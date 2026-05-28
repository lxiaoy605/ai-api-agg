#!/bin/bash
# ============================================================
# ai-api-agg 备份恢复脚本
# 功能：列出备份、从指定备份恢复数据库和配置
# 用法：bash restore.sh [备份文件名]
#       bash restore.sh                    # 交互模式：列出备份并选择
#       bash restore.sh backup-2026-01-01-120000.tar.gz  # 直接恢复
# ============================================================

set -e

# ---------- 路径配置 ----------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$PROJECT_DIR/backups"
LOG_FILE="$BACKUP_DIR/backup.log"
DB_FILE="$PROJECT_DIR/backend/data/app.db"
CONFIG_DIR="$PROJECT_DIR/config"
DOCKER_DIR="$PROJECT_DIR/docker"
NOTIFY_SCRIPT="$SCRIPT_DIR/ops-notify.sh"

# ---------- 通知函数 ----------
notify_restore() {
  local level="$1" title="$2" message="$3"
  if [ -x "$NOTIFY_SCRIPT" ]; then
    "$NOTIFY_SCRIPT" --level "$level" --title "$title" --message "$message" --silent || true
  fi
}

# ---------- 日志函数 ----------
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# ---------- 颜色输出 ----------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# ---------- 列出可用备份 ----------
list_backups() {
    echo ""
    echo "============================================"
    echo "  可用备份列表"
    echo "============================================"
    echo ""

    local count=0
    local backups=()

    for f in "$BACKUP_DIR"/backup-*.tar.gz; do
        [ -f "$f" ] || continue
        # 跳过符号链接
        [ -L "$f" ] && continue
        count=$((count + 1))
        backups+=("$f")
        local name=$(basename "$f")
        local size=$(du -h "$f" | cut -f1)

        printf "  ${GREEN}[%d]${NC} %s  (${YELLOW}%s${NC})\n" "$count" "$name" "$size"
    done

    if [ "$count" -eq 0 ]; then
        echo "  (无可用备份)"
        echo ""
        exit 0
    fi

    echo ""
    return 0
}

# ---------- 安全备份当前状态 ----------
safe_backup_current() {
    local safety_dir="$BACKUP_DIR/pre-restore-safety"
    mkdir -p "$safety_dir"
    local safety_file="$safety_dir/pre-restore-$(date +%Y-%m-%d-%H%M%S).tar.gz"
    local tmp_dir=$(mktemp -d)

    log "创建恢复前安全备份..."

    if [ -f "$DB_FILE" ]; then
        mkdir -p "$tmp_dir/db"
        cp "$DB_FILE" "$tmp_dir/db/app.db"
        [ -f "$DB_FILE-wal" ] && cp "$DB_FILE-wal" "$tmp_dir/db/"
        [ -f "$DB_FILE-shm" ] && cp "$DB_FILE-shm" "$tmp_dir/db/"
    fi

    mkdir -p "$tmp_dir/config"
    [ -f "$CONFIG_DIR/config.yaml" ] && cp "$CONFIG_DIR/config.yaml" "$tmp_dir/config/"
    [ -f "$CONFIG_DIR/config.example.yaml" ] && cp "$CONFIG_DIR/config.example.yaml" "$tmp_dir/config/"

    mkdir -p "$tmp_dir/docker"
    [ -f "$DOCKER_DIR/.env" ] && cp "$DOCKER_DIR/.env" "$tmp_dir/docker/"
    [ -f "$DOCKER_DIR/docker-compose.yml" ] && cp "$DOCKER_DIR/docker-compose.yml" "$tmp_dir/docker/"

    cd "$tmp_dir"
    tar czf "$safety_file" .
    cd "$PROJECT_DIR"
    rm -rf "$tmp_dir"

    log "安全备份已创建: $safety_file"
    echo -e "  ${GREEN}✓${NC} 当前状态已备份到: $safety_file"
}

# ---------- 执行恢复 ----------
do_restore() {
    local backup_path="$1"

    if [ ! -f "$backup_path" ]; then
        echo -e "${RED}错误: 备份文件不存在: $backup_path${NC}"
        exit 1
    fi

    echo ""
    echo "============================================"
    echo "  恢复备份"
    echo "============================================"
    echo ""
    echo "  备份文件: $(basename "$backup_path")"
    echo "  大小: $(du -h "$backup_path" | cut -f1)"
    echo ""

    # 确认操作
    echo -e "  ${RED}⚠ 警告: 此操作将覆盖当前数据库和配置文件！${NC}"
    echo ""
    read -r -p "  确认恢复？(输入 yes 继续): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "  已取消操作"
        exit 0
    fi

    log "========== 开始恢复 =========="
    log "备份文件: $backup_path"

    # 1. 安全备份当前状态
    safe_backup_current

    # 2. 解压备份到临时目录
    local tmp_dir=$(mktemp -d)
    tar xzf "$backup_path" -C "$tmp_dir"

    # 3. 恢复数据库
    if [ -f "$tmp_dir/db/app.db" ]; then
        mkdir -p "$(dirname "$DB_FILE")"
        cp "$tmp_dir/db/app.db" "$DB_FILE"
        [ -f "$tmp_dir/db/app.db-wal" ] && cp "$tmp_dir/db/app.db-wal" "$DB_FILE-wal"
        [ -f "$tmp_dir/db/app.db-shm" ] && cp "$tmp_dir/db/app.db-shm" "$DB_FILE-shm"
        log "数据库恢复完成 -> $DB_FILE"
        echo -e "  ${GREEN}✓${NC} 数据库已恢复"
    else
        log "备份中无数据库文件，跳过"
        echo -e "  ${YELLOW}○${NC} 备份中无数据库文件"
    fi

    # 4. 恢复配置文件
    if [ -f "$tmp_dir/config/config.yaml" ]; then
        mkdir -p "$CONFIG_DIR"
        cp "$tmp_dir/config/config.yaml" "$CONFIG_DIR/config.yaml"
        log "config.yaml 恢复完成"
        echo -e "  ${GREEN}✓${NC} config.yaml 已恢复"
    fi
    if [ -f "$tmp_dir/config/config.example.yaml" ]; then
        cp "$tmp_dir/config/config.example.yaml" "$CONFIG_DIR/config.example.yaml"
    fi

    # 5. 恢复 docker 配置
    if [ -f "$tmp_dir/docker/.env" ]; then
        mkdir -p "$DOCKER_DIR"
        cp "$tmp_dir/docker/.env" "$DOCKER_DIR/.env"
        log "docker/.env 恢复完成"
        echo -e "  ${GREEN}✓${NC} docker/.env 已恢复"
    fi
    if [ -f "$tmp_dir/docker/docker-compose.yml" ]; then
        cp "$tmp_dir/docker/docker-compose.yml" "$DOCKER_DIR/docker-compose.yml"
    fi

    # 6. 清理临时目录
    rm -rf "$tmp_dir"

    log "========== 恢复完成 =========="
    notify_restore "warning" "备份恢复操作" "从备份 $(basename "$backup_path") 恢复成功。请重启服务使恢复生效。"

    echo ""
    echo "============================================"
    echo "  恢复成功！"
    echo "============================================"
    echo ""
    echo "  如果之前运行过服务，请重启："
    echo "    cd backend && go run ./cmd/server"
    echo ""
}

# ---------- 主入口 ----------
echo ""
echo "============================================"
echo "  ai-api-agg 备份恢复工具"
echo "============================================"

# 确保备份目录存在
mkdir -p "$BACKUP_DIR"

# 如果指定了备份文件名参数
if [ -n "$1" ]; then
    BACKUP_PATH=""
    if [ -f "$1" ]; then
        # 绝对路径或相对路径
        BACKUP_PATH="$(realpath "$1")"
    elif [ -f "$BACKUP_DIR/$1" ]; then
        BACKUP_PATH="$BACKUP_DIR/$1"
    else
        echo -e "${RED}错误: 找不到备份文件 '$1'${NC}"
        list_backups
        exit 1
    fi
    do_restore "$BACKUP_PATH"
    exit 0
fi

# 交互模式：列出备份让用户选择
list_backups

# 获取备份列表并让用户选择
backups=()
for f in "$BACKUP_DIR"/backup-*.tar.gz; do
    [ -f "$f" ] && [ ! -L "$f" ] && backups+=("$f")
done

if [ ${#backups[@]} -eq 0 ]; then
    exit 0
fi

read -r -p "  请输入序号 (1-${#backups[@]}) 或按 Enter 取消: " choice

if [ -z "$choice" ]; then
    echo "  已取消"
    exit 0
fi

if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#backups[@]} ]; then
    echo -e "${RED}  无效选择${NC}"
    exit 1
fi

selected="${backups[$((choice - 1))]}"
do_restore "$selected"
