#!/bin/bash
# ============================================================
# ai-api-agg 灾难恢复 — 跨区域故障切换脚本
# ============================================================
# 功能：
#   从远程备份拉取最新备份 → 恢复数据库 → 启动服务 → 验证健康
#
# 用法：
#   bash dr-failover.sh --status                  # 查看远程备份列表
#   bash dr-failover.sh                           # 交互模式：选择备份并恢复
#   bash dr-failover.sh --auto                    # 自动拉取最新备份并恢复
#   bash dr-failover.sh --target-host 1.2.3.4 --auto  # 指定目标主机自动恢复
#
# 环境变量：
#   REMOTE_BACKUP_HOST           远程备份主机
#   REMOTE_BACKUP_PATH           远程备份路径
#   ONEAPI_URL                   本地 OneAPI 地址（默认 http://localhost:3000）
#   TELEGRAM_BOT_TOKEN           Telegram Bot Token
#   TELEGRAM_CHAT_ID             Telegram Chat ID
# ============================================================

set -euo pipefail

# ---------- 路径配置 ----------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$PROJECT_DIR/backups"
LOG_FILE="$BACKUP_DIR/failover.log"
DB_FILE="$PROJECT_DIR/backend/data/app.db"
CONFIG_DIR="$PROJECT_DIR/config"
DOCKER_DIR="$PROJECT_DIR/docker"
MANIFEST_FILE="$BACKUP_DIR/manifest.json"

# 本地临时存储远程备份
RESTORE_TMP="$BACKUP_DIR/remote-restore"

# ---------- 默认值 ----------
ONEAPI_URL="${ONEAPI_URL:-http://localhost:3000}"
HEALTH_CHECK_RETRIES=10
HEALTH_CHECK_INTERVAL=3
AUTO_MODE=false
TARGET_HOST=""
ACTION="restore"

mkdir -p "$BACKUP_DIR"
mkdir -p "$RESTORE_TMP"

# ---------- 日志函数 ----------
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# ---------- 颜色 ----------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# ---------- Telegram 通知 ----------
NOTIFY_SCRIPT="${SCRIPT_DIR:-$(dirname "$0")}/ops-notify.sh"

tg_notify() {
    local message="$1"

    # 根据消息内容推断级别
    local level="warning"
    if echo "$message" | grep -qi "fail\|failed\|failure\|error\|disaster\|crash"; then
        level="critical"
    elif echo "$message" | grep -qi "success\|successfully\|done\|complete"; then
        level="info"
    fi

    if [ -x "$NOTIFY_SCRIPT" ]; then
        "$NOTIFY_SCRIPT" --level "$level" --title "灾难恢复通知" --message "$message" --silent || true
    fi
}

# ---------- 远程连接检查 ----------
check_remote_reachable() {
    local host="$1"

    if [[ "$host" == *"@"* ]]; then
        # user@host 格式
        local ssh_host="$host"
        if ssh -o ConnectTimeout=5 -o BatchMode=yes "$ssh_host" "echo ok" >/dev/null 2>&1; then
            return 0
        else
            return 1
        fi
    else
        # 纯 IP/域名
        if ping -c 1 -W 3 "$host" >/dev/null 2>&1; then
            return 0
        else
            return 1
        fi
    fi
}

# ---------- 列出远程备份 ----------
list_remote_backups() {
    local host="${REMOTE_BACKUP_HOST:-}"
    local path="${REMOTE_BACKUP_PATH:-}"

    if [ -z "$host" ] || [ -z "$path" ]; then
        echo -e "${RED}错误: 未设置 REMOTE_BACKUP_HOST 或 REMOTE_BACKUP_PATH 环境变量${NC}"
        echo ""
        echo "请设置:"
        echo "  export REMOTE_BACKUP_HOST=user@backup.example.com"
        echo "  export REMOTE_BACKUP_PATH=/data/backups/ai-api-agg"
        return 1
    fi

    echo ""
    echo "============================================"
    echo "  远程备份列表 — ${host}:${path}"
    echo "============================================"
    echo ""

    # 尝试获取 manifest.json
    local manifest
    if manifest=$(ssh -o ConnectTimeout=10 -o BatchMode=yes "$host" "cat ${path}/manifest.json 2>/dev/null" 2>/dev/null); then
        echo "$manifest" | jq -r '
          .backups | sort_by(.timestamp) | reverse |
          to_entries[] |
          "  [\(.key + 1)] \(.value.filename)  \(.value.type)  \((.value.size_bytes | tonumber / 1024 | floor) + "KB")  \((.value.timestamp | tonumber | strftime("%Y-%m-%d %H:%M:%S")) // "未知")"
        ' 2>/dev/null || {
            # jq 失败时走原始列表
            ssh -o ConnectTimeout=10 "$host" "ls -lh ${path}/full/ 2>/dev/null; ls -lh ${path}/incremental/ 2>/dev/null" 2>/dev/null || \
            echo -e "${YELLOW}无法获取远程备份列表（SSH 连接失败或路径不存在）${NC}"
        }
    else
        # 无法读取 manifest，走原始文件列表
        log "无法读取远程 manifest.json，回退到文件列表"
        ssh -o ConnectTimeout=10 "$host" "ls -lh ${path}/full/ 2>/dev/null; echo '---'; ls -lh ${path}/incremental/ 2>/dev/null" 2>/dev/null || \
            echo -e "${YELLOW}无法连接远程主机${NC}"
    fi

    echo ""

    # 检查远程 SHA256 文件数目
    local sha_count
    sha_count=$(ssh -o ConnectTimeout=10 "$host" "find ${path}/ -name '*.sha256' | wc -l" 2>/dev/null || echo "0")
    echo "远程备份校验文件: ${sha_count} 个 .sha256"
    echo ""
}

# ---------- 从远程拉取备份 ----------
fetch_remote_backup() {
    local host="${REMOTE_BACKUP_HOST:-}"
    local path="${REMOTE_BACKUP_PATH:-}"
    local specific_file="${1:-}"

    if [ -z "$host" ] || [ -z "$path" ]; then
        log "ERROR: 未设置 REMOTE_BACKUP_HOST 或 REMOTE_BACKUP_PATH"
        return 1
    fi

    log "连接到远程备份服务器: $host"
    if ! check_remote_reachable "$host"; then
        log "ERROR: 无法连接远程备份服务器"
        return 1
    fi

    local remote_file

    if [ -n "$specific_file" ]; then
        remote_file="$specific_file"
    else
        # 自动获取最新全量备份
        log "自动获取最新全量备份..."
        remote_file=$(ssh -o ConnectTimeout=10 "$host" \
            "ls -t ${path}/full/backup-full-*.tar.gz 2>/dev/null | head -1" 2>/dev/null || echo "")

        if [ -z "$remote_file" ]; then
            log "无全量备份可用，尝试获取最新增量备份..."
            remote_file=$(ssh -o ConnectTimeout=10 "$host" \
                "ls -t ${path}/incremental/backup-incr-*.tar.gz 2>/dev/null | head -1" 2>/dev/null || echo "")
        fi

        if [ -z "$remote_file" ]; then
            # 兼容旧版
            remote_file=$(ssh -o ConnectTimeout=10 "$host" \
                "ls -t ${path}/backup-*.tar.gz 2>/dev/null | head -1" 2>/dev/null || echo "")
        fi
    fi

    if [ -z "$remote_file" ]; then
        log "ERROR: 远程服务器无可用备份"
        return 1
    fi

    local filename
    filename=$(basename "$remote_file")
    local local_path="$RESTORE_TMP/$filename"

    log "拉取远程备份: $filename"
    if scp -o ConnectTimeout=30 "$host:${path}/${filename}" "$local_path" 2>&1 | tee -a "$LOG_FILE"; then
        log "备份拉取成功: $local_path"

        # 同时拉取 .sha256 文件
        scp -o ConnectTimeout=10 "$host:${path}/${filename}.sha256" "${local_path}.sha256" 2>/dev/null || true

        # 如果是从子目录取到的完整路径，直接使用
        if [ ! -f "$local_path" ]; then
            # 尝试从 full/ 子目录
            scp -o ConnectTimeout=30 "$host:$remote_file" "$local_path" 2>&1 | tee -a "$LOG_FILE"
            scp -o ConnectTimeout=10 "$host:${remote_file}.sha256" "${local_path}.sha256" 2>/dev/null || true
        fi

        echo "$local_path"
        return 0
    else
        log "ERROR: 备份拉取失败"
        return 1
    fi
}

# ---------- 验证备份完整性 ----------
verify_backup() {
    local backup_file="$1"

    if [ ! -f "$backup_file" ]; then
        log "ERROR: 备份文件不存在: $backup_file"
        return 1
    fi

    # SHA256 验证
    local sha256_file="${backup_file}.sha256"
    if [ -f "$sha256_file" ]; then
        log "验证 SHA256 校验和..."
        local expected actual
        expected=$(awk '{print $1}' "$sha256_file")
        actual=$(sha256sum "$backup_file" | awk '{print $1}')
        if [ "$expected" = "$actual" ]; then
            log "SHA256 校验通过"
        else
            log "ERROR: SHA256 校验失败！"
            log "  期望: $expected"
            log "  实际: $actual"
            return 1
        fi
    else
        log "WARNING: 未找到 .sha256 文件，跳过完整性验证"
    fi

    # 检查 tar 完整性
    if tar tzf "$backup_file" >/dev/null 2>&1; then
        log "备份压缩包完整性检查通过"
    else
        log "ERROR: 备份压缩包损坏（tar 校验失败）"
        return 1
    fi

    return 0
}

# ---------- 恢复数据库和配置 ----------
restore_from_backup() {
    local backup_file="$1"

    log "========== 开始恢复 =========="
    log "备份文件: $backup_file"

    # 1. 解压到临时目录
    local tmp_dir
    tmp_dir=$(mktemp -d)
    tar xzf "$backup_file" -C "$tmp_dir"

    # 2. 安全备份当前状态
    local safety_dir="$BACKUP_DIR/pre-restore-safety"
    mkdir -p "$safety_dir"
    local safety_file="$safety_dir/pre-failover-$(date +%Y-%m-%d-%H%M%S).tar.gz"

    log "创建恢复前安全备份..."
    local safety_tmp
    safety_tmp=$(mktemp -d)
    if [ -f "$DB_FILE" ]; then
        mkdir -p "$safety_tmp/db"
        cp "$DB_FILE" "$safety_tmp/db/app.db"
        [ -f "$DB_FILE-wal" ] && cp "$DB_FILE-wal" "$safety_tmp/db/"
        [ -f "$DB_FILE-shm" ] && cp "$DB_FILE-shm" "$safety_tmp/db/"
    fi
    [ -f "$CONFIG_DIR/config.yaml" ] && { mkdir -p "$safety_tmp/config"; cp "$CONFIG_DIR/config.yaml" "$safety_tmp/config/"; }
    [ -f "$DOCKER_DIR/.env" ] && { mkdir -p "$safety_tmp/docker"; cp "$DOCKER_DIR/.env" "$safety_tmp/docker/"; }
    [ -f "$DOCKER_DIR/docker-compose.yml" ] && { mkdir -p "$safety_tmp/docker"; cp "$DOCKER_DIR/docker-compose.yml" "$safety_tmp/docker/"; }

    cd "$safety_tmp"
    tar czf "$safety_file" .
    cd "$PROJECT_DIR"
    rm -rf "$safety_tmp"
    log "安全备份已创建: $safety_file"

    # 3. 恢复数据库
    if [ -f "$tmp_dir/db/app.db" ]; then
        log "恢复数据库..."
        mkdir -p "$(dirname "$DB_FILE")"

        # 先执行 integrity check
        local integrity
        integrity=$(sqlite3 "$tmp_dir/db/app.db" "PRAGMA integrity_check;" 2>&1) || true
        if [ "$integrity" != "ok" ]; then
            log "ERROR: 备份数据库完整性检查失败: $integrity"
            log "恢复中止，当前数据未受影响"
            rm -rf "$tmp_dir"
            return 1
        fi

        cp "$tmp_dir/db/app.db" "$DB_FILE"
        [ -f "$tmp_dir/db/app.db-wal" ] && cp "$tmp_dir/db/app.db-wal" "$DB_FILE-wal"
        [ -f "$tmp_dir/db/app.db-shm" ] && cp "$tmp_dir/db/app.db-shm" "$DB_FILE-shm"
        log "数据库恢复完成 -> $DB_FILE"
        echo -e "  ${GREEN}✓${NC} 数据库已恢复"
    else
        log "备份中无数据库文件，跳过"
        echo -e "  ${YELLOW}○${NC} 备份中无数据库文件"
    fi

    # 4. 恢复配置
    if [ -f "$tmp_dir/config/config.yaml" ]; then
        mkdir -p "$CONFIG_DIR"
        cp "$tmp_dir/config/config.yaml" "$CONFIG_DIR/config.yaml"
        log "config.yaml 恢复完成"
        echo -e "  ${GREEN}✓${NC} config.yaml 已恢复"
    fi

    if [ -f "$tmp_dir/docker/.env" ]; then
        mkdir -p "$DOCKER_DIR"
        cp "$tmp_dir/docker/.env" "$DOCKER_DIR/.env"
        log "docker/.env 恢复完成"
        echo -e "  ${GREEN}✓${NC} docker/.env 已恢复"
    fi

    if [ -f "$tmp_dir/docker/docker-compose.yml" ]; then
        cp "$tmp_dir/docker/docker-compose.yml" "$DOCKER_DIR/docker-compose.yml"
    fi

    rm -rf "$tmp_dir"
    log "========== 恢复完成 =========="
    return 0
}

# ---------- 启动服务 ----------
start_services() {
    log "========== 启动服务 =========="

    if [ -f "$DOCKER_DIR/docker-compose.yml" ]; then
        cd "$DOCKER_DIR"
        if docker compose up -d 2>&1 | tee -a "$LOG_FILE"; then
            log "服务启动成功"
            cd "$PROJECT_DIR"
            return 0
        else
            log "ERROR: Docker Compose 启动失败"
            cd "$PROJECT_DIR"
            return 1
        fi
    else
        log "WARNING: docker-compose.yml 不存在，尝试直接启动后端服务"
        # 回退到直接启动
        cd "$PROJECT_DIR/backend"
        nohup go run ./cmd/server > /tmp/ai-api-agg.log 2>&1 &
        cd "$PROJECT_DIR"
        log "后端服务已在后台启动"
        return 0
    fi
}

# ---------- 健康验证 ----------
health_check() {
    log "========== 健康验证 =========="

    local retries=$HEALTH_CHECK_RETRIES
    local count=0

    while [ $count -lt $retries ]; do
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$ONEAPI_URL/api/status" 2>/dev/null || echo "000")

        if [ "$http_code" = "200" ]; then
            log "健康检查通过 (HTTP $http_code, 尝试 $((count + 1)))"
            echo -e "  ${GREEN}✓${NC} 服务健康检查通过"
            return 0
        fi

        count=$((count + 1))
        log "健康检查等待中... (HTTP $http_code, 尝试 $count/$retries)"
        sleep "$HEALTH_CHECK_INTERVAL"
    done

    log "ERROR: 健康检查失败（$retries 次尝试后仍未通过）"
    echo -e "  ${RED}✗${NC} 健康检查失败"
    return 1
}

# ---------- 交互式恢复 ----------
interactive_restore() {
    list_remote_backups || true

    echo ""
    echo "============================================"
    echo "  灾难恢复 — 交互模式"
    echo "============================================"
    echo ""
    echo "  1) 从远程拉取最新备份并恢复"
    echo "  2) 从本地备份恢复"
    echo "  3) 退出"
    echo ""

    read -r -p "  请选择 (1-3): " choice

    local backup_file=""

    case "$choice" in
        1)
            echo -e "\n${CYAN}正在从远程拉取最新备份...${NC}"
            backup_file=$(fetch_remote_backup "" || echo "")
            if [ -z "$backup_file" ] || [ ! -f "$backup_file" ]; then
                echo -e "${RED}拉取远程备份失败${NC}"
                return 1
            fi
            ;;
        2)
            echo ""
            echo "本地备份列表:"
            local count=0
            local backups=()
            for f in "$BACKUP_DIR"/full/backup-full-*.tar.gz "$BACKUP_DIR"/incremental/backup-incr-*.tar.gz "$BACKUP_DIR"/backup-*.tar.gz; do
                [ -f "$f" ] || continue
                [ -L "$f" ] && continue
                count=$((count + 1))
                backups+=("$f")
                printf "  ${GREEN}[%d]${NC} %s (%s)\n" "$count" "$(basename "$f")" "$(du -h "$f" | cut -f1)"
            done

            if [ "$count" -eq 0 ]; then
                echo -e "${YELLOW}无可用本地备份${NC}"
                return 1
            fi

            read -r -p "  请选择 (1-$count): " idx
            if [ "$idx" -ge 1 ] 2>/dev/null && [ "$idx" -le "$count" ] 2>/dev/null; then
                backup_file="${backups[$((idx - 1))]}"
            else
                echo -e "${RED}无效选择${NC}"
                return 1
            fi
            ;;
        3)
            echo "已退出"
            return 0
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            return 1
            ;;
    esac

    # 验证备份
    echo ""
    echo "验证备份完整性..."
    if ! verify_backup "$backup_file"; then
        echo -e "${RED}备份验证失败，恢复中止${NC}"
        return 1
    fi

    # 确认操作
    echo ""
    echo -e "${RED}⚠ 警告: 此操作将覆盖当前数据库和配置文件！${NC}"
    read -r -p "  确认恢复？(输入 yes 继续): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "已取消"
        return 0
    fi

    # 执行恢复
    if ! restore_from_backup "$backup_file"; then
        echo -e "${RED}恢复失败${NC}"
        tg_notify "❌ *灾难恢复失败*\n主机: $(hostname)\n时间: $(date)"
        return 1
    fi

    # 启动服务
    if ! start_services; then
        echo -e "${RED}服务启动失败${NC}"
        tg_notify "❌ *灾难恢复 — 服务启动失败*\n主机: $(hostname)\n时间: $(date)"
        return 1
    fi

    # 健康验证
    if ! health_check; then
        echo -e "${RED}健康验证失败${NC}"
        tg_notify "⚠️ *灾难恢复 — 服务已启动但健康检查未通过*\n主机: $(hostname)\n时间: $(date)"
        return 1
    fi

    echo ""
    echo "============================================"
    echo -e "  ${GREEN}灾难恢复成功！${NC}"
    echo "============================================"
    echo ""
    echo "  数据库: $DB_FILE"
    echo "  服务: $ONEAPI_URL"
    echo ""

    tg_notify "✅ *灾难恢复成功*\n主机: $(hostname)\n服务: $ONEAPI_URL\n时间: $(date)"

    return 0
}

# ---------- 自动恢复 ----------
auto_restore() {
    log "========== 自动灾难恢复模式 =========="
    log "目标主机: ${TARGET_HOST:-localhost}"

    tg_notify "🔄 *灾难恢复启动*\n主机: $(hostname)\n目标: ${TARGET_HOST:-localhost}\n时间: $(date)"

    # 1. 拉取最新远程备份
    echo -e "${CYAN}[1/4] 拉取远程备份...${NC}"
    local backup_file
    backup_file=$(fetch_remote_backup "" || echo "")
    if [ -z "$backup_file" ] || [ ! -f "$backup_file" ]; then
        log "FATAL: 无法获取远程备份"
        tg_notify "🚨 *灾难恢复失败 — 无法获取远程备份*\n主机: $(hostname)"
        return 1
    fi

    # 2. 验证备份
    echo -e "${CYAN}[2/4] 验证备份完整性...${NC}"
    if ! verify_backup "$backup_file"; then
        log "FATAL: 备份验证失败"
        tg_notify "🚨 *灾难恢复失败 — 备份验证失败*\n主机: $(hostname)"
        return 1
    fi

    # 3. 恢复
    echo -e "${CYAN}[3/4] 恢复数据...${NC}"
    if ! restore_from_backup "$backup_file"; then
        log "FATAL: 数据恢复失败"
        tg_notify "🚨 *灾难恢复失败 — 数据恢复失败*\n主机: $(hostname)"
        return 1
    fi

    # 4. 启动服务
    echo -e "${CYAN}[4/4] 启动服务并验证健康...${NC}"
    if ! start_services; then
        log "FATAL: 服务启动失败"
        tg_notify "🚨 *灾难恢复失败 — 服务启动失败*\n主机: $(hostname)"
        return 1
    fi

    if ! health_check; then
        log "FATAL: 健康检查失败"
        tg_notify "⚠️ *灾难恢复 — 服务已启动但健康检查未通过*\n主机: $(hostname)\nOneAPI: $ONEAPI_URL"
        return 1
    fi

    log "========== 自动灾难恢复成功 =========="
    tg_notify "✅ *灾难恢复成功*\n主机: $(hostname)\n服务: $ONEAPI_URL\n时间: $(date)"

    echo ""
    echo -e "${GREEN}灾难恢复成功！${NC}"
    return 0
}

# ============================================================
# 主入口
# ============================================================

# 解析参数
while [ $# -gt 0 ]; do
    case "$1" in
        --status)
            ACTION="status"
            ;;
        --auto)
            AUTO_MODE=true
            ;;
        --target-host)
            TARGET_HOST="$2"
            shift
            ;;
        --help|-h)
            echo "用法: $0 [选项]"
            echo ""
            echo "选项:"
            echo "  --status               查看远程备份列表"
            echo "  --auto                 自动模式（无需交互确认）"
            echo "  --target-host <IP>     指定目标主机"
            echo "  --help                 显示帮助"
            echo ""
            echo "环境变量:"
            echo "  REMOTE_BACKUP_HOST     远程备份主机"
            echo "  REMOTE_BACKUP_PATH     远程备份路径"
            echo "  TELEGRAM_BOT_TOKEN     Telegram Bot Token"
            echo "  TELEGRAM_CHAT_ID       Telegram Chat ID"
            exit 0
            ;;
        *)
            echo "未知参数: $1"
            exit 1
            ;;
    esac
    shift
done

# 确认必要环境变量
if [ -z "${REMOTE_BACKUP_HOST:-}" ] || [ -z "${REMOTE_BACKUP_PATH:-}" ]; then
    echo -e "${YELLOW}警告: 未设置 REMOTE_BACKUP_HOST 和 REMOTE_BACKUP_PATH${NC}"
    echo "远程备份功能将不可用，仅可使用本地备份恢复"
    echo ""
fi

case "$ACTION" in
    status)
        list_remote_backups
        ;;
    restore)
        if [ "$AUTO_MODE" = true ]; then
            auto_restore
        else
            interactive_restore
        fi
        ;;
esac
