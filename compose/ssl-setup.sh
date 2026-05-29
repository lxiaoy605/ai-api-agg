#!/bin/bash
# =============================================
# SSL 自动配置脚本 — Let's Encrypt Certbot
# =============================================
#
# 架构：宿主机 Certbot + Docker Nginx
#   - Certbot 在宿主机运行，通过 HTTP-01 webroot 验证
#   - Nginx 在 Docker 容器中，serve /.well-known/acme-challenge/
#   - SSL 证书存储在宿主机 /etc/letsencrypt/，挂载进容器
#
# 用法：
#   chmod +x ssl-setup.sh
#   sudo DOMAIN_NAME=api.example.com SSL_EMAIL=admin@example.com ./ssl-setup.sh
#   sudo ./ssl-setup.sh --renew        # 仅续期
#   sudo ./ssl-setup.sh --status       # 查看证书状态
#   sudo ./ssl-setup.sh --setup-cron   # 仅配置自动续期
#
# 前置条件：
#   1. 域名 DNS 已指向本机 IP
#   2. Docker Compose 已启动（nginx 容器运行中，端口 80 可访问）
#   3. 防火墙放行 80/443
# =============================================

set -euo pipefail

# ── 配置变量（可通过环境变量覆盖）─────────────────
DOMAIN_NAME="${DOMAIN_NAME:-}"
SSL_EMAIL="${SSL_EMAIL:-}"
STAGING="${STAGING:-0}"                      # 1=Let's Encrypt staging 测试
DRY_RUN="${DRY_RUN:-0}"                      # 1=模拟运行
NGINX_CONTAINER="${NGINX_CONTAINER:-ai-api-agg-nginx}"
CERTBOT_WWW="${CERTBOT_WWW:-/var/www/certbot}"   # HTTP-01 webroot（与 nginx http.conf 配置一致）
LETSENCRYPT_DIR="/etc/letsencrypt"

# 脚本路径
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
用法: sudo DOMAIN_NAME=<域名> SSL_EMAIL=<邮箱> $0 [选项]

选项:
  (无参数)         首次签发证书 + 配置自动续期
  --renew          检查并续期证书（适合 cron 调用）
  --status         查看证书状态
  --setup-cron     仅配置自动续期 cron

环境变量:
  DOMAIN_NAME       域名（必填，如 api.example.com）
  SSL_EMAIL         通知邮箱（必填）
  STAGING=1         使用 Let's Encrypt staging 环境测试
  DRY_RUN=1         模拟运行，不真正签发
  NGINX_CONTAINER   Nginx 容器名（默认 ai-api-agg-nginx）
  CERTBOT_WWW       HTTP-01 验证目录（默认 /var/www/certbot）

示例:
  # 首次签发
  sudo DOMAIN_NAME=api.example.com SSL_EMAIL=admin@example.com ./ssl-setup.sh

  # 测试模式（避免触发 Let's Encrypt 频率限制）
  sudo STAGING=1 DOMAIN_NAME=api.example.com SSL_EMAIL=admin@example.com ./ssl-setup.sh

  # 查看状态
  sudo DOMAIN_NAME=api.example.com ./ssl-setup.sh --status
EOF
    exit 0
}

# ── 从 .env 加载变量 ──────────────────────────
load_env_file() {
    if [ -f "$ENV_FILE" ]; then
        log_info "加载环境变量: $ENV_FILE"
        set -a
        source "$ENV_FILE"
        set +a
    fi
}

# ── 参数校验 ──────────────────────────────────
validate_params() {
    if [ -z "$DOMAIN_NAME" ]; then
        log_error "DOMAIN_NAME 未设置"
        echo "  方式1: sudo DOMAIN_NAME=api.example.com SSL_EMAIL=admin@example.com $0"
        echo "  方式2: 在 ${ENV_FILE} 中配置 DOMAIN_NAME 和 SSL_EMAIL"
        exit 1
    fi

    if [ -z "$SSL_EMAIL" ]; then
        log_error "SSL_EMAIL 未设置"
        exit 1
    fi

    log_info "域名: $DOMAIN_NAME"
    log_info "邮箱: $SSL_EMAIL"
    [ "$STAGING" = "1" ] && log_warn "⚠ STAGING 模式 — 将使用测试证书"
}

# ── 安装 Certbot ──────────────────────────────
install_certbot() {
    if command -v certbot &>/dev/null; then
        log_info "certbot 已安装: $(certbot --version 2>&1 | head -1)"
        return 0
    fi

    log_step "安装 Certbot..."
    if command -v snap &>/dev/null; then
        sudo snap install --classic certbot
        sudo ln -sf /snap/bin/certbot /usr/bin/certbot
    elif command -v apt-get &>/dev/null; then
        sudo apt-get update -qq
        sudo apt-get install -y -qq certbot
    elif command -v yum &>/dev/null; then
        sudo yum install -y certbot
    else
        log_error "无法自动安装 certbot，请手动安装: https://certbot.eff.org/"
        exit 1
    fi
    log_info "✓ Certbot 安装完成"
}

# ── 准备 webroot 目录 ─────────────────────────
prepare_webroot() {
    if [ ! -d "$CERTBOT_WWW" ]; then
        log_info "创建 HTTP-01 验证目录: $CERTBOT_WWW"
        sudo mkdir -p "$CERTBOT_WWW"
    fi
    # 确保 nginx 容器内用户可读
    sudo chmod 755 /var/www /var/www/certbot 2>/dev/null || true
}

# ── 确保 Nginx 容器在运行 ─────────────────────
check_nginx_container() {
    if ! command -v docker &>/dev/null; then
        log_warn "docker 命令不可用，跳过容器检查"
        return 0
    fi

    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${NGINX_CONTAINER}$"; then
        log_info "✓ Nginx 容器运行中: $NGINX_CONTAINER"
    else
        log_warn "Nginx 容器 ($NGINX_CONTAINER) 未运行"
        log_warn "请先启动: docker compose -f docker/docker-compose.yml up -d nginx"
        log_warn "SSL 证书签发需要端口 80 可访问"
    fi
}

# ── 重载 Nginx ────────────────────────────────
reload_nginx() {
    if command -v docker &>/dev/null; then
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${NGINX_CONTAINER}$"; then
            log_info "重载 Nginx 容器..."
            if docker exec "$NGINX_CONTAINER" nginx -s reload 2>/dev/null; then
                log_info "✓ Nginx 已重载"
            else
                log_warn "Nginx 重载失败（可能容器使用了不同的信号机制），尝试重启..."
                docker restart "$NGINX_CONTAINER" 2>/dev/null || true
            fi
        else
            log_warn "Nginx 容器未运行，跳过重载"
        fi
    fi
}

# ── 验证 Nginx 配置 ───────────────────────────
verify_nginx_config() {
    if command -v docker &>/dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${NGINX_CONTAINER}$"; then
        if ! docker exec "$NGINX_CONTAINER" nginx -t 2>&1; then
            log_error "Nginx 配置有语法错误，请修复后重试"
            exit 1
        fi
    fi
}

# ── 签发证书 ──────────────────────────────────
issue_certificate() {
    local cert_path="$LETSENCRYPT_DIR/live/$DOMAIN_NAME/fullchain.pem"

    if [ -f "$cert_path" ]; then
        log_info "证书已存在: $cert_path"
        log_info "检查到期时间..."
        local expiry
        expiry=$(openssl x509 -enddate -noout -in "$cert_path" 2>/dev/null | cut -d= -f2)
        log_info "  到期时间: $expiry"
        return 0
    fi

    log_step "签发 SSL 证书: $DOMAIN_NAME"
    echo ""

    local certbot_args=(
        certonly
        --webroot
        --webroot-path "$CERTBOT_WWW"
        --domain "$DOMAIN_NAME"
        --email "$SSL_EMAIL"
        --agree-tos
        --no-eff-email
        --non-interactive
        --deploy-hook "docker exec $NGINX_CONTAINER nginx -s reload 2>/dev/null || true"
    )

    [ "$STAGING" = "1" ] && certbot_args+=(--staging)
    [ "$DRY_RUN" = "1" ] && certbot_args+=(--dry-run)

    if sudo certbot "${certbot_args[@]}"; then
        log_info "✓ 证书签发成功!"
        log_info "  证书: $cert_path"
        log_info "  私钥: $LETSENCRYPT_DIR/live/$DOMAIN_NAME/privkey.pem"
        log_info "  链:   $LETSENCRYPT_DIR/live/$DOMAIN_NAME/chain.pem"
        reload_nginx
    else
        log_error "证书签发失败！"
        echo ""
        echo "  排查步骤:"
        echo "  1. 确认 DNS 已解析: dig +short $DOMAIN_NAME"
        echo "  2. 确认端口 80 可访问: curl -I http://$DOMAIN_NAME/.well-known/acme-challenge/"
        echo "  3. 检查防火墙: sudo ufw status"
        echo "  4. 测试模式重试: sudo STAGING=1 DOMAIN_NAME=$DOMAIN_NAME SSL_EMAIL=$SSL_EMAIL $0"
        exit 1
    fi
}

# ── 续期证书 ──────────────────────────────────
renew_certificate() {
    log_step "检查证书续期..."

    if [ ! -d "$LETSENCRYPT_DIR/live/$DOMAIN_NAME" ]; then
        log_warn "未找到现有证书，将执行首次签发"
        issue_certificate
        return
    fi

    # certbot renew 只处理 30 天内到期的证书
    sudo certbot renew \
        --quiet \
        --deploy-hook "docker exec $NGINX_CONTAINER nginx -s reload 2>/dev/null || true" \
        2>&1 || {
        log_error "证书续期失败！"
        exit 1
    }

    log_info "✓ 续期检查完成"
}

# ── 配置自动续期 cron ─────────────────────────
setup_cron() {
    log_step "配置自动续期定时任务..."

    local safe_domain="${DOMAIN_NAME//./-}"
    local cron_file="/etc/cron.d/certbot-renew-${safe_domain}"
    local log_file="/var/log/certbot-renew-${safe_domain}.log"

    # 每天凌晨 3:23 和 15:23 各检查一次（错峰避免全互联网同一分钟冲刺 Let's Encrypt）
    local cron_content="23 3,15 * * * root DOMAIN_NAME='${DOMAIN_NAME}' SSL_EMAIL='${SSL_EMAIL}' ${SCRIPT_DIR}/ssl-setup.sh --renew >> ${log_file} 2>&1"

    # 检查是否已存在相同配置
    if [ -f "$cron_file" ]; then
        log_info "cron 任务已存在: $cron_file"
        return 0
    fi

    echo "$cron_content" | sudo tee "$cron_file" > /dev/null
    sudo chmod 644 "$cron_file"

    log_info "✓ 自动续期已配置"
    log_info "  Cron 文件: $cron_file"
    log_info "  执行时间: 每天 03:23 和 15:23"
    log_info "  续期日志: $log_file"

    # 同时启用 certbot 自带的 systemd timer（如果存在）
    if command -v systemctl &>/dev/null; then
        sudo systemctl enable --now certbot.timer 2>/dev/null || true
    fi
}

# ── 查看证书状态 ──────────────────────────────
check_status() {
    local cert_path="$LETSENCRYPT_DIR/live/$DOMAIN_NAME/fullchain.pem"

    if [ ! -f "$cert_path" ]; then
        log_warn "未找到证书: $cert_path"
        echo "  请先运行签发: sudo DOMAIN_NAME=$DOMAIN_NAME SSL_EMAIL=$SSL_EMAIL $0"
        exit 1
    fi

    echo ""
    echo "=========================================="
    echo "  SSL 证书状态"
    echo "=========================================="
    echo ""
    echo "  域名:     $DOMAIN_NAME"
    echo "  证书路径: $cert_path"
    echo "  签发者:   $(openssl x509 -in "$cert_path" -noout -issuer 2>/dev/null | sed 's/.*CN=//;s/\/.*//')"
    echo "  主题:     $(openssl x509 -in "$cert_path" -noout -subject 2>/dev/null | sed 's/.*CN=//;s/\/.*//')"
    echo "  生效时间: $(openssl x509 -in "$cert_path" -noout -startdate 2>/dev/null | cut -d= -f2)"
    echo "  到期时间: $(openssl x509 -in "$cert_path" -noout -enddate 2>/dev/null | cut -d= -f2)"

    # 计算剩余天数
    local expiry_epoch
    expiry_epoch=$(openssl x509 -in "$cert_path" -noout -enddate 2>/dev/null | cut -d= -f2)
    expiry_epoch=$(date -d "$expiry_epoch" +%s 2>/dev/null || echo 0)
    local now_epoch
    now_epoch=$(date +%s)
    local days_left=$(( (expiry_epoch - now_epoch) / 86400 ))

    echo "  剩余天数: ${days_left} 天"
    if [ "$days_left" -lt 30 ]; then
        log_warn "⚠ 证书将在 ${days_left} 天后过期，建议执行续期"
    fi
    echo ""

    # 证书详情
    echo "  SAN:"
    openssl x509 -in "$cert_path" -noout -ext subjectAltName 2>/dev/null | sed 's/^/    /'
    echo ""

    if command -v certbot &>/dev/null; then
        sudo certbot certificates -d "$DOMAIN_NAME" 2>/dev/null || true
    fi
}

# ── 验证 HTTPS 可访问 ─────────────────────────
verify_https() {
    log_step "验证 HTTPS..."

    if ! command -v curl &>/dev/null; then
        log_warn "curl 未安装，跳过验证"
        return
    fi

    # 等待 nginx 生效
    sleep 2

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "https://$DOMAIN_NAME/health" 2>/dev/null || echo "000")
    if [ "$http_code" = "200" ]; then
        log_info "✓ HTTPS 可访问 (HTTP $http_code)"
    else
        log_warn "HTTPS /health 返回 $http_code（可能是证书刚签发尚未生效）"
    fi

    # 验证 HTTP → HTTPS 重定向
    local redirect_code
    redirect_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://$DOMAIN_NAME/" 2>/dev/null || echo "000")
    if [ "$redirect_code" = "301" ]; then
        log_info "✓ HTTP → HTTPS 重定向正常"
    else
        log_warn "HTTP 重定向返回 $redirect_code（预期 301）"
    fi
}

# ── 主流程 ────────────────────────────────────
main() {
    # 帮助
    if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
        usage
    fi

    # 加载 .env 中的变量（命令行传入的优先级更高，故先加载）
    load_env_file

    echo ""
    echo "=========================================="
    echo "  ai-api-agg SSL 证书管理"
    echo "=========================================="
    echo "  域名: ${DOMAIN_NAME:-<未设置>}"
    echo "  邮箱: ${SSL_EMAIL:-<未设置>}"
    echo "=========================================="
    echo ""

    case "${1:-}" in
        --renew)
            validate_params
            check_nginx_container
            renew_certificate
            ;;
        --status)
            validate_params
            check_status
            ;;
        --setup-cron)
            validate_params
            setup_cron
            ;;
        *)
            validate_params
            install_certbot
            prepare_webroot
            check_nginx_container
            issue_certificate
            setup_cron
            verify_https

            echo ""
            echo "=========================================="
            echo "  SSL 配置完成!"
            echo "=========================================="
            echo ""
            echo "  站点:     https://$DOMAIN_NAME"
            echo "  证书目录: /etc/letsencrypt/live/$DOMAIN_NAME/"
            echo ""
            echo "  安全检测:"
            echo "    https://www.ssllabs.com/ssltest/analyze.html?d=$DOMAIN_NAME"
            echo ""
            echo "  手动续期:"
            echo "    sudo $0 --renew"
            echo ""
            ;;
    esac
}

main "$@"
