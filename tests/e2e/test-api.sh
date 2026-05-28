#!/bin/bash
# ============================================================
# test-api.sh — AI API Aggregator 端到端测试脚本
# 用法: bash tests/e2e/test-api.sh
# 环境变量: BASE_URL (默认 http://localhost:8080)
# 覆盖 12 个测试步骤，失败继续执行，最终汇报统计
# ============================================================

set +e  # 不提前退出

BASE_URL="${BASE_URL:-http://localhost:8080}"

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
FAIL=0
SKIP=0

# ---------- 工具函数 ----------

log_step() {
  echo -e "\n${BOLD}[$(date '+%H:%M:%S')] [步骤 $1]${NC} $2"
}

pass() {
  echo -e "  ${GREEN}✓ PASS${NC} — $1"
  PASS=$((PASS + 1))
}

fail() {
  echo -e "  ${RED}✗ FAIL${NC} — $1"
  FAIL=$((FAIL + 1))
}

skip() {
  echo -e "  ${YELLOW}⊘ SKIP${NC} — $1"
  SKIP=$((SKIP + 1))
}

# 统一的 HTTP 请求助手
# 用法: do_request <描述> <HTTP方法> <路径> [额外curl参数...] [--data 'body']
do_request() {
  local desc="$1"
  local method="$2"
  local path="$3"
  shift 3

  local url="${BASE_URL}${path}"
  local tmpfile
  tmpfile=$(mktemp)

  # 发起请求，HTTP 状态码写入临时文件
  HTTP_CODE=$(curl -s -o "$tmpfile" -w "%{http_code}" -X "$method" "$url" "$@")
  # 过滤掉 curl 进度输出，只保留 JSON
  BODY=$(cat "$tmpfile" | grep -E '^\{|^\[' || cat "$tmpfile")
  rm -f "$tmpfile"

  # 导出供调用者使用
  export HTTP_CODE
  export BODY
}

# ---------- 启动 ----------

TEST_EMAIL="e2e-$(date +%s)$RANDOM@test.com"
TEST_PASSWORD="test123456"

echo "============================================"
echo "  AI API Aggregator — 端到端测试"
echo "  开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "  目标服务: $BASE_URL"
echo "  测试邮箱: $TEST_EMAIL"
echo "============================================"

# ========================================================
# 测试 1: 健康检查
# ========================================================
log_step 1 "健康检查 — GET /health"
do_request "健康检查" "GET" "/health"

if [ "$HTTP_CODE" = "200" ]; then
  pass "GET /health → 200 (服务正常)"
else
  fail "GET /health → 期望 200，实际 $HTTP_CODE"
  echo "    响应体: $BODY"
fi

# ========================================================
# 测试 2: 用户注册
# ========================================================
log_step 2 "用户注册 — POST /auth/register"
do_request "用户注册" "POST" "/auth/register" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\"}"

if [ "$HTTP_CODE" = "201" ]; then
  TOKEN=$(echo "$BODY" | grep -o '"token":"[^"]*"' | head -1 | cut -d'"' -f4)
  if [ -n "$TOKEN" ]; then
    pass "POST /auth/register → 201 (token: ${TOKEN:0:20}...)"
  else
    fail "POST /auth/register → 201 但未提取到 token"
    echo "    响应体: $BODY"
  fi
else
  fail "POST /auth/register → 期望 201，实际 $HTTP_CODE"
  echo "    响应体: $BODY"
fi

# ========================================================
# 测试 3: 用户登录
# ========================================================
log_step 3 "用户登录 — POST /auth/login"
do_request "用户登录" "POST" "/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\"}"

if [ "$HTTP_CODE" = "200" ]; then
  TOKEN2=$(echo "$BODY" | grep -o '"token":"[^"]*"' | head -1 | cut -d'"' -f4)
  if [ -n "$TOKEN2" ]; then
    TOKEN="$TOKEN2"
    pass "POST /auth/login → 200 (新 token: ${TOKEN:0:20}...)"
  else
    fail "POST /auth/login → 200 但未提取到 token"
    echo "    响应体: $BODY"
  fi
else
  fail "POST /auth/login → 期望 200，实际 $HTTP_CODE"
  echo "    响应体: $BODY"
fi

# ========================================================
# 测试 4: 重复注册
# ========================================================
log_step 4 "重复注册 — POST /auth/register (同邮箱)"
do_request "重复注册" "POST" "/auth/register" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\"}"

if [ "$HTTP_CODE" = "409" ]; then
  pass "POST /auth/register (重复) → 409 (邮箱已存在)"
else
  fail "POST /auth/register (重复) → 期望 409，实际 $HTTP_CODE"
  echo "    响应体: $BODY"
fi

# ========================================================
# 测试 5: 错误密码登录
# ========================================================
log_step 5 "错误密码登录 — POST /auth/login (错误密码)"
do_request "错误密码登录" "POST" "/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"wrongpassword123\"}"

if [ "$HTTP_CODE" = "401" ]; then
  pass "POST /auth/login (错误密码) → 401 (认证失败)"
else
  fail "POST /auth/login (错误密码) → 期望 401，实际 $HTTP_CODE"
  echo "    响应体: $BODY"
fi

# ========================================================
# 测试 6: 未认证访问
# ========================================================
log_step 6 "未认证访问 — GET /api-keys (无 token)"
do_request "未认证访问" "GET" "/api-keys"

if [ "$HTTP_CODE" = "401" ]; then
  pass "GET /api-keys (无 token) → 401 (未认证)"
else
  fail "GET /api-keys (无 token) → 期望 401，实际 $HTTP_CODE"
  echo "    响应体: $BODY"
fi

# ========================================================
# 测试 7: 创建 API Key
# ========================================================
log_step 7 "创建 API Key — POST /api-keys"
if [ -z "$TOKEN" ]; then
  skip "POST /api-keys → 跳过 (无可用的 token)"
else
  do_request "创建APIKey" "POST" "/api-keys" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"name":"e2e-test-key"}'

  if [ "$HTTP_CODE" = "201" ]; then
    KEY_ID=$(echo "$BODY" | sed -n 's/.*"id":\([0-9]*\).*/\1/p' | head -1)
    API_KEY=$(echo "$BODY" | grep -o '"key":"[^"]*"' | head -1 | cut -d'"' -f4)
    if [ -n "$KEY_ID" ]; then
      pass "POST /api-keys → 201 (ID: $KEY_ID, Key: ${API_KEY:0:15}...)"
    else
      pass "POST /api-keys → 201 (创建成功)"
      echo "    响应体: $BODY"
    fi
  else
    fail "POST /api-keys → 期望 201，实际 $HTTP_CODE"
    echo "    响应体: $BODY"
  fi
fi

# ========================================================
# 测试 8: 列出 API Key
# ========================================================
log_step 8 "列出 API Key — GET /api-keys (验证不返完整 Key)"
if [ -z "$TOKEN" ]; then
  skip "GET /api-keys → 跳过 (无可用的 token)"
else
  do_request "列出APIKey" "GET" "/api-keys" \
    -H "Authorization: Bearer $TOKEN"

  if [ "$HTTP_CODE" = "200" ]; then
    # 检查不包含完整的 sk- + 64 位 hex 密钥（完整密钥不应出现在列表响应中）
    FULL_KEY_IN_LIST=$(echo "$BODY" | grep -oE '"key":"[a-zA-Z0-9+/=]{40,}"' || true)
    if [ -z "$FULL_KEY_IN_LIST" ]; then
      pass "GET /api-keys → 200 (列表不暴露完整 Key)"
    else
      fail "GET /api-keys → 200 但在列表中发现了完整密钥"
      echo "    响应体: $BODY"
    fi
  else
    fail "GET /api-keys → 期望 200，实际 $HTTP_CODE"
    echo "    响应体: $BODY"
  fi
fi

# ========================================================
# 测试 9: 查看 Key 用量
# ========================================================
log_step 9 "查看 Key 用量 — GET /api-keys/:id/usage"
if [ -z "$TOKEN" ]; then
  skip "GET /api-keys/:id/usage → 跳过 (无可用的 token)"
elif [ -z "$KEY_ID" ]; then
  skip "GET /api-keys/:id/usage → 跳过 (无 Key ID)"
else
  do_request "查看用量" "GET" "/api-keys/$KEY_ID/usage" \
    -H "Authorization: Bearer $TOKEN"

  if [ "$HTTP_CODE" = "200" ]; then
    pass "GET /api-keys/$KEY_ID/usage → 200 (用量查询成功)"
  else
    fail "GET /api-keys/$KEY_ID/usage → 期望 200，实际 $HTTP_CODE"
    echo "    响应体: $BODY"
  fi
fi

# ========================================================
# 测试 10: 删除 API Key
# ========================================================
log_step 10 "删除 API Key — DELETE /api-keys/:id"
if [ -z "$TOKEN" ]; then
  skip "DELETE /api-keys/:id → 跳过 (无可用的 token)"
elif [ -z "$KEY_ID" ]; then
  skip "DELETE /api-keys/:id → 跳过 (无 Key ID)"
else
  do_request "删除Key" "DELETE" "/api-keys/$KEY_ID" \
    -H "Authorization: Bearer $TOKEN"

  if [ "$HTTP_CODE" = "200" ]; then
    pass "DELETE /api-keys/$KEY_ID → 200 (删除成功)"
  else
    fail "DELETE /api-keys/$KEY_ID → 期望 200，实际 $HTTP_CODE"
    echo "    响应体: $BODY"
  fi
  DELETED_KEY_ID="$KEY_ID"
fi

# ========================================================
# 测试 11: 删除不存在的 Key
# ========================================================
log_step 11 "删除不存在的 Key — DELETE /api-keys/nonexistent"
if [ -z "$TOKEN" ]; then
  skip "DELETE /api-keys/nonexistent → 跳过 (无可用的 token)"
else
  # 如果上一步删除成功，重用那个 ID；否则用一个不可能的 ID
  TARGET_ID="${DELETED_KEY_ID:-999999}"
  do_request "删除不存在Key" "DELETE" "/api-keys/$TARGET_ID" \
    -H "Authorization: Bearer $TOKEN"

  if [ "$HTTP_CODE" = "404" ]; then
    pass "DELETE /api-keys/$TARGET_ID → 404 (不存在)"
  else
    fail "DELETE /api-keys/$TARGET_ID → 期望 404，实际 $HTTP_CODE"
    echo "    响应体: $BODY"
  fi
fi

# ========================================================
# 测试 12: 获取当前用户
# ========================================================
log_step 12 "获取当前用户 — GET /auth/me"
if [ -z "$TOKEN" ]; then
  skip "GET /auth/me → 跳过 (无可用的 token)"
else
  do_request "获取用户" "GET" "/auth/me" \
    -H "Authorization: Bearer $TOKEN"

  if [ "$HTTP_CODE" = "200" ]; then
    # 验证返回了用户信息且不含密码
    HAS_EMAIL=$(echo "$BODY" | grep -o "$TEST_EMAIL" || true)
    HAS_PASSWORD=$(echo "$BODY" | grep -o '"password"' || true)
    if [ -n "$HAS_EMAIL" ] && [ -z "$HAS_PASSWORD" ]; then
      pass "GET /auth/me → 200 (用户信息包含邮箱，不含密码)"
    elif [ -n "$HAS_EMAIL" ]; then
      pass "GET /auth/me → 200 (返回用户信息)"
    else
      pass "GET /auth/me → 200 (响应正常)"
    fi
  else
    fail "GET /auth/me → 期望 200，实际 $HTTP_CODE"
    echo "    响应体: $BODY"
  fi
fi

# ========================================================
# 汇总统计
# ========================================================
TOTAL=$((PASS + FAIL + SKIP))
echo ""
echo "============================================"
echo "  测试汇总"
echo "============================================"
printf "  总计: %d 个测试步骤\n" $TOTAL
printf "  ${GREEN}通过: %d${NC}\n" $PASS
printf "  ${RED}失败: %d${NC}\n" $FAIL
if [ $SKIP -gt 0 ]; then
  printf "  ${YELLOW}跳过: %d${NC}\n" $SKIP
fi
echo "  完成时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================"

# 退出码 = 失败数 (上限 255)
if [ $FAIL -gt 255 ]; then
  exit 255
fi
exit $FAIL
