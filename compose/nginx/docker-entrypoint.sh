#!/bin/sh
set -e

echo "[entrypoint] DOMAIN_NAME=${DOMAIN_NAME:-localhost}"

# 生成 http-only 配置（开发环境无 SSL 证书）
echo "[entrypoint] Dev mode: HTTP only (no SSL)"
cp /etc/nginx/conf.d/http.conf /tmp/nginx-http.conf

# 如果有 https.conf.template，替换为空的（避免 nginx 报错）
if [ -f /etc/nginx/conf.d/https.conf ]; then
    rm /etc/nginx/conf.d/https.conf
fi

echo "[entrypoint] 验证 nginx 配置..."
nginx -t

echo "[entrypoint] 启动 nginx..."
exec nginx -g "daemon off;"
