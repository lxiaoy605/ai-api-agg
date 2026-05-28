#!/usr/bin/env bash
# =============================================
# AI API 聚合平台 — 蓝绿切换脚本
# =============================================
# 功能：
#   1. 完全切换（instant）：Blue ↔ Green 流量瞬间切换
#   2. 灰度迁移（gradual）：逐步调整权重，每个 step 等待观察
#   3. 通过 HAProxy Unix Socket 动态调整权重（零中断）
#   4. 切换后验证新实例健康状态
#   5. Telegram Bot 通知切换完成
#   6. 日志写入 logs/bluegreen.log + 状态持久化到 logs/bluegreen.state
#   7. 支持 --pool oneapi|backend 双池管理
#
# 用法：
#   ./bluegreen-switch.sh status                              # 查看所有池状态
#   ./bluegreen-switch.sh status --pool backend               # 仅查看后端池
#   ./bluegreen-switch.sh --target green --mode instant       # 瞬间切 OneAPI 到 Green
#   ./bluegreen-switch.sh --pool backend --target green --mode instant  # 切后端到 Green
#   ./bluegreen-switch.sh --target blue --mode gradual --weight 30
#   ./bluegreen-switch.sh rollback                            # 回滚 OneAPI
#   ./bluegreen-switch.sh rollback --pool backend             # 回滚后端
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
ENV_FILE="$DOCKER_DIR/.env"
mkdir -p "$LOG_DIR"

STATE_FILE="$LOG_DIR/bluegreen.state"
BG_LOG="$LOG_DIR/bluegreen.log"

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
TARGET=""
MODE="instant"
WEIGHT=100
GRADUAL_STEP=20      # 每次灰度步进 %
GRADUAL_INTERVAL=30  # 每步间等待秒数
HAPROXY_CONTAINER="ai-api-agg-haproxy"
HAPROXY_SOCK="/var/run/haproxy.sock"

# 池类型: oneapi (默认) 或 backend
POOL="oneapi"

# 以下变量由 setup_pool_config() 根据 POOL 动态设置
POOL_BACKEND=""       # HAProxy backend 名称 (oneapi_pool / backend_pool)
BLUE_HOST=""          # 蓝实例 Docker 网络主机名
BLUE_PORT=""          # 蓝实例容器内端口
GREEN_HOST=""         # 绿实例 Docker 网络主机名
GREEN_PORT=""         # 绿实例容器内端口
BLUE_EXTERNAL_PORT="" # 蓝实例宿主机端口
GREEN_EXTERNAL_PORT=""# 绿实例宿主机端口
HEALTH_ENDPOINT=""    # 健康检查路径
CONTAINER_BLUE=""     # 蓝实例容器名
CONTAINER_GREEN=""    # 绿实例容器名
SERVICE_BLUE=""       # docker compose 服务名
SERVICE_GREEN=""      # docker compose 服务名

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
        *)     color="$NC" ;;
    esac
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
    echo -e "${color}${msg}${NC}"
    echo "$msg" >> "$BG_LOG"
}

log_info()  { log INFO "$@"; }
log_ok()    { log OK "$@"; }
log_warn()  { log WARN "$@"; }
log_error() { log ERROR "$@"; }

# ==========================================
# 加载环境变量
# ==========================================
load_env() {
    if [ -f "$ENV_FILE" ]; then
        # shellcheck source=/dev/null
        set -a
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
# 根据池类型设置配置变量
# ==========================================
setup_pool_config() {
    if [ "$POOL" = "backend" ]; then
        POOL_BACKEND="backend_pool"
        BLUE_HOST="backend-blue"
        BLUE_PORT="8080"
        GREEN_HOST="backend-green"
        GREEN_PORT="8080"
        BLUE_EXTERNAL_PORT="${BACKEND_BLUE_PORT:-8082}"
        GREEN_EXTERNAL_PORT="${BACKEND_GREEN_PORT:-8083}"
        HEALTH_ENDPOINT="/health"
        CONTAINER_BLUE="ai-api-agg-backend-blue"
        CONTAINER_GREEN="ai-api-agg-backend-green"
        SERVICE_BLUE="backend-blue"
        SERVICE_GREEN="backend-green"
    else
        POOL_BACKEND="oneapi_pool"
        BLUE_HOST="oneapi-blue"
        BLUE_PORT="3000"
        GREEN_HOST="oneapi-green"
        GREEN_PORT="3000"
        BLUE_EXTERNAL_PORT=3001
        GREEN_EXTERNAL_PORT=3002
        HEALTH_ENDPOINT="/api/status"
        CONTAINER_BLUE="ai-api-agg-oneapi-blue"
        CONTAINER_GREEN="ai-api-agg-oneapi-green"
        SERVICE_BLUE="oneapi-blue"
        SERVICE_GREEN="oneapi-green"
    fi
}

# ==========================================
# HAProxy backend 路径（含池名前缀）
# ==========================================
backend_path() {
    local instance="$1"  # blue 或 green
    if [ "$instance" = "blue" ]; then
        echo "${POOL_BACKEND}/${BLUE_HOST}"
    else
        echo "${POOL_BACKEND}/${GREEN_HOST}"
    fi
}

# ==========================================
# 状态管理
# ==========================================
get_state_key() {
    # 状态键格式: <pool>_active
    echo "${POOL}_active"
}

get_state() {
    local key
    key=$(get_state_key)
    if [ -f "$STATE_FILE" ]; then
        grep "^${key}=" "$STATE_FILE" 2>/dev/null | cut -d= -f2 || echo "blue"
    else
        echo "blue"
    fi
}

set_state() {
    local key new_state
    key=$(get_state_key)
    new_state="$1"

    if [ -f "$STATE_FILE" ]; then
        if grep -q "^${key}=" "$STATE_FILE" 2>/dev/null; then
            sed -i "s/^${key}=.*/${key}=${new_state}/" "$STATE_FILE"
        else
            echo "${key}=${new_state}" >> "$STATE_FILE"
        fi
    else
        echo "${key}=${new_state}" > "$STATE_FILE"
    fi
    log_info "[${POOL}] 状态已更新: $new_state"
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

# 获取后端 server 当前 weight
get_server_weight() {
    local backend="$1"
    haproxy_cmd "show stat" | grep "$backend" | cut -d',' -f19 2>/dev/null || echo "unknown"
}

# 设置后端 server 权重
set_server_weight() {
    local backend="$1"
    local weight="$2"
    haproxy_cmd "set weight $backend $weight"
}

# 获取后端状态
get_server_status() {
    local backend="$1"
    haproxy_cmd "show stat" | grep "$backend" | cut -d',' -f18 2>/dev/null || echo "unknown"
}

# ==========================================
# 健康检查
# ==========================================
health_check() {
    local name="$1"
    local port="$2"
    local retries="${3:-6}"
    local count=0

    while [ $count -lt $retries ]; do
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
            "http://localhost:${port}${HEALTH_ENDPOINT}" 2>/dev/null || echo "000")

        if [ "$http_code" = "200" ]; then
            log_ok "[${POOL}] $name 健康检查通过 (HTTP $http_code, 尝试 $((count+1)))"
            return 0
        fi
        count=$((count + 1))
        log_warn "[${POOL}] $name 返回 HTTP $http_code (尝试 $count/$retries)"
        sleep 5
    done

    log_error "[${POOL}] $name 健康检查失败: $retries 次尝试后仍不健康"
    return 1
}

# ==========================================
# 模式1: 完全切换 (instant cutover)
# ==========================================
switch_instant() {
    local target="$1"  # "blue" 或 "green"
    local current
    current=$(get_state)

    if [ "$target" = "$current" ]; then
        log_info "[${POOL}] 已经是 $target，无需切换"
        return 0
    fi

    local target_port target_host target_backend
    local current_host current_backend

    if [ "$target" = "green" ]; then
        target_host="$GREEN_HOST"
        target_port="$GREEN_EXTERNAL_PORT"
        target_backend=$(backend_path "green")
        current_backend=$(backend_path "blue")
    else
        target_host="$BLUE_HOST"
        target_port="$BLUE_EXTERNAL_PORT"
        target_backend=$(backend_path "blue")
        current_backend=$(backend_path "green")
    fi

    echo ""
    echo -e "${BOLD}${CYAN}=============================================${NC}"
    echo -e "${BOLD}${CYAN}  蓝绿切换 [${POOL}]: ${current^^} → ${target^^} (完全切换)${NC}"
    echo -e "${BOLD}${CYAN}=============================================${NC}"
    echo ""

    # 1. 确保目标实例运行
    log_info "步骤 1/5: 确保目标实例 ($target) 运行中..."
    local compose_svc
    if [ "$target" = "green" ]; then
        compose_svc="$SERVICE_GREEN"
    else
        compose_svc="$SERVICE_BLUE"
    fi
    docker compose -f "$DOCKER_DIR/docker-compose.yml" up -d "$compose_svc" 2>&1 | tee -a "$BG_LOG"

    # 2. 健康检查目标实例
    log_info "步骤 2/5: 目标实例健康检查 (${target_host}:${target_port}${HEALTH_ENDPOINT})..."
    if ! health_check "$target_host" "$target_port" 6; then
        log_error "目标实例不健康，终止切换"
        send_notify "critical" "蓝绿切换失败 [${POOL}]" "切换 ${current} → ${target} 失败: 目标实例健康检查未通过"
        return 1
    fi

    # 3. 通过 HAProxy Socket 动态切换权重
    log_info "步骤 3/5: 切换流量: $current (weight→0), $target (weight→100)..."
    set_server_weight "$current_backend" 0
    set_server_weight "$target_backend" 100

    # 4. 验证权重已生效
    sleep 2
    local target_w
    target_w=$(get_server_weight "$target_backend")
    log_info "步骤 4/5: 验证权重 — $target = $target_w (期望 100)"

    if [ "$target_w" != "100" ]; then
        log_error "权重未正确切换 (当前: $target_w)，请手动检查 HAProxy"
        return 1
    fi

    # 5. 验证新实例可正常提供服务
    log_info "步骤 5/5: 验证新实例可正常提供服务..."
    sleep 3
    local test_code
    test_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
        "http://localhost:${target_port}${HEALTH_ENDPOINT}" 2>/dev/null || echo "000")
    if [ "$test_code" = "200" ]; then
        log_ok "[${POOL}] 新实例 ($target) 服务验证通过"
    else
        log_warn "[${POOL}] 新实例验证返回 HTTP $test_code，但权重已切换，请人工确认"
    fi

    # 更新状态
    set_state "$target"

    send_notify "warning" "蓝绿切换完成 [${POOL}]" "环境: ${ENVIRONMENT:-production}
池: ${POOL}
切换: ${current} → ${target}
模式: instant
时间: $(date '+%Y-%m-%d %H:%M:%S')"

    echo ""
    log_ok "[${POOL}] 切换完成！$target 现为 ACTIVE (weight=100)"
    return 0
}

# ==========================================
# 模式2: 灰度迁移 (gradual rollover)
# ==========================================
switch_gradual() {
    local target="$1"
    local target_weight="$2"

    local current
    current=$(get_state)

    if [ "$target" = "$current" ] && [ "$target_weight" -eq 100 ]; then
        log_info "[${POOL}] 已经是 $target (weight=100)，无需切换"
        return 0
    fi

    local target_backend current_backend target_port
    if [ "$target" = "green" ]; then
        target_backend=$(backend_path "green")
        current_backend=$(backend_path "blue")
        target_port="$GREEN_EXTERNAL_PORT"
    else
        target_backend=$(backend_path "blue")
        current_backend=$(backend_path "green")
        target_port="$BLUE_EXTERNAL_PORT"
    fi

    echo ""
    echo -e "${BOLD}${CYAN}=============================================${NC}"
    echo -e "${BOLD}${CYAN}  灰度迁移 [${POOL}]: → ${target^^} (目标 ${target_weight}%)${NC}"
    echo -e "${BOLD}${CYAN}=============================================${NC}"
    echo ""

    # 1. 确保目标实例运行
    log_info "步骤 1/4: 确保目标实例 ($target) 运行中..."
    local compose_svc
    if [ "$target" = "green" ]; then
        compose_svc="$SERVICE_GREEN"
    else
        compose_svc="$SERVICE_BLUE"
    fi
    docker compose -f "$DOCKER_DIR/docker-compose.yml" up -d "$compose_svc" 2>&1 | tee -a "$BG_LOG"

    # 2. 健康检查
    log_info "步骤 2/4: 目标实例健康检查..."
    if ! health_check "$target" "$target_port" 3; then
        log_error "目标实例不健康，终止灰度迁移"
        return 1
    fi

    # 3. 逐步增加权重
    log_info "步骤 3/4: 灰度引流..."
    local current_weight=0
    while [ "$current_weight" -lt "$target_weight" ]; do
        local next_weight=$((current_weight + GRADUAL_STEP))
        if [ "$next_weight" -gt "$target_weight" ]; then
            next_weight="$target_weight"
        fi

        local from_weight=$((100 - next_weight))

        log_info "  调整权重: $target → ${next_weight}%, ${current} → ${from_weight}%"
        set_server_weight "$target_backend" "$next_weight"
        set_server_weight "$current_backend" "$from_weight"

        # 等待观察
        log_info "  等待 ${GRADUAL_INTERVAL}s 观察..."
        sleep "$GRADUAL_INTERVAL"

        # 验证步骤后的健康状态
        local target_status
        target_status=$(get_server_status "$target_backend")
        if [ "$target_status" != "UP" ] && [ "$target_status" != "UP 1/2" ] && [ "$target_status" != "UP 1/3" ]; then
            log_error "灰度过程中 $target 状态异常: $target_status，回滚！"
            set_server_weight "$target_backend" 0
            set_server_weight "$current_backend" 100
            send_notify "critical" "灰度迁移中止 [${POOL}]" "目标 $target 在 ${next_weight}% 阶段状态异常，已自动回滚"
            return 1
        fi

        current_weight="$next_weight"
    done

    # 4. 完成后验证
    log_info "步骤 4/4: 灰度完成，最终验证..."
    sleep 5
    local final_w
    final_w=$(get_server_weight "$target_backend")
    log_ok "[${POOL}] 灰度迁移完成: $target 权重 = $final_w%"

    # 如果达到 100%，更新状态
    if [ "$target_weight" -eq 100 ]; then
        set_state "$target"
    else
        # 部分灰度，状态记录权重
        set_state "${current}:$((100 - target_weight)),${target}:${target_weight}"
    fi

    send_notify "warning" "灰度迁移完成 [${POOL}]" "环境: ${ENVIRONMENT:-production}
池: ${POOL}
目标: ${target} = ${target_weight}%
当前活跃: ${current} = $((100 - target_weight))%
时间: $(date '+%Y-%m-%d %H:%M:%S')"

    return 0
}

# ==========================================
# 回滚（快捷方式）
# ==========================================
do_rollback() {
    local current
    current=$(get_state | cut -d',' -f1 | cut -d':' -f1)
    local target

    if [ "$current" = "blue" ]; then
        target="green"
    else
        target="blue"
    fi

    log_warn "[${POOL}] 回滚操作: 切回 $target"
    switch_instant "$target"
}

# ==========================================
# 状态显示（单个池）
# ==========================================
show_pool_status() {
    local pool_label="$1"
    local backend_pool="$2"
    local container_blue="$3"
    local container_green="$4"
    local ext_port_blue="$5"
    local ext_port_green="$6"

    local state_key="${pool_label}_active"
    local state
    state=$(grep "^${state_key}=" "$STATE_FILE" 2>/dev/null | cut -d= -f2 || echo "blue")

    echo -e "  ${BOLD}池: ${pool_label}${NC}"
    echo -e "  ${BOLD}当前活跃:${NC} ${GREEN}${state}${NC}"

    # Blue 容器状态
    local blue_status
    blue_status=$(docker inspect "$container_blue" --format '{{.State.Status}}' 2>/dev/null || echo "stopped")
    local blue_symbol=""
    case "$blue_status" in
        running) blue_symbol="${GREEN}●${NC}" ;;
        *)       blue_symbol="${RED}●${NC}" ;;
    esac
    echo -e "  Blue  (:${ext_port_blue}): ${blue_symbol} $blue_status"

    # Green 容器状态
    local green_status
    green_status=$(docker inspect "$container_green" --format '{{.State.Status}}' 2>/dev/null || echo "stopped")
    local green_symbol=""
    case "$green_status" in
        running) green_symbol="${GREEN}●${NC}" ;;
        *)       green_symbol="${RED}●${NC}" ;;
    esac
    echo -e "  Green (:${ext_port_green}): ${green_symbol} $green_status"

    # 权重信息（如果 HAProxy 运行中）
    local haproxy_status
    haproxy_status=$(docker inspect "$HAPROXY_CONTAINER" --format '{{.State.Status}}' 2>/dev/null || echo "stopped")
    if [ "$haproxy_status" = "running" ]; then
        # 从 pool label 推断 HAProxy backend 名称
        local ha_bp
        if [ "$pool_label" = "backend" ]; then
            ha_bp="backend_pool"
        else
            ha_bp="oneapi_pool"
        fi

        local blue_w green_w blue_st green_st
        blue_w=$(get_server_weight "${ha_bp}/${container_blue#ai-api-agg-}" 2>/dev/null || echo "N/A")
        green_w=$(get_server_weight "${ha_bp}/${container_green#ai-api-agg-}" 2>/dev/null || echo "N/A")
        blue_st=$(get_server_status "${ha_bp}/${container_blue#ai-api-agg-}" 2>/dev/null || echo "N/A")
        green_st=$(get_server_status "${ha_bp}/${container_green#ai-api-agg-}" 2>/dev/null || echo "N/A")

        # 修复容器名映射到 HAProxy server 名
        local ha_blue ha_green
        if [ "$pool_label" = "backend" ]; then
            ha_blue="backend_pool/backend-blue"
            ha_green="backend_pool/backend-green"
        else
            ha_blue="oneapi_pool/oneapi-blue"
            ha_green="oneapi_pool/oneapi-green"
        fi

        blue_w=$(get_server_weight "$ha_blue" 2>/dev/null || echo "N/A")
        green_w=$(get_server_weight "$ha_green" 2>/dev/null || echo "N/A")
        blue_st=$(get_server_status "$ha_blue" 2>/dev/null || echo "N/A")
        green_st=$(get_server_status "$ha_green" 2>/dev/null || echo "N/A")
        echo -e "  ${BOLD}--- HAProxy 权重 ---${NC}"
        echo -e "  Blue:  weight=$blue_w, status=$blue_st"
        echo -e "  Green: weight=$green_w, status=$green_st"
    fi
    echo ""
}

# 显示全部状态
show_status() {
    load_env

    echo -e "${BOLD}${CYAN}=============================================${NC}"
    echo -e "${BOLD}${CYAN}  蓝绿部署状态${NC}"
    echo -e "${BOLD}${CYAN}=============================================${NC}"
    echo ""

    # HAProxy 总体状态
    local haproxy_status
    haproxy_status=$(docker inspect "$HAPROXY_CONTAINER" --format '{{.State.Status}}' 2>/dev/null || echo "stopped")
    local ha_symbol=""
    case "$haproxy_status" in
        running) ha_symbol="${GREEN}●${NC}" ;;
        *)       ha_symbol="${RED}●${NC}" ;;
    esac
    echo -e "  HAProxy:      ${ha_symbol} $haproxy_status"
    echo ""

    # 根据请求显示池
    if [ "$POOL" = "backend" ]; then
        show_pool_status "backend" "backend_pool" \
            "ai-api-agg-backend-blue" "ai-api-agg-backend-green" \
            "${BACKEND_BLUE_PORT:-8082}" "${BACKEND_GREEN_PORT:-8083}"
    else
        # 默认显示单池（oneapi），或显示所有池
        show_pool_status "oneapi" "oneapi_pool" \
            "ai-api-agg-oneapi-blue" "ai-api-agg-oneapi-green" \
            "3001" "3002"

        # 如果后端容器存在，也显示后端池
        if docker inspect "ai-api-agg-backend-blue" --format '{{.State.Status}}' &>/dev/null; then
            show_pool_status "backend" "backend_pool" \
                "ai-api-agg-backend-blue" "ai-api-agg-backend-green" \
                "${BACKEND_BLUE_PORT:-8082}" "${BACKEND_GREEN_PORT:-8083}"
        fi
    fi

    echo -e "  ${BOLD}HAProxy 状态页:${NC} http://localhost:8081/stats"
    echo -e "  ${BOLD}HAProxy API 入口:${NC} http://localhost:8080"
}

# ==========================================
# 使用帮助
# ==========================================
usage() {
    cat << 'EOF'
用法: bluegreen-switch.sh <命令> [选项]

命令:
  status                          查看当前蓝绿状态

选项:
  --pool <oneapi|backend>         目标池（默认: oneapi）
  --target <blue|green>           目标实例
  --mode <instant|gradual>        切换模式（默认: instant）
  --weight <1-100>                灰度目标权重 %（仅 gradual 模式，默认: 100）

快捷命令:
  rollback                        紧急回滚到另一个实例
  rollback --pool backend         回滚后端池

示例:
  ./bluegreen-switch.sh status
  ./bluegreen-switch.sh status --pool backend

  # OneAPI 池切换（默认）
  ./bluegreen-switch.sh --target green --mode instant
  ./bluegreen-switch.sh --target blue --mode gradual --weight 30

  # 后端池切换
  ./bluegreen-switch.sh --pool backend --target green --mode instant
  ./bluegreen-switch.sh --pool backend --target blue --mode gradual --weight 30

  # 回滚
  ./bluegreen-switch.sh rollback
  ./bluegreen-switch.sh rollback --pool backend

环境变量（从 docker/.env 读取）:
  ONEAPI_ADMIN_TOKEN       OneAPI 管理员 Token
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

    # 检查是否为快捷命令
    case "${1:-}" in
        status)
            shift
            # 检查是否有额外的 --pool
            while [ $# -gt 0 ]; do
                case "$1" in
                    --pool)
                        POOL="$2"
                        shift 2
                        ;;
                    *)
                        shift
                        ;;
                esac
            done
            setup_pool_config
            show_status
            exit 0
            ;;
        rollback)
            shift
            while [ $# -gt 0 ]; do
                case "$1" in
                    --pool)
                        POOL="$2"
                        shift 2
                        ;;
                    *)
                        shift
                        ;;
                esac
            done
            setup_pool_config
            do_rollback
            exit $?
            ;;
        -h|--help)
            usage
            exit 0
            ;;
    esac

    # 解析命名参数
    while [ $# -gt 0 ]; do
        case "$1" in
            --pool)
                POOL="$2"
                shift 2
                ;;
            --target)
                TARGET="$2"
                shift 2
                ;;
            --mode)
                MODE="$2"
                shift 2
                ;;
            --weight)
                WEIGHT="$2"
                shift 2
                ;;
            *)
                log_error "未知参数: $1"
                usage
                exit 1
                ;;
        esac
    done

    # 初始化池配置
    setup_pool_config

    # 验证参数
    if [ -z "$TARGET" ]; then
        log_error "缺少 --target 参数 (blue 或 green)"
        usage
        exit 1
    fi

    if [ "$TARGET" != "blue" ] && [ "$TARGET" != "green" ]; then
        log_error "--target 必须为 blue 或 green"
        exit 1
    fi

    if [ "$MODE" != "instant" ] && [ "$MODE" != "gradual" ]; then
        log_error "--mode 必须为 instant 或 gradual"
        exit 1
    fi

    if ! [[ "$WEIGHT" =~ ^[0-9]+$ ]] || [ "$WEIGHT" -lt 1 ] || [ "$WEIGHT" -gt 100 ]; then
        log_error "--weight 必须为 1-100 之间的整数"
        exit 1
    fi

    # 验证池
    if [ "$POOL" != "oneapi" ] && [ "$POOL" != "backend" ]; then
        log_error "--pool 必须为 oneapi 或 backend"
        exit 1
    fi

    # 执行切换
    if [ "$MODE" = "instant" ]; then
        switch_instant "$TARGET"
    else
        switch_gradual "$TARGET" "$WEIGHT"
    fi
}

main "$@"
