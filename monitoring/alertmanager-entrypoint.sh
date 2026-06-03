#!/bin/sh
# =============================================
# Alertmanager 容器入口脚本
# 功能：在启动前用环境变量替换 Telegram 配置占位符
# =============================================

set -e

echo "[alertmanager-entrypoint] 初始化 Alertmanager"

# 复制配置文件到可写位置（原文件是只读挂载）
cp /etc/alertmanager/alertmanager.yml /tmp/alertmanager.yml
CONFIG_FILE="/tmp/alertmanager.yml"

# 替换 Telegram Bot Token
if [ -n "${TELEGRAM_BOT_TOKEN}" ]; then
  echo "[alertmanager-entrypoint] 配置 Telegram Bot Token"
  sed -i "s/\${TELEGRAM_BOT_TOKEN:-YOUR_BOT_TOKEN_HERE}/${TELEGRAM_BOT_TOKEN}/g" "$CONFIG_FILE"
fi

# 替换 Telegram Chat ID
if [ -n "${TELEGRAM_CHAT_ID}" ]; then
  echo "[alertmanager-entrypoint] 配置 Telegram Chat ID"
  sed -i "s/\${TELEGRAM_CHAT_ID:-YOUR_CHAT_ID_HERE}/${TELEGRAM_CHAT_ID}/g" "$CONFIG_FILE"
fi

echo "[alertmanager-entrypoint] 启动 Alertmanager"

exec /bin/alertmanager \
  --config.file="$CONFIG_FILE" \
  --storage.path=/alertmanager \
  --log.level=info \
  "$@"
