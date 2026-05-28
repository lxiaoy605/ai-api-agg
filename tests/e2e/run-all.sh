#!/bin/bash
# ============================================================
# run-all.sh — 端到端测试入口
# 调用 test-api.sh，返回统一退出码
# 用法: bash tests/e2e/run-all.sh
# 全部通过 = 退出码 0，否则 = 失败数
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "============================================"
echo "  启动全栈端到端测试套件"
echo "============================================"
echo ""

if [ ! -f "$SCRIPT_DIR/test-api.sh" ]; then
  echo "✗ 错误: 找不到 test-api.sh"
  exit 1
fi

# 传递环境变量给子脚本
export BASE_URL="${BASE_URL:-http://localhost:8080}"

bash "$SCRIPT_DIR/test-api.sh"
EXIT_CODE=$?

echo ""
if [ $EXIT_CODE -eq 0 ]; then
  echo -e "\033[0;32m✓ 所有测试通过!\033[0m"
else
  echo -e "\033[0;31m✗ $EXIT_CODE 个测试失败\033[0m"
fi

exit $EXIT_CODE
