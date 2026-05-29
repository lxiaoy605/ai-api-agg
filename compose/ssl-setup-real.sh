#!/bin/bash
# =============================================
# aiflowhub.ai 真实 SSL 证书签发脚本
# =============================================
#
# 这是 ssl-setup.sh 的封装，针对 aiflowhub.ai 预配置。
# 使用 Let's Encrypt + Certbot webroot 模式。
#
# 用法：
#   chmod +x ssl-setup-real.sh
#   sudo ./ssl-setup-real.sh              # 首次签发（生产）
#   sudo ./ssl-setup-real.sh --staging     # 测试模式（避免频率限制）
#   sudo ./ssl-setup-real.sh --renew       # 手动续期
#   sudo ./ssl-setup-real.sh --status      # 查看证书状态
#
# 前置条件：
#   1. 域名 DNS 已指向服务器 IP（参考 SPACESHIP-DNS.md）
#   2. Docker Compose 已启动（nginx 容器运行中）
#   3. 防火墙放行 80/443 端口
# =============================================

set -euo pipefail

# ── 固定配置（aiflowhub.ai）─────────────────────
DOMAIN_NAME="aiflowhub.ai"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

# ── 颜色输出 ──────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()  { echo -e "${CYAN}[STEP]${NC} $*"; }

# ── 帮助 ──────────────────────────────────────
usage() {
    cat <<EOF
用法: sudo $0 [选项]

aiflowhub.ai SSL 证书管理（Let's Encrypt）

选项:
  (无参数)         首次签发证书 + 配置自动续期
  --staging         使用 Let's Encrypt staging 环境测试（避免频率限制）
  --renew           检查并续期证书
  --status          查看当前证书状态
  --setup-cron      仅配置自动续期 cron

前置条件:
  1. 域名 aiflowhub.ai DNS 已指向本机 IP
  2. docker compose up -d 已启动（nginx 容器运行中）
  3. 防火墙放行 80/443 端口

邮箱配置:
  从 .env 文件读取 SSL_EMAIL，或通过环境变量传入：
  sudo SSL_EMAIL=your@email.com $0
EOF
    exit 0
}

# ── 加载邮箱 ──────────────────────────────────
load_email() {
    if [ -n "${SSL_EMAIL:-}" ]; then
        return 0
    fi

    if [ -f "$ENV_FILE" ]; then
        # shellcheck source=/dev/null
        SSL_EMAIL=$(grep -E '^SSL_EMAIL=' "$ENV_FILE" | head -1 | cut -d= -f2-)
        SSL_EMAIL="${SSL_EMAIL:-}"
    fi

    if [ -z "$SSL_EMAIL" ] || [ "$SSL_EMAIL" = "your-email@example.com" ]; then
        echo ""
        log_warn "SSL_EMAIL 未配置（Let's Encrypt 证书到期通知用）"
        echo ""
        read -r -p "请输入你的邮箱地址: " SSL_EMAIL
        if [ -z "$SSL_EMAIL" ]; then
            log_error "邮箱不能为空"
            exit 1
        fi
    fi

    log_info "通知邮箱: $SSL_EMAIL"
}

# ── DNS 预检查 ─────────────────────────────────
check_dns() {
    log_step "检查 DNS 解析..."

    local server_ip
    server_ip=$(curl -s --max-time 5 https://ifconfig.me 2>/dev/null || curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "unknown")

    if [ "$server_ip" = "unknown" ]; then
        log_warn "无法获取本机公网 IP，跳过 DNS 检查"
        return 0
    fi

    log_info "本机公网 IP: $server_ip"

    # 检查 A 记录
    local resolved_ip
    resolved_ip=$(dig +short "$DOMAIN_NAME" A 2>/dev/null | tail -1 || echo "")
    if [ -z "$resolved_ip" ]; then
        log_warn "无法解析 $DOMAIN_NAME（DNS 可能尚未生效）"
        echo "  请确保已在 Spaceship 添加 A 记录: $DOMAIN_NAME → $server_ip"
        echo "  参考: docker/SPACESHIP-DNS.md"
        echo ""
        read -r -p "DNS 可能未生效，是否继续？[y/N] " yn
        if [ "${yn,,}" != "y" ]; then
            exit 0
        fi
    elif [ "$resolved_ip" != "$server_ip" ]; then
        log_warn "DNS 解析 ($resolved_ip) 与本机 IP ($server_ip) 不一致"
        echo "  可能原因: DNS 缓存未刷新 / 尚未生效"
        read -r -p "是否继续？[y/N] " yn
        if [ "${yn,,}" != "y" ]; then
            exit 0
        fi
    else
        log_info "✓ DNS 解析正确: $DOMAIN_NAME → $resolved_ip"
    fi
}

# ── 检查 HTTP 可访问性 ─────────────────────────
check_http() {
    log_step "检查端口 80 可访问性..."

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://$DOMAIN_NAME/health" 2>/dev/null || echo "000")

    if [ "$http_code" = "200" ]; then
        log_info "✓ HTTP /health 可访问"
    else
        log_warn "HTTP /health 返回 $http_code（预期 200）"
        echo "  排查: docker compose ps | grep nginx"
        echo "  排查: sudo ufw status"
    fi
}

# ── 主流程 ────────────────────────────────────
main() {
    local mode="${1:-}"

    if [ "$mode" = "-h" ] || [ "$mode" = "--help" ]; then
        usage
    fi

    echo ""
    echo "=========================================="
    echo "  aiflowhub.ai SSL 证书管理"
    echo "  Let's Encrypt + Certbot"
    echo "=========================================="
    echo ""

    load_email

    case "$mode" in
        --staging)
            log_info "STAGING 测试模式"
            export STAGING=1
            export DOMAIN_NAME SSL_EMAIL
            exec bash "${SCRIPT_DIR}/ssl-setup.sh"
            ;;
        --renew)
            export DOMAIN_NAME SSL_EMAIL
            exec bash "${SCRIPT_DIR}/ssl-setup.sh" --renew
            ;;
        --status)
            export DOMAIN_NAME SSL_EMAIL
            exec bash "${SCRIPT_DIR}/ssl-setup.sh" --status
            ;;
        --setup-cron)
            export DOMAIN_NAME SSL_EMAIL
            exec bash "${SCRIPT_DIR}/ssl-setup.sh" --setup-cron
            ;;
        *)
            # 首次签发完整流程
            check_dns
            check_http

            echo ""
            log_step "开始签发 SSL 证书..."
            echo ""

            export DOMAIN_NAME SSL_EMAIL
            exec bash "${SCRIPT_DIR}/ssl-setup.sh"
            ;;
    esac
}

main "${@}"
