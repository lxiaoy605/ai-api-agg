#!/bin/bash
# =============================================
# ops-channel-mgmt.sh — 日常渠道/模型维护脚本
# =============================================
# 用途：
#   - 新增模型到已有渠道（sync-models）
#   - 接入新 provider（add-provider）：一键创建渠道 + 同步 abilities
#   - 创建用户令牌（create-token）：带配额设置
#   - 健康检查（health）：检查所有渠道连通性
#
# 用法：
#   bash scripts/ops-channel-mgmt.sh sync-models           # 同步所有渠道的模型列表
#   bash scripts/ops-channel-mgmt.sh add-provider <name>     # 接入新 provider
#   bash scripts/ops-channel-mgmt.sh create-token <name> <quota>  # 创建令牌
#   bash scripts/ops-channel-mgmt.sh health                  # 健康检查
#
# 环境变量（从 stack/.env 加载）：
#   ONEAPI_URL         — OneAPI 地址（默认 http://localhost:3001）
#   ONEAPI_ADMIN_TOKEN — OneAPI 管理员令牌
# =============================================

set -euo pipefail

# ---- 路径 ----
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/stack/.env"

# ---- 默认值 ----
ONEAPI_URL="${ONEAPI_URL:-http://localhost:3001}"
ADMIN_TOKEN="${ONEAPI_ADMIN_TOKEN:-}"

# ---- 颜色 ----
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()    { echo -e "  ${GREEN}✅${NC} $*"; }
fail()  { echo -e "  ${RED}❌${NC} $*"; }
warn()  { echo -e "  ${YELLOW}⚠️${NC}  $*"; }
info()  { echo -e "  ${BLUE}ℹ️${NC}  $*"; }
step()  { echo -e "\n${BOLD}${CYAN}━━━ $* ━━━${NC}"; }

# ---- 工具函数 ----
load_env() {
  if [ -f "$ENV_FILE" ]; then
    set -a; source "$ENV_FILE" 2>/dev/null || true; set +a
  fi
  ADMIN_TOKEN="${ONEAPI_ADMIN_TOKEN:-$ADMIN_TOKEN}"
}

# OneAPI API 调用
api() {
  local method="$1" endpoint="$2" data="${3:-}"
  if [ -z "$ADMIN_TOKEN" ]; then
    fail "ONEAPI_ADMIN_TOKEN 未设置"
    exit 1
  fi
  if [ -n "$data" ]; then
    curl -s -X "$method" "$ONEAPI_URL$endpoint" \
      -H "Authorization: Bearer $ADMIN_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$data"
  else
    curl -s -X "$method" "$ONEAPI_URL$endpoint" \
      -H "Authorization: Bearer $ADMIN_TOKEN"
  fi
}

# 检查 OneAPI 连通性
check_connection() {
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$ONEAPI_URL/api/status" 2>/dev/null || echo "000")
  if [ "$code" = "200" ]; then
    ok "OneAPI 连接正常 ($ONEAPI_URL)"
    return 0
  else
    fail "OneAPI 不可达 (HTTP $code)"
    exit 1
  fi
}

# =============================================
# 命令：sync-models — 同步模型列表
# =============================================
# 从渠道配置的 models 字段读取，自动补全 abilities 表映射
# 用法：bash scripts/ops-channel-mgmt.sh sync-models [--dry-run]
sync_models() {
  local dry_run=false
  [[ "${1:-}" == "--dry-run" ]] && dry_run=true

  step "同步渠道 → 模型映射（abilities 表）"

  # 获取所有渠道
  local channels
  channels=$(api "GET" "/api/channel/?p=0&page_size=200")
  if [ -z "$channels" ]; then
    fail "获取渠道列表失败"
    return 1
  fi

  # 获取已有 abilities 映射
  local existing_abl
  existing_abl=$(curl -s -X GET "$ONEAPI_URL/api/channel/ability/?p=0&page_size=500" \
    -H "Authorization: Bearer $ADMIN_TOKEN" 2>/dev/null)
  local existing_map
  existing_map=$(echo "$existing_abl" | jq -r '.data[]? | "\(.channel_id):\(.model)"' 2>/dev/null || echo "")

  local added=0 skipped=0

  # 遍历渠道
  local channel_count
  channel_count=$(echo "$channels" | jq '.data | length' 2>/dev/null || echo "0")

  for ((i=0; i<channel_count; i++)); do
    local channel
    channel=$(echo "$channels" | jq -c ".data[$i]")
    local ch_id ch_name ch_models
    ch_id=$(echo "$channel" | jq -r '.id')
    ch_name=$(echo "$channel" | jq -r '.name')
    ch_models=$(echo "$channel" | jq -r '.models // ""')

    if [ -z "$ch_models" ]; then
      warn "渠道 $ch_name (ID=$ch_id) 未配置模型列表，跳过"
      continue
    fi

    info "渠道 $ch_name (ID=$ch_id): models=$ch_models"

    # 解析逗号分隔的模型列表
    IFS=',' read -ra models_arr <<< "$ch_models"
    for model in "${models_arr[@]}"; do
      model=$(echo "$model" | xargs)  # trim
      if echo "$existing_map" | grep -q "^${ch_id}:${model}$"; then
        skipped=$((skipped + 1))
        continue
      fi

      if [ "$dry_run" = true ]; then
        info "  [DRY-RUN] 将添加 ability: model=$model → channel=$ch_id"
        added=$((added + 1))
        continue
      fi

      # 创建 ability 映射
      local payload
      payload=$(jq -n --arg group "default" --arg model "$model" --argjson ch_id "$ch_id" '{
        group: $group,
        model: $model,
        channel_id: $ch_id,
        enabled: true,
        priority: 0
      }')

      local resp
      resp=$(api "POST" "/api/channel/ability/" "$payload")
      local success
      success=$(echo "$resp" | jq -r '.success // false' 2>/dev/null)

      if [ "$success" = "true" ]; then
        ok "  Added: $model → channel $ch_id"
        added=$((added + 1))
      else
        local msg
        msg=$(echo "$resp" | jq -r '.message // "unknown"' 2>/dev/null)
        fail "  Failed: $model → channel $ch_id: $msg"
      fi
      sleep 0.3
    done
  done

  echo ""
  info "同步完成：新增 $added 个映射，已存在 $skipped 个"
}

# =============================================
# 命令：add-provider — 接入新 provider
# =============================================
# 交互式引导：输入 provider 信息 → 创建渠道 → 同步 abilities
# 用法：bash scripts/ops-channel-mgmt.sh add-provider
add_provider() {
  step "接入新 Provider"

  echo ""
  echo "  请提供以下信息（按 Ctrl+C 取消）："
  echo ""

  # 收集输入
  read -r -p "  渠道名称（如 Qwen-1）：" name
  read -r -p "  API Key：" key
  read -r -p "  Base URL（如 https://dashscope.aliyuncs.com/compatible-mode/v1）：" base_url
  read -r -p "  模型列表（逗号分隔，如 qwen-turbo,qwen-plus）：" models
  read -r -p "  权重（默认 1）：" weight
  weight="${weight:-1}"
  read -r -p "  渠道类型（1=OpenAI, 3=Custom，默认 1）：" ctype
  ctype="${ctype:-1}"

  echo ""
  echo "  ═══════════════════════════════════════════"
  echo "  确认信息："
  echo "  ═══════════════════════════════════════════"
  echo "  名称：$name"
  echo "  Key ：${key:0:8}****"
  echo "  URL ：$base_url"
  echo "  模型：$models"
  echo "  权重：$weight"
  echo "  类型：$ctype"
  echo "  ═══════════════════════════════════════════"
  read -r -p "  确认创建？(y/n)：" confirm

  if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    warn "已取消"
    return 0
  fi

  # 构建 payload
  local payload
  payload=$(jq -n \
    --argjson type "$ctype" \
    --arg name "$name" \
    --arg key "$key" \
    --arg base_url "$base_url" \
    --arg models "$models" \
    --argjson weight "$weight" \
    '{
      type: $type,
      name: $name,
      key: $key,
      base_url: $base_url,
      models: $models,
      model_mapping: "",
      groups: ["default"],
      status: 1,
      priority: 1,
      weight: $weight
    }')

  info "正在创建渠道..."
  local resp
  resp=$(api "POST" "/api/channel/" "$payload")

  local success
  success=$(echo "$resp" | jq -r '.success // false' 2>/dev/null)

  if [ "$success" != "true" ]; then
    local msg
    msg=$(echo "$resp" | jq -r '.message // "unknown"' 2>/dev/null)
    fail "创建渠道失败: $msg"
    return 1
  fi

  local new_id
  new_id=$(echo "$resp" | jq -r '.data.id')
  ok "渠道「$name」创建成功 (ID=$new_id)"

  # 测试渠道连通性
  info "测试渠道连通性..."
  sleep 2
  local test_resp
  test_resp=$(api "GET" "/api/channel/test/$new_id")
  local test_ok
  test_ok=$(echo "$test_resp" | jq -r '.success // false' 2>/dev/null)
  if [ "$test_ok" = "true" ]; then
    ok "渠道测试通过"
  else
    warn "渠道测试返回异常（可能需要等待几秒同步，手动在后台检查）"
  fi

  # 同步 abilities
  IFS=',' read -ra models_arr <<< "$models"
  for model in "${models_arr[@]}"; do
    model=$(echo "$model" | xargs)
    local ab_payload
    ab_payload=$(jq -n --arg group "default" --arg model "$model" --argjson ch_id "$new_id" '{
      group: $group,
      model: $model,
      channel_id: $ch_id,
      enabled: true,
      priority: 0
    }')
    api "POST" "/api/channel/ability/" "$ab_payload" > /dev/null 2>&1
    ok "  Ability: $model → channel $new_id"
    sleep 0.3
  done

  echo ""
  ok "Provider「$name」接入完成！"
  echo ""
  echo "  后续步骤："
  echo "  1. 在 OneAPI 后台「渠道管理」验证状态"
  echo "  2. 更新 backend: projects/ai-api-agg/backend/internal/config/config.go"
  echo "     在 ModelMapping 中添加新模型"
  echo "  3. 重新部署 backend 生效"
}

# =============================================
# 命令：create-token — 创建用户令牌
# =============================================
# 用法：bash scripts/ops-channel-mgmt.sh create-token <名称> <配额> [--unlimited]
create_token() {
  local name="${1:-}" quota="${2:-0}" unlimited=false
  for arg in "$@"; do [[ "$arg" == "--unlimited" ]] && unlimited=true; done

  step "创建令牌"

  if [ -z "$name" ] || [ "$quota" -le 0 ] && [ "$unlimited" != true ]; then
    echo "用法：bash scripts/ops-channel-mgmt.sh create-token <名称> <配额> [--unlimited]"
    echo ""
    echo "示例："
    echo "  # 创建 10K 配额的用户令牌"
    echo "  bash scripts/ops-channel-mgmt.sh create-token user-token 10000"
    echo ""
    echo "  # 创建无限配额的系统令牌（仅内部使用）"
    echo "  bash scripts/ops-channel-mgmt.sh create-token system-api --unlimited"
    exit 1
  fi

  local payload
  if [ "$unlimited" = true ]; then
    quota=999999999
    payload=$(jq -n --arg name "$name" --argjson quota "$quota" '{
      name: $name,
      remain_quota: $quota,
      unlimited_quota: true
    }')
  else
    payload=$(jq -n --arg name "$name" --argjson quota "$quota" '{
      name: $name,
      remain_quota: $quota,
      unlimited_quota: false
    }')
  fi

  local resp
  resp=$(api "POST" "/api/token/" "$payload")
  local success
  success=$(echo "$resp" | jq -r '.success // false' 2>/dev/null)

  if [ "$success" = "true" ]; then
    local token_key token_id
    token_key=$(echo "$resp" | jq -r '.data.key // "N/A"')
    token_id=$(echo "$resp" | jq -r '.data.id')
    ok "令牌创建成功"
    echo ""
    echo "  ID:   $token_id"
    echo "  名称: $name"
    echo "  Key:  $token_key"
    echo "  配额: $( [ "$unlimited" = true ] && echo '无限' || echo "$quota" )"
    echo ""
    echo "  ⚠️ 请妥善保存 Key，创建后仅显示一次！"
    echo "  测试调用："
    echo "  curl $ONEAPI_URL/v1/chat/completions \\"
    echo "    -H 'Authorization: Bearer $token_key' \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"model\":\"deepseek-v4-flash\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}'"
  else
    local msg
    msg=$(echo "$resp" | jq -r '.message // "unknown"' 2>/dev/null)
    fail "创建令牌失败: $msg"
  fi
}

# =============================================
# 命令：health — 渠道健康检查
# =============================================
health() {
  step "渠道健康检查"

  local channels
  channels=$(api "GET" "/api/channel/?p=0&page_size=200")
  local total
  total=$(echo "$channels" | jq '.data | length' 2>/dev/null || echo "0")

  local ok_count=0 fail_count=0

  printf "\n  %-4s %-20s %-8s %s\n" "ID" "名称" "状态" "延迟"
  printf "  %-4s %-20s %-8s %s\n" "──" "──────────────────" "──────" "──────"

  for ((i=0; i<total; i++)); do
    local ch
    ch=$(echo "$channels" | jq -c ".data[$i]")
    local ch_id ch_name
    ch_id=$(echo "$ch" | jq -r '.id')
    ch_name=$(echo "$ch" | jq -r '.name')

    local test_resp
    test_resp=$(api "GET" "/api/channel/test/$ch_id" 2>/dev/null || echo '{}')
    local test_ok latency
    test_ok=$(echo "$test_resp" | jq -r '.success // false' 2>/dev/null)
    latency=$(echo "$test_resp" | jq -r '.data // "N/A"' 2>/dev/null)

    if [ "$test_ok" = "true" ]; then
      printf "  %-4s %-20s %-8s %s\n" "$ch_id" "$ch_name" "${GREEN}✅ OK${NC}" "${latency}ms"
      ok_count=$((ok_count + 1))
    else
      printf "  %-4s %-20s %-8s %s\n" "$ch_id" "$ch_name" "${RED}❌ FAIL${NC}" "-"
      fail_count=$((fail_count + 1))
    fi
    sleep 0.5
  done

  echo ""
  info "健康检查完成：通过 $ok_count，失败 $fail_count"
  [ "$fail_count" -gt 0 ] && warn "有渠道异常，请登录 OneAPI 后台排查"
}

# =============================================
# 命令：list-tokens — 列出所有令牌
# =============================================
list_tokens() {
  step "令牌列表"

  local tokens
  tokens=$(api "GET" "/api/token/?p=0&page_size=100")
  local total
  total=$(echo "$tokens" | jq '.data | length' 2>/dev/null || echo "0")

  printf "\n  %-4s %-20s %-12s %-8s\n" "ID" "名称" "剩余配额" "状态"
  printf "  %-4s %-20s %-12s %-8s\n" "──" "──────────────────" "──────────" "──────"

  for ((i=0; i<total; i++)); do
    local t
    t=$(echo "$tokens" | jq -c ".data[$i]")
    local tid tname trem tstat unlimited
    tid=$(echo "$t" | jq -r '.id')
    tname=$(echo "$t" | jq -r '.name')
    trem=$(echo "$t" | jq -r '.remain_quota')
    tstat=$(echo "$t" | jq -r '.status')
    unlimited=$(echo "$t" | jq -r '.unlimited_quota // false')

    local display_quota
    if [ "$unlimited" = "true" ]; then
      display_quota="无限"
    else
      display_quota=$(printf "%'d" "$trem" 2>/dev/null || echo "$trem")
    fi

    local status_icon
    [ "$tstat" = "1" ] && status_icon="${GREEN}启用${NC}" || status_icon="${RED}停用${NC}"

    printf "  %-4s %-20s %-12s %b\n" "$tid" "$tname" "$display_quota" "$status_icon"
  done
  echo ""
}

# =============================================
# 命令：set-token-quota — 修改令牌配额
# =============================================
# 用法：bash scripts/ops-channel-mgmt.sh set-token-quota <token_name> <new_quota>
set_token_quota() {
  local name="${1:-}" new_quota="${2:-}"

  if [ -z "$name" ] || [ -z "$new_quota" ]; then
    echo "用法：bash scripts/ops-channel-mgmt.sh set-token-quota <令牌名称> <新配额>"
    echo ""
    echo "示例："
    echo "  bash scripts/ops-channel-mgmt.sh set-token-quota user-token 50000"
    exit 1
  fi

  step "修改令牌配额"

  # 查找令牌
  local tokens
  tokens=$(api "GET" "/api/token/?p=0&page_size=100")
  local token
  token=$(echo "$tokens" | jq -c --arg name "$name" '.data[]? | select(.name == $name)')
  if [ -z "$token" ] || [ "$token" = "null" ]; then
    fail "未找到令牌: $name"
    return 1
  fi

  local tid
  tid=$(echo "$token" | jq -r '.id')

  local payload
  payload=$(jq -n --argjson quota "$new_quota" --argjson unlimited false '{
    remain_quota: $quota,
    unlimited_quota: $unlimited
  }')

  local resp
  resp=$(api "PUT" "/api/token/$tid" "$payload")
  local success
  success=$(echo "$resp" | jq -r '.success // false' 2>/dev/null)

  if [ "$success" = "true" ]; then
    ok "令牌「$name」配额已更新为 $new_quota"
  else
    local msg
    msg=$(echo "$resp" | jq -r '.message // "unknown"' 2>/dev/null)
    fail "更新失败: $msg"
  fi
}

# =============================================
# 主入口
# =============================================
main() {
  load_env

  local cmd="${1:-}"
  shift || true

  echo ""
  echo "╔══════════════════════════════════════════════╗"
  echo "║   AI API 聚合 — 日常渠道/模型维护工具          ║"
  echo "╚══════════════════════════════════════════════╝"

  case "$cmd" in
    sync-models)
      check_connection
      sync_models "$@"
      ;;
    add-provider)
      check_connection
      add_provider "$@"
      ;;
    create-token)
      check_connection
      create_token "$@"
      ;;
    health)
      check_connection
      health
      ;;
    list-tokens)
      check_connection
      list_tokens
      ;;
    set-token-quota)
      check_connection
      set_token_quota "$@"
      ;;
    *)
      echo ""
      echo "用法：bash scripts/ops-channel-mgmt.sh <命令> [参数]"
      echo ""
      echo "命令："
      echo "  sync-models             同步所有渠道→模型映射（abilities 表）"
      echo "  add-provider            交互式接入新 provider（如 Qwen）"
      echo "  create-token <名> <配额> 创建令牌"
      echo "  set-token-quota <名> <额> 修改令牌配额"
      echo "  list-tokens             列出所有令牌"
      echo "  health                  渠道健康检查"
      echo ""
      echo "示例："
      echo "  bash scripts/ops-channel-mgmt.sh sync-models"
      echo "  bash scripts/ops-channel-mgmt.sh add-provider"
      echo "  bash scripts/ops-channel-mgmt.sh create-token my-token 10000"
      echo "  bash scripts/ops-channel-mgmt.sh create-token system-api --unlimited"
      echo "  bash scripts/ops-channel-mgmt.sh set-token-quota my-token 50000"
      ;;
  esac
}

main "$@"
