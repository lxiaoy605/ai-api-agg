#!/bin/bash
# scripts/update-model-catalog.sh
# 月度模型目录更新：拉取 → 增量富化 → 分页输出
# 由 cron 每月 1 号凌晨 3:00 触发

set -euo pipefail
cd "$(dirname "$0")/.."

# 加载环境变量
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

if [ -z "${ENRICH_API_KEY:-}" ]; then
    echo "❌ ENRICH_API_KEY 未设置"
    exit 1
fi

LOG_FILE="logs/model-update-$(date +%Y%m%d-%H%M).log"
mkdir -p logs
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== AI模型目录月度更新 ==="
echo "开始: $(date)"
echo ""

# 1. 拉取最新数据
echo "📡 [1/2] 从 OpenRouter 拉取模型数据..."
python3 -u scripts/fetch-models.py
echo ""

# 2. 增量生成多语言介绍（跳过已有） → 输出分页文件
echo "🤖 [2/2] 增量生成多语言介绍（分页输出）..."
python3 -u scripts/enrich-models.py --pages 15
echo ""

echo "=== 更新完成: $(date) ==="
echo "输出: frontend/src/data/models/page-*.json"
