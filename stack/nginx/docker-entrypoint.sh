#!/bin/sh
set -e

DOMAIN="${DOMAIN_NAME:-localhost}"
CERT_PATH="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
CERT_DIR="/etc/letsencrypt/live/${DOMAIN}"

# 替换域名变量
sed "s/\${DOMAIN_NAME}/${DOMAIN}/g" /etc/nginx/conf.d/http.conf > /tmp/http.conf
cp /tmp/http.conf /etc/nginx/conf.d/http.conf

# 检测证书
if [ -f "$CERT_PATH" ]; then
    echo "[entrypoint] SSL cert found — enabling HTTPS"
    sed "s/\${DOMAIN_NAME}/${DOMAIN}/g" /etc/nginx/conf.d/https.template > /etc/nginx/conf.d/https.conf
else
    echo "[entrypoint] No SSL cert — HTTP only"
    # 删除 HTTPS 模板，避免 nginx 加载
    rm -f /etc/nginx/conf.d/https.template /etc/nginx/conf.d/https.conf
fi

echo "[entrypoint] 验证 nginx 配置..."
nginx -t

echo "[entrypoint] 启动 nginx..."
exec nginx -g "daemon off;"
