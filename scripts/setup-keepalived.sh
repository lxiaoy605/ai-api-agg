#!/usr/bin/env bash
# ============================================================
# setup-keepalived.sh — Keepalived VIP 高可用一键部署脚本
# ============================================================
# 功能：
#   1. 安装 keepalived 软件包
#   2. 根据 KEEPALIVED_ROLE 配置 Master/Backup 角色
#   3. 部署健康检查脚本和通知脚本
#   4. 创建 systemd service 并启用
#
# 前置条件：
#   - 2 台 VPS 组成 VRRP 集群
#   - 两台机器在同一 VPC/子网内（共享虚拟 IP）
#   - 已安装 Docker 并运行 HAProxy 容器
#
# 环境变量（从 docker/.env 读取）：
#   KEEPALIVED_VIP       — 虚拟 IP 地址（如 10.0.0.100/24）
#   KEEPALIVED_ROLE      — 角色: MASTER | BACKUP
#   KEEPALIVED_INTERFACE — 网卡接口（默认 eth0）
#
# 用法：
#   # 在 Master 节点上:
#   KEEPALIVED_VIP=10.0.0.100/24 KEEPALIVED_ROLE=MASTER ./setup-keepalived.sh
#
#   # 在 Backup 节点上:
#   KEEPALIVED_VIP=10.0.0.100/24 KEEPALIVED_ROLE=BACKUP ./setup-keepalived.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/docker/.env"
LOG_DIR="$PROJECT_DIR/logs"
KEEPALIVED_CONF_DIR="$PROJECT_DIR/docker/keepalived"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

mkdir -p "$LOG_DIR"

# ---------- 加载环境变量 ----------
load_env() {
  if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE" 2>/dev/null || true
    set +a
  fi
}

# ---------- 参数验证 ----------
validate_params() {
  local missing=()

  if [ -z "${KEEPALIVED_VIP:-}" ]; then
    log_error "KEEPALIVED_VIP 未设置（示例: 10.0.0.100/24）"
    missing+=("KEEPALIVED_VIP")
  fi

  if [ -z "${KEEPALIVED_ROLE:-}" ]; then
    log_error "KEEPALIVED_ROLE 未设置（MASTER 或 BACKUP）"
    missing+=("KEEPALIVED_ROLE")
  elif [ "$KEEPALIVED_ROLE" != "MASTER" ] && [ "$KEEPALIVED_ROLE" != "BACKUP" ]; then
    log_error "KEEPALIVED_ROLE 必须是 MASTER 或 BACKUP"
    missing+=("KEEPALIVED_ROLE")
  fi

  if [ ${#missing[@]} -gt 0 ]; then
    echo ""
    echo "用法:"
    echo "  KEEPALIVED_VIP=10.0.0.100/24 KEEPALIVED_ROLE=MASTER $0"
    echo "  KEEPALIVED_VIP=10.0.0.100/24 KEEPALIVED_ROLE=BACKUP $0"
    exit 1
  fi
}

# ---------- 安装 keepalived ----------
install_keepalived() {
  log_info "安装 keepalived..."

  if command -v keepalived &>/dev/null; then
    log_ok "keepalived 已安装: $(keepalived --version 2>&1 | head -1)"
    return 0
  fi

  if command -v apt-get &>/dev/null; then
    apt-get update -qq && apt-get install -y -qq keepalived
  elif command -v yum &>/dev/null; then
    yum install -y keepalived
  else
    log_error "无法识别的包管理器，请手动安装 keepalived"
    exit 1
  fi

  log_ok "keepalived 安装完成"
}

# ---------- 计算优先级 ----------
get_priority() {
  if [ "$KEEPALIVED_ROLE" = "MASTER" ]; then
    echo "100"
  else
    echo "50"
  fi
}

# ---------- 获取网卡接口 ----------
get_interface() {
  if [ -n "${KEEPALIVED_INTERFACE:-}" ]; then
    echo "$KEEPALIVED_INTERFACE"
    return
  fi
  # 自动检测默认网卡
  local iface
  iface=$(ip route show default 2>/dev/null | awk '{print $5}' | head -1)
  if [ -z "$iface" ]; then
    iface="eth0"
    log_warn "无法自动检测网卡，默认使用 eth0"
  fi
  echo "$iface"
}

# ---------- 部署配置 ----------
deploy_config() {
  local priority interface role vip
  priority=$(get_priority)
  interface=$(get_interface)
  role="$KEEPALIVED_ROLE"
  vip="$KEEPALIVED_VIP"

  log_info "部署 keepalived 配置..."
  log_info "  角色: $role"
  log_info "  优先级: $priority"
  log_info "  网卡: $interface"
  log_info "  虚拟 IP: $vip"

  # 从模板生成配置
  local template="$KEEPALIVED_CONF_DIR/keepalived.conf"
  local target="/etc/keepalived/keepalived.conf"

  if [ ! -f "$template" ]; then
    log_error "模板文件不存在: $template"
    exit 1
  fi

  # 替换占位符
  sed -e "s|\${KEEPALIVED_ROLE}|$role|g" \
      -e "s|\${KEEPALIVED_PRIORITY}|$priority|g" \
      -e "s|\${KEEPALIVED_INTERFACE}|$interface|g" \
      -e "s|\${KEEPALIVED_VIP}|$vip|g" \
      "$template" > "$target"

  log_ok "配置文件已写入 $target"
}

# ---------- 部署辅助脚本 ----------
deploy_scripts() {
  log_info "部署辅助脚本..."

  # HAProxy 健康检查脚本
  cat > /usr/local/bin/check-haproxy.sh << 'CHECKSCRIPT'
#!/bin/bash
# 检查 HAProxy 是否存活（通过 stats socket）
if docker exec ai-api-agg-haproxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg &>/dev/null; then
  # 额外检查 HAProxy 进程是否在运行
  if pgrep -x haproxy > /dev/null; then
    exit 0
  fi
fi
exit 1
CHECKSCRIPT
  chmod +x /usr/local/bin/check-haproxy.sh
  log_ok "健康检查脚本: /usr/local/bin/check-haproxy.sh"

  # 状态转换通知脚本（调用 ops-notify.sh）
  cat > /usr/local/bin/keepalived-notify.sh << 'NOTIFYSCRIPT'
#!/bin/bash
# Keepalived 状态转换通知
STATE="$1"
TIMESTAMP=$(date -Iseconds)
NOTIFY_SCRIPT="/mnt/d/WSL/openclawWorkspace/workspace/projects/ai-api-agg/scripts/ops-notify.sh"

case "$STATE" in
  master)
    echo "[$TIMESTAMP] Keepalived 提升为 MASTER，VIP 已绑定" >> /var/log/keepalived-notify.log
    if [ -x "$NOTIFY_SCRIPT" ]; then
      "$NOTIFY_SCRIPT" --level warning --title "Keepalived 故障转移" \
        --message "本节点提升为 MASTER，VIP 已接管。请检查原 Master 节点状态。" || true
    fi
    ;;
  backup)
    echo "[$TIMESTAMP] Keepalived 降级为 BACKUP，VIP 已释放" >> /var/log/keepalived-notify.log
    if [ -x "$NOTIFY_SCRIPT" ]; then
      "$NOTIFY_SCRIPT" --level critical --title "Keepalived VIP 漂移" \
        --message "本节点降级为 BACKUP，VIP 已释放。当前节点不再承载流量。" || true
    fi
    ;;
  fault)
    echo "[$TIMESTAMP] Keepalived 进入 FAULT 状态！" >> /var/log/keepalived-notify.log
    if [ -x "$NOTIFY_SCRIPT" ]; then
      "$NOTIFY_SCRIPT" --level critical --title "Keepalived FAULT" \
        --message "Keepalived 进入 FAULT 状态！HAProxy 或网络异常，请立即检查。" || true
    fi
    ;;
  stop)
    echo "[$TIMESTAMP] Keepalived 进程停止" >> /var/log/keepalived-notify.log
    ;;
  *)
    echo "[$TIMESTAMP] 未知状态: $STATE" >> /var/log/keepalived-notify.log
    ;;
esac
NOTIFYSCRIPT
  chmod +x /usr/local/bin/keepalived-notify.sh
  log_ok "通知脚本: /usr/local/bin/keepalived-notify.sh"
}

# ---------- 配置 systemd ----------
setup_systemd() {
  log_info "配置 systemd service..."

  # Keepalived service 已由包管理器创建，只需确保启用
  systemctl daemon-reload
  systemctl enable keepalived

  log_ok "keepalived.service 已启用"
}

# ---------- 备份旧配置 ----------
backup_old_config() {
  if [ -f /etc/keepalived/keepalived.conf ]; then
    local backup="/etc/keepalived/keepalived.conf.bak.$(date +%Y%m%d_%H%M%S)"
    cp /etc/keepalived/keepalived.conf "$backup"
    log_info "旧配置已备份到 $backup"
  fi
}

# ---------- 启动服务 ----------
start_service() {
  log_info "启动 keepalived..."
  systemctl restart keepalived
  sleep 3

  if systemctl is-active --quiet keepalived; then
    log_ok "keepalived 运行中"
  else
    log_error "keepalived 启动失败，查看日志: journalctl -u keepalived -n 50"
    return 1
  fi
}

# ---------- 显示状态 ----------
show_status() {
  echo ""
  echo "╔══════════════════════════════════════════════════╗"
  echo "║   Keepalived VIP 高可用部署完成                    ║"
  echo "╠══════════════════════════════════════════════════╣"
  echo "║   角色:     $(printf '%-38s' "$KEEPALIVED_ROLE")║"
  echo "║   虚拟 IP:  $(printf '%-38s' "$KEEPALIVED_VIP")║"
  echo "║   网卡:     $(printf '%-38s' "$(get_interface)")║"
  echo "╠══════════════════════════════════════════════════╣"
  echo "║   管理命令:                                       ║"
  echo "║     systemctl status keepalived                  ║"
  echo "║     journalctl -u keepalived -f                  ║"
  echo "║     ip addr show | grep $(echo $KEEPALIVED_VIP | cut -d/ -f1)║"
  echo "╚══════════════════════════════════════════════════╝"
  echo ""

  log_info "在另一台 VPS 上使用相同 VIP、BACKUP 角色运行此脚本完成配对"
}

# ---------- 主流程 ----------
main() {
  echo ""
  echo "╔══════════════════════════════════════════════════╗"
  echo "║    AI API 聚合平台 — Keepalived VIP 部署脚本       ║"
  echo "╚══════════════════════════════════════════════════╝"
  echo ""

  # 检查 root 权限
  if [ "$(id -u)" -ne 0 ]; then
    log_error "此脚本需要 root 权限运行 (keepalived 安装和 systemd 配置)"
    echo "请使用: sudo $0"
    exit 1
  fi

  load_env
  validate_params
  install_keepalived
  backup_old_config
  deploy_config
  deploy_scripts
  setup_systemd
  start_service
  show_status
}

main "$@"
