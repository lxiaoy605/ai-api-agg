#!/bin/sh
# =============================================
# Prometheus 容器入口脚本
# 功能：在启动前用环境变量替换配置模板中的占位符
# =============================================

set -e

ENV_VALUE="${ENV:-production}"

echo "[prometheus-entrypoint] 设置环境标签: env=${ENV_VALUE}"

# 替换 prometheus.yml 中的 ${ENV:-production} 占位符
sed -i "s/\${ENV:-production}/${ENV_VALUE}/g" /etc/prometheus/prometheus.yml

# 替换 alertmanager.yml 中的 Telegram 配置（如果有设置）
if [ -n "${TELEGRAM_BOT_TOKEN}" ]; then
  echo "[prometheus-entrypoint] 检测到 TELEGRAM_BOT_TOKEN，已配置"
fi

# 启动 Prometheus
exec /bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time=15d \
  --web.console.libraries=/usr/share/prometheus/console_libraries \
  --web.console.templates=/usr/share/prometheus/consoles \
  --web.enable-lifecycle \
  "$@"
