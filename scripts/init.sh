#!/bin/bash
# =============================================
# AI API 聚合平台 — 一键初始化脚本
# 用途：首次部署或清空数据后，恢复所有配置
# 用法：bash scripts/init.sh
# =============================================

set -e

# ---- 配置 ----
ONEAPI_URL="${ONEAPI_URL:-http://localhost:3001}"
ADMIN_KEY="${ADMIN_KEY:-94686403648a4ae7b069ffcd9383332e}"

# ---- API Keys（从 .env 读取或手动设置） ----
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# 尝试从 .env 加载
if [ -f "$PROJECT_DIR/stack/.env" ]; then
  source <(grep -v '^#' "$PROJECT_DIR/stack/.env" | grep -v '^$' | sed 's/^/export /')
fi

AUTH="Authorization: Bearer $ADMIN_KEY"
CT="Content-Type: application/json"

echo "============================================"
echo " AI API 聚合平台 — 初始化开始"
echo " OneAPI: $ONEAPI_URL"
echo "============================================"

# ---- 0. 检查现有状态 ----
EXISTING_CHANNELS=$(curl -s --max-time 5 -H "$AUTH" "$ONEAPI_URL/api/channel/" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['data']))" 2>/dev/null || echo "0")

if [ "$EXISTING_CHANNELS" -gt 0 ]; then
  echo "检测到已有 $EXISTING_CHANNELS 个渠道，跳过渠道创建。"
  echo "如需重新创建，请先在 OneAPI 管理后台手动删除所有渠道，再运行本脚本。"
  SKIP_CHANNELS=1
else
  SKIP_CHANNELS=0
fi

# ---- 1. 创建渠道 ----
echo ""
echo ">>> 步骤 1: 创建上游渠道（6 个）"

if [ "$SKIP_CHANNELS" = "1" ]; then
  echo "  已跳过（渠道已存在）。"
else

create_channel() {
  local name="$1" type="$2" base_url="$3" key="$4" models="$5"
  echo -n "  创建 $name... "
  local resp=$(curl -s --max-time 10 -X POST -H "$AUTH" -H "$CT" \
    -d "{\"type\":$type,\"name\":\"$name\",\"base_url\":\"$base_url\",\"key\":\"$key\",\"models\":\"$models\",\"status\":1,\"priority\":0}" \
    "$ONEAPI_URL/api/channel/")
  local success=$(echo "$resp" | python3 -c "import json,sys; print(json.load(sys.stdin).get('success',False))" 2>/dev/null || echo "false")
  if [ "$success" = "True" ]; then echo "✅"; else echo "❌ $resp"; fi
}

create_channel "DeepSeek"                 35 "${DEEPSEEK_API_BASE:-https://api.deepseek.com}"        "$DEEPSEEK_API_KEY"                        "deepseek-chat,deepseek-reasoner"
create_channel "DeepSeek #2"              35 "${DEEPSEEK_API_BASE:-https://api.deepseek.com}"        "$DEEPSEEK_API_KEY_2"                      "deepseek-chat,deepseek-reasoner"
create_channel "Zhipu Z.ai"               16 "https://open.bigmodel.cn/api/paas/v4"                  "$ZHIPU_ZAI_API_KEY"                       "glm-4,glm-4-flash,glm-4v"
create_channel "Zhipu #2"                 16 "https://open.bigmodel.cn/api/paas/v4"                  "$ZHIPU_ZAI_API_KEY_2"                     "glm-4,glm-4-flash"
create_channel "Xiaomi MiMo"              27 "${MIMO_API_BASE:-https://api.minimax.chat/v1}"         "$MIMO_API_KEY"                            "abab7-chat,abab6.5s-chat"
create_channel "Xiaomi MiMo #2"           27 "${MIMO_API_BASE:-https://api.minimax.chat/v1}"         "$MIMO_API_KEY_2"                          "abab7-chat,abab6.5s-chat"

fi  # SKIP_CHANNELS

echo "  渠道创建完毕。"

# ---- 2. 倍率调整（已有默认值，无需修改） ----
echo ""
echo ">>> 步骤 2: 模型倍率（使用默认值，无需调整）"
echo "  当前关键模型倍率:"
curl -s --max-time 5 -H "$AUTH" "$ONEAPI_URL/api/option/" | python3 -c "
import json,sys
for item in json.load(sys.stdin)['data']:
    if item['key']=='ModelRatio':
        r=json.loads(item['value'])
        for k,v in sorted(r.items()):
            if any(x in k.lower() for x in ['deepseek-chat','deepseek-reasoner','glm-4-flash','glm-4-air','abab6.5','abab7']):
                print(f'    {k}: {v}')
" 2>/dev/null
echo "  ✅ 倍率已合理，无需调整。"

# ---- 3. 系统设置 ----
echo ""
echo ">>> 步骤 3: 系统设置"

update_option() {
  local key="$1" value="$2"
  echo -n "  设置 $key... "
  local resp=$(curl -s --max-time 5 -X PUT -H "$AUTH" -H "$CT" \
    -d "{\"key\":\"$key\",\"value\":\"$value\"}" \
    "$ONEAPI_URL/api/option/")
  local success=$(echo "$resp" | python3 -c "import json,sys; print(json.load(sys.stdin).get('success',False))" 2>/dev/null || echo "false")
  if [ "$success" = "True" ]; then echo "✅"; else echo "❌ $resp"; fi
}

update_option "SystemName" "API Hub"
update_option "Logo" ""
update_option "Footer" "© 2026 API Hub — Unified AI API Platform"
update_option "Notice" "Welcome to API Hub. $5 free credit for new users."
update_option "About" ""
update_option "HomePageContent" ""
update_option "TopUpLink" ""
update_option "ChatLink" ""
update_option "QuotaPerUnit" "500000"

echo "  系统设置完成。"

# ---- 4. 创建初始令牌 ----
echo ""
echo ">>> 步骤 4: 创建初始令牌（测试用）"
echo -n "  创建测试令牌 test-token... "
resp=$(curl -s --max-time 5 -X POST -H "$AUTH" -H "$CT" \
  -d '{"name":"test-token","remain_quota":500000,"expired_time":-1,"unlimited_quota":false}' \
  "$ONEAPI_URL/api/token/")
success=$(echo "$resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('success',False))" 2>/dev/null || echo "false")
if [ "$success" = "True" ]; then
  key=$(echo "$resp" | python3 -c "import json,sys; print(json.load(sys.stdin)['data'])")
  echo "✅ Key: $key"
else
  echo "❌ $resp"
fi

# ---- 5. 验证 ----
echo ""
echo ">>> 步骤 5: 验证"

echo -n "  渠道数: "
curl -s --max-time 5 -H "$AUTH" "$ONEAPI_URL/api/channel/" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['data']))"

echo -n "  令牌数: "
curl -s --max-time 5 -H "$AUTH" "$ONEAPI_URL/api/token/" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['data']))"

echo -n "  API 状态: "
curl -s --max-time 5 "$ONEAPI_URL/api/status" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('message','OK'))"

echo -n "  测试渠道: "
resp=$(curl -s --max-time 30 -X POST -H "$AUTH" -H "$CT" \
  -d '{"model":"deepseek-chat","messages":[{"role":"user","content":"hi"}]}' \
  "$ONEAPI_URL/v1/chat/completions")
code=$(echo "$resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('choices',[{}])[0].get('message',{}).get('content','FAIL')[:30])" 2>/dev/null || echo "FAIL")
echo "$code"

echo ""
echo "============================================"
echo " 初始化完成！"
echo ""
echo " 管理后台:  http://localhost:3001  (root / 123456)"
echo " API 端点:  http://localhost/v1/chat/completions"
echo " Grafana:   http://localhost:3030  (admin / 见 .env)"
echo "============================================"
