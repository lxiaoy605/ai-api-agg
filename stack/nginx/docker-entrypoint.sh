#!/bin/sh
set -e

DOMAIN="${DOMAIN_NAME:-localhost}"
echo "[entrypoint] DOMAIN=${DOMAIN}"

# 替换 http.conf 中的域名变量
sed "s/\${DOMAIN_NAME}/${DOMAIN}/g" /etc/nginx/conf.d/http.conf > /tmp/http.conf
cp /tmp/http.conf /etc/nginx/conf.d/http.conf

# 开发模式：跳过 HTTPS
echo "[entrypoint] Dev mode: HTTP only (no SSL cert)"

echo "[entrypoint] 验证 nginx 配置..."
nginx -t

echo "[entrypoint] 启动 nginx..."
exec nginx -g "daemon off;"
