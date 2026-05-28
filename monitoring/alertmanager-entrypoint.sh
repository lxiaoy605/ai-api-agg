#!/bin/sh
# =============================================
# Alertmanager 容器入口脚本
# 功能：在启动前用环境变量替换 Telegram 配置占位符
# =============================================

set -e

echo "[alertmanager-entrypoint] 初始化 Alertmanager"

# 替换 Telegram Bot Token（如果设置了环境变量）
if [ -n "${TELEGRAM_BOT_TOKEN}" ]; then
  echo "[alertmanager-entrypoint] 配置 Telegram Bot Token"
  sed -i "s/\${TELEGRAM_BOT_TOKEN:-YOUR_BOT_TOKEN_HERE}/${TELEGRAM_BOT_TOKEN}/g" /etc/alertmanager/alertmanager.yml
fi

# 替换 Telegram Chat ID（如果设置了环境变量）
if [ -n "${TELEGRAM_CHAT_ID}" ]; then
  echo "[alertmanager-entrypoint] 配置 Telegram Chat ID"
  sed -i "s/\${TELEGRAM_CHAT_ID:-YOUR_CHAT_ID_HERE}/${TELEGRAM_CHAT_ID}/g" /etc/alertmanager/alertmanager.yml
fi

echo "[alertmanager-entrypoint] 启动 Alertmanager"

exec /bin/alertmanager \
  --config.file=/etc/alertmanager/alertmanager.yml \
  --storage.path=/alertmanager \
  --log.level=info \
  "$@"
