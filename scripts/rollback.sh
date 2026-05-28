#!/usr/bin/env bash
# =============================================
# AI API 聚合平台 — 三层回滚脚本
# =============================================
# 功能：
#   Layer 1 (流量回滚): 通过 HAProxy socket 瞬间切回旧实例
#   Layer 2 (容器回滚): docker-compose 停新实例、启旧版本
#   Layer 3 (数据回滚): 从最新 SQLite 备份恢复数据库
#
# 用法：
#   ./rollback.sh --layer 1                # 仅流量回滚（默认交互确认）
#   ./rollback.sh --layer 2 --auto         # 容器回滚（自动执行）
#   ./rollback.sh --layer 3 --backup <file> # 从指定备份恢复
#   ./rollback.sh --layer 1 --layer 2      # 多层回滚（L1→L2）
#   ./rollback.sh --status                 # 查看回滚操作历史
#
# 环境变量（从 docker/.env 读取）：
#   ONEAPI_ADMIN_TOKEN      OneAPI 管理员 Token
#   TELEGRAM_BOT_TOKEN      Telegram Bot Token
#   TELEGRAM_CHAT_ID        Telegram Chat ID
# =============================================

set -euo pipefail

# ==========================================
# 路径
# ==========================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DOCKER_DIR="$PROJECT_DIR/docker"
LOG_DIR="$PROJECT_DIR/logs"
BACKUP_DIR="$PROJECT_DIR/backups"
ENV_FILE="$DOCKER_DIR/.env"
BG_SWITCH_SCRIPT="$SCRIPT_DIR/bluegreen-switch.sh"
RESTORE_SCRIPT="$SCRIPT_DIR/restore.sh"
mkdir -p "$LOG_DIR"

ROLLBACK_LOG="$LOG_DIR/rollback.log"

# ==========================================
# 颜色
# ==========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ==========================================
# 默认配置
# ==========================================
AUTO_MODE=false
LAYERS=()
BACKUP_FILE=""
HAPROXY_CONTAINER="ai-api-agg-haproxy"
HAPROXY_SOCK="/var/run/haproxy.sock"

# ==========================================
# 日志函数
# ==========================================
log() {
    local level="$1"; shift
    local color=""
    case "$level" in
        INFO)  color="$CYAN" ;;
        OK)    color="$GREEN" ;;
        WARN)  color="$YELLOW" ;;
        ERROR) color="$RED" ;;
        ALERT) color="$RED" ;;
        *)     color="$NC" ;;
    esac
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
    echo -e "${color}${msg}${NC}"
    echo "$msg" >> "$ROLLBACK_LOG"
}

log_info()  { log INFO "$@"; }
log_ok()    { log OK "$@"; }
log_warn()  { log WARN "$@"; }
log_error() { log ERROR "$@"; }
log_alert() { log ALERT "$@"; }

# ==========================================
# 加载环境变量
# ==========================================
load_env() {
    if [ -f "$ENV_FILE" ]; then
        set -a
        # shellcheck source=/dev/null
        source "$ENV_FILE"
        set +a
    fi
}

NOTIFY_SCRIPT="$SCRIPT_DIR/ops-notify.sh"

# ==========================================
# 运维通知（通过统一通知脚本 ops-notify.sh）
# ==========================================
send_notify() {
    local level="$1" title="$2" message="$3"
    if [ -x "$NOTIFY_SCRIPT" ]; then
        "$NOTIFY_SCRIPT" --level "$level" --title "$title" --message "$message" --silent || true
    fi
}

# ==========================================
# 记录回滚操作
# ==========================================
record_rollback() {
    local layer="$1"
    local action="$2"
    local result="$3"
    local details="${4:-}"

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] L${layer} | ${action} | ${result} | ${details}" >> "$ROLLBACK_LOG"

    send_notify "$([ "$result" = "SUCCESS" ] && echo "info" || echo "critical")" "回滚 L${layer}: ${action}" "层级: L${layer}
操作: ${action}
结果: ${result}
详情: ${details}
时间: $(date '+%Y-%m-%d %H:%M:%S')"
}

# ==========================================
# HAProxy Socket 命令
# ==========================================
haproxy_cmd() {
    docker compose -f "$DOCKER_DIR/docker-compose.yml" exec -T haproxy \
        sh -c "echo '$1' | socat stdio '$HAPROXY_SOCK'" 2>/dev/null || {
        log_warn "HAProxy socket 命令失败: $1"
        return 1
    }
}

set_server_weight() {
    local backend="$1"
    local weight="$2"
    haproxy_cmd "set weight $backend $weight"
}

get_server_weight() {
    local backend="$1"
    haproxy_cmd "show stat" | grep "$backend" | cut -d',' -f19 2>/dev/null || echo "unknown"
}

# ==========================================
# 获取当前活跃实例
# ==========================================
get_active() {
    local blue_w green_w
    blue_w=$(get_server_weight "oneapi_pool/oneapi-blue" 2>/dev/null || echo "0")
    green_w=$(get_server_weight "oneapi_pool/oneapi-green" 2>/dev/null || echo "0")

    if [ "$blue_w" -gt "$green_w" ] 2>/dev/null; then
        echo "blue"
    elif [ "$green_w" -gt "$blue_w" ] 2>/dev/null; then
        echo "green"
    else
        # 权重相同，检查容器状态
        local blue_running
        blue_running=$(docker inspect "ai-api-agg-oneapi-blue" --format '{{.State.Status}}' 2>/dev/null || echo "stopped")
        if [ "$blue_running" = "running" ]; then
            echo "blue"
        else
            echo "green"
        fi
    fi
}

# ==========================================
# 用户确认
# ==========================================
confirm_action() {
    local prompt="$1"

    if [ "$AUTO_MODE" = true ]; then
        log_info "自动模式: 跳过确认 — $prompt"
        return 0
    fi

    echo ""
    echo -e "${YELLOW}${BOLD}⚠  确认操作${NC}"
    echo -e "${YELLOW}$prompt${NC}"
    echo ""
    read -r -p "确认执行? (y/N): " answer
    case "$answer" in
        [Yy]|[Yy][Ee][Ss]) return 0 ;;
        *) return 1 ;;
    esac
}

# ==========================================
# Layer 1: 流量回滚
# ==========================================
rollback_layer1() {
    echo ""
    echo -e "${BOLD}${RED}=============================================${NC}"
    echo -e "${BOLD}${RED}  Layer 1: 流量回滚 (HAProxy 权重切换)${NC}"
    echo -e "${BOLD}${RED}=============================================${NC}"
    echo ""

    local active standby
    active=$(get_active)
    if [ "$active" = "blue" ]; then
        standby="green"
    else
        standby="blue"
    fi

    log_info "当前活跃: $active → 即将切回: $standby"

    if ! confirm_action "将流量从 $active 切回 $standby (零停机)"; then
        log_info "用户取消 Layer 1 回滚"
        return 0
    fi

    # 执行切换
    local target_backend active_backend
    if [ "$standby" = "blue" ]; then
        target_backend="oneapi_pool/oneapi-blue"
        active_backend="oneapi_pool/oneapi-green"
    else
        target_backend="oneapi_pool/oneapi-green"
        active_backend="oneapi_pool/oneapi-blue"
    fi

    log_info "执行流量切换: $active (weight→0), $standby (weight→100)"

    # 动态调整权重
    set_server_weight "$active_backend" 0
    sleep 1
    set_server_weight "$target_backend" 100

    # 验证
    sleep 3
    local new_w
    new_w=$(get_server_weight "$target_backend")

    if [ "$new_w" = "100" ]; then
        log_ok "Layer 1 回滚成功: 流量已切回 $standby"
        record_rollback "1" "流量回滚" "SUCCESS" "active=$active → standby=$standby"
        return 0
    else
        log_error "Layer 1 回滚失败: $standby 权重 = $new_w (期望 100)"
        record_rollback "1" "流量回滚" "FAILED" "权重验证失败: actual=$new_w expected=100"
        return 1
    fi
}

# ==========================================
# Layer 2: 容器回滚
# ==========================================
rollback_layer2() {
    echo ""
    echo -e "${BOLD}${RED}=============================================${NC}"
    echo -e "${BOLD}${RED}  Layer 2: 容器回滚 (Docker Compose 版本回退)${NC}"
    echo -e "${BOLD}${RED}=============================================${NC}"
    echo ""

    local active standby
    active=$(get_active)
    if [ "$active" = "blue" ]; then
        standby="green"
    else
        standby="blue"
    fi

    # 获取当前/旧镜像版本
    local active_image standby_image
    active_image=$(docker inspect "ai-api-agg-oneapi-${active}" --format '{{.Config.Image}}' 2>/dev/null || echo "unknown")
    standby_image=$(docker inspect "ai-api-agg-oneapi-${standby}" --format '{{.Config.Image}}' 2>/dev/null || echo "unknown")

    log_info "当前活跃: $active ($active_image)"
    log_info "待启用:   $standby ($standby_image)"

    # 检查是否有旧版本镜像可用
    local image_history
    image_history=$(docker image ls --format "{{.Repository}}:{{.Tag}}" "justsong/one-api*" 2>/dev/null | head -5 || true)

    echo ""
    log_info "可用 OneAPI 镜像:"
    echo "$image_history" | while read -r img; do
        echo "  - $img"
    done

    if ! confirm_action "将 $active 停止并用旧版本重启 $standby (服务会中断 30s)"; then
        log_info "用户取消 Layer 2 回滚"
        return 0
    fi

    # 先做 L1 切流到 standby（如果可能）
    log_info "步骤 1/4: 先将流量切到备用实例 ($standby)..."
    if [ "$active" = "blue" ]; then
        set_server_weight "oneapi_pool/oneapi-blue" 0
        set_server_weight "oneapi_pool/oneapi-green" 100
    else
        set_server_weight "oneapi_pool/oneapi-green" 0
        set_server_weight "oneapi_pool/oneapi-blue" 100
    fi
    sleep 2

    # 停止问题实例
    log_info "步骤 2/4: 停止 $active 实例..."
    docker compose -f "$DOCKER_DIR/docker-compose.yml" stop "oneapi-${active}"

    # 如果 standby 也在运行但有问题，重启它
    log_info "步骤 3/4: 重启 $standby 确保可用..."
    docker compose -f "$DOCKER_DIR/docker-compose.yml" restart "oneapi-${standby}"

    # 等待启动
    sleep 10

    # 健康检查
    log_info "步骤 4/4: 健康检查..."
    local port
    [ "$standby" = "blue" ] && port=3001 || port=3002

    local retry=0
    while [ $retry -lt 6 ]; do
        local code
        code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
            "http://localhost:${port}/api/status" 2>/dev/null || echo "000")
        if [ "$code" = "200" ]; then
            log_ok "Layer 2 回滚成功: $standby 健康检查通过"
            record_rollback "2" "容器回滚" "SUCCESS" "stopped=$active restarted=$standby image=$standby_image"
            return 0
        fi
        retry=$((retry + 1))
        log_warn "健康检查重试 $retry/6..."
        sleep 5
    done

    log_error "Layer 2 回滚: $standby 启动后健康检查失败"
    record_rollback "2" "容器回滚" "FAILED" "$standby 健康检查失败"
    return 1
}

# ==========================================
# Layer 3: 数据回滚
# ==========================================
rollback_layer3() {
    echo ""
    echo -e "${BOLD}${RED}=============================================${NC}"
    echo -e "${BOLD}${RED}  Layer 3: 数据回滚 (SQLite 备份恢复)${NC}"
    echo -e "${BOLD}${RED}=============================================${NC}"
    echo ""

    # 查找可用备份
    local backup_list=""
    if [ -d "$BACKUP_DIR/full" ]; then
        backup_list=$(ls -1t "$BACKUP_DIR/full/"*.tar.gz 2>/dev/null || true)
    fi

    if [ -z "$backup_list" ] && [ -z "$BACKUP_FILE" ]; then
        log_error "未找到任何备份文件"
        echo ""
        echo "可用恢复方式:"
        echo "  1. 指定备份文件: ./rollback.sh --layer 3 --backup <file.tar.gz>"
        echo "  2. 先运行备份:   ./scripts/backup.sh"
        echo ""
        return 1
    fi

    # 选择备份文件
    local restore_file="$BACKUP_FILE"
    if [ -z "$restore_file" ]; then
        echo ""
        echo -e "${BOLD}可用备份:${NC}"
        echo "$backup_list" | nl -w2 -s'. '
        echo ""

        if [ "$AUTO_MODE" = true ]; then
            # 自动模式使用最新备份
            restore_file=$(echo "$backup_list" | head -1)
            log_info "自动模式: 使用最新备份 — $restore_file"
        else
            read -r -p "选择备份编号 (默认: 1 = 最新): " choice
            choice="${choice:-1}"
            restore_file=$(echo "$backup_list" | sed -n "${choice}p")
        fi
    fi

    if [ ! -f "$restore_file" ]; then
        log_error "备份文件不存在: $restore_file"
        return 1
    fi

    log_info "将从以下备份恢复: $restore_file"

    if ! confirm_action "数据回滚将覆盖当前数据库，此操作不可逆！"; then
        log_info "用户取消 Layer 3 回滚"
        return 0
    fi

    # 1. 创建当前数据的安全副本
    log_info "步骤 1/5: 创建当前数据的安全副本..."
    local safety_dir="$BACKUP_DIR/pre_rollback_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$safety_dir"

    # 从运行的容器中复制数据库（任一实例）
    for instance in blue green; do
        if docker inspect "ai-api-agg-oneapi-${instance}" --format '{{.State.Status}}' 2>/dev/null | grep -q "running"; then
            docker compose -f "$DOCKER_DIR/docker-compose.yml" cp \
                "oneapi-${instance}:/data/one-api.db" "$safety_dir/one-api.db.${instance}" 2>/dev/null || true
            break
        fi
    done
    log_ok "安全副本已保存到: $safety_dir"

    # 2. 停止两个实例
    log_info "步骤 2/5: 暂停 OneAPI 实例..."
    docker compose -f "$DOCKER_DIR/docker-compose.yml" stop oneapi-blue oneapi-green 2>/dev/null || true

    # 3. 恢复数据库
    log_info "步骤 3/5: 恢复 SQLite 数据库..."
    local temp_dir
    temp_dir=$(mktemp -d)
    tar xzf "$restore_file" -C "$temp_dir"

    # 查找备份中的 oneapi.db
    local backup_db
    backup_db=$(find "$temp_dir" -name "oneapi.db" -type f 2>/dev/null | head -1)

    if [ -z "$backup_db" ]; then
        log_error "备份中未找到 oneapi.db"
        # 回滚安全副本
        log_warn "恢复安全副本..."
        docker compose -f "$DOCKER_DIR/docker-compose.yml" start oneapi-blue oneapi-green
        rm -rf "$temp_dir"
        return 1
    fi

    # 校验数据库完整性
    log_info "步骤 4/5: 校验数据库完整性..."
    if command -v sqlite3 &>/dev/null; then
        if ! sqlite3 "$backup_db" "PRAGMA integrity_check;" 2>/dev/null | grep -q "ok"; then
            log_error "备份数据库完整性检查失败！"
            docker compose -f "$DOCKER_DIR/docker-compose.yml" start oneapi-blue oneapi-green
            rm -rf "$temp_dir"
            return 1
        fi
        log_ok "数据库完整性校验通过"
    else
        log_warn "sqlite3 未安装，跳过完整性校验"
    fi

    # 复制到两个实例的数据卷
    # 先启动一个临时容器来复制数据
    log_info "步骤 5/5: 部署恢复后的数据库..."
    for instance in blue green; do
        # 使用 docker compose cp 反向复制
        docker compose -f "$DOCKER_DIR/docker-compose.yml" up -d "oneapi-${instance}" 2>/dev/null || true
        sleep 2
        docker compose -f "$DOCKER_DIR/docker-compose.yml" cp \
            "$backup_db" "oneapi-${instance}:/data/one-api.db" 2>/dev/null || true
        docker compose -f "$DOCKER_DIR/docker-compose.yml" stop "oneapi-${instance}" 2>/dev/null || true
    done

    rm -rf "$temp_dir"

    # 启动实例
    log_info "启动 OneAPI 实例..."
    docker compose -f "$DOCKER_DIR/docker-compose.yml" start oneapi-blue oneapi-green

    # 等待并验证
    sleep 10
    local all_ok=true
    for instance in blue green; do
        local port
        [ "$instance" = "blue" ] && port=3001 || port=3002
        if curl -sf --max-time 5 "http://localhost:${port}/api/status" >/dev/null 2>&1; then
            log_ok "$instance (:${port}) 恢复后健康检查通过"
        else
            log_error "$instance (:${port}) 恢复后健康检查失败"
            all_ok=false
        fi
    done

    if [ "$all_ok" = true ]; then
        log_ok "Layer 3 数据回滚完成"
        record_rollback "3" "数据回滚" "SUCCESS" "backup=$restore_file safety=$safety_dir"
        return 0
    else
        log_error "Layer 3 数据回滚: 部分实例启动失败"
        log_warn "安全副本位于: $safety_dir"
        record_rollback "3" "数据回滚" "PARTIAL" "部分实例启动失败 safety=$safety_dir"
        return 1
    fi
}

# ==========================================
# 状态显示
# ==========================================
show_status() {
    echo -e "${BOLD}${CYAN}=============================================${NC}"
    echo -e "${BOLD}${CYAN}  回滚操作历史${NC}"
    echo -e "${BOLD}${CYAN}=============================================${NC}"
    echo ""

    if [ -f "$ROLLBACK_LOG" ]; then
        tail -30 "$ROLLBACK_LOG"
    else
        echo "  尚无回滚操作记录"
    fi

    echo ""
    echo -e "${BOLD}备份文件:${NC}"
    if [ -d "$BACKUP_DIR/full" ]; then
        ls -1th "$BACKUP_DIR/full/"*.tar.gz 2>/dev/null | head -10 || echo "  (无全量备份)"
    else
        echo "  (备份目录不存在)"
    fi
}

# ==========================================
# 使用帮助
# ==========================================
usage() {
    cat << 'EOF'
用法: rollback.sh [选项]

选项:
  --layer <1|2|3>        回滚层级 (可多次指定, 按 L1→L2→L3 顺序执行)
  --auto                  自动模式（跳过交互确认）
  --backup <file>         Layer 3 使用的备份文件路径
  --status                查看回滚操作历史

回滚层级说明:
  L1: 流量回滚 — HAProxy 权重瞬间切回旧实例（秒级，零停机）
  L2: 容器回滚 — 停止新实例，重启旧版本容器（分钟级，短暂中断）
  L3: 数据回滚 — 从 SQLite 备份恢复数据库（分钟级，数据回退）

示例:
  ./rollback.sh --layer 1                   # 交互式 L1 回滚
  ./rollback.sh --layer 2 --auto            # 自动 L2 回滚
  ./rollback.sh --layer 1 --layer 2         # 多层回滚
  ./rollback.sh --layer 3 --backup backups/full/20260528_120000.tar.gz
  ./rollback.sh --status                    # 查看历史

环境变量（从 docker/.env 读取）:
  TELEGRAM_BOT_TOKEN       Telegram Bot Token
  TELEGRAM_CHAT_ID         Telegram Chat ID
EOF
}

# ==========================================
# 主流程
# ==========================================
main() {
    load_env

    # 解析参数
    if [ $# -eq 0 ]; then
        usage
        exit 1
    fi

    while [ $# -gt 0 ]; do
        case "$1" in
            --layer)
                LAYERS+=("$2")
                shift 2
                ;;
            --auto)
                AUTO_MODE=true
                shift
                ;;
            --backup)
                BACKUP_FILE="$2"
                shift 2
                ;;
            --status)
                show_status
                exit 0
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                usage
                exit 1
                ;;
        esac
    done

    if [ ${#LAYERS[@]} -eq 0 ]; then
        log_error "请指定至少一个 --layer 参数"
        usage
        exit 1
    fi

    # 排序并去重 layers
    IFS=$'\n' LAYERS=($(printf '%s\n' "${LAYERS[@]}" | sort -un))

    # 验证 layer 值
    for layer in "${LAYERS[@]}"; do
        if [ "$layer" != "1" ] && [ "$layer" != "2" ] && [ "$layer" != "3" ]; then
            log_error "无效 layer: $layer (有效值: 1, 2, 3)"
            exit 1
        fi
    done

    # 概述即将执行的操作
    echo ""
    echo -e "${BOLD}${RED}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${RED}║  ⚠  回滚操作 — 生产环境保护             ║${NC}"
    echo -e "${BOLD}${RED}╚═══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  将执行层级: ${CYAN}${LAYERS[*]}${NC}"
    echo -e "  运行模式:   ${CYAN}$([ "$AUTO_MODE" = true ] && echo '自动（无确认）' || echo '交互（需确认）')${NC}"
    echo -e "  日志文件:   ${CYAN}${ROLLBACK_LOG}${NC}"
    echo ""

    # 按顺序执行各层回滚
    local overall_success=true
    for layer in "${LAYERS[@]}"; do
        case "$layer" in
            1)
                if ! rollback_layer1; then
                    overall_success=false
                    log_alert "Layer 1 回滚失败，后续层级仍将继续"
                fi
                ;;
            2)
                if ! rollback_layer2; then
                    overall_success=false
                    log_alert "Layer 2 回滚失败"
                fi
                ;;
            3)
                if ! rollback_layer3; then
                    overall_success=false
                    log_alert "Layer 3 回滚失败"
                fi
                ;;
        esac
    done

    # 总结
    echo ""
    echo -e "${BOLD}=============================================${NC}"
    if [ "$overall_success" = true ]; then
        echo -e "${BOLD}${GREEN}  回滚操作全部完成${NC}"
        send_notify "warning" "回滚操作完成" "层级: ${LAYERS[*]}
模式: $([ "$AUTO_MODE" = true ] && echo '自动' || echo '手动')
时间: $(date '+%Y-%m-%d %H:%M:%S')"
    else
        echo -e "${BOLD}${RED}  回滚操作部分失败，请检查日志${NC}"
        send_notify "critical" "回滚操作异常" "层级: ${LAYERS[*]}
部分步骤失败
日志: ${ROLLBACK_LOG}
时间: $(date '+%Y-%m-%d %H:%M:%S')"
    fi
    echo -e "${BOLD}=============================================${NC}"
}

main "$@"
