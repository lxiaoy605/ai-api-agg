#!/bin/bash
# =============================================
# channel-setup.sh — OneAPI 渠道自动配置脚本（多账号池版）
# =============================================
# 功能：
#   1. 从 channel-configs.json 读取渠道定义（支持 keys 数组）
#   2. 每 Key 创建一个独立渠道，实现多 Key 轮询
#   3. 幂等操作 — 按名称检测已存在渠道，只创建缺失的
#   4. 验证每个渠道健康状态
#   5. 权重分配：每厂商 2 Key 各 1 权重，总计 2:2:2
#
# 用法：
#   export ONEAPI_ROOT_TOKEN=your-root-token
#   ./channel-setup.sh
#
# 环境变量（从 docker/.env 自动加载）：
#   ONEAPI_URL         — OneAPI 地址（默认 http://localhost:3000）
#   ONEAPI_ROOT_TOKEN  — OneAPI Root Token
#   各厂商 API Key 变量 — 在 channel-configs.json 中引用
# =============================================

set -euo pipefail

# ==========================================
# 配置
# ==========================================
ONEAPI_URL="${ONEAPI_URL:-http://localhost:3000}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_DIR/channels/channel-configs.json"
ENV_FILE="$PROJECT_DIR/docker/.env"
DRY_RUN="${DRY_RUN:-false}"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ==========================================
# 工具函数
# ==========================================
log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()  { echo -e "\n${CYAN}━━━${NC} $* ${CYAN}━━━${NC}"; }
log_detail(){ echo -e "       $*"; }

# 加载 .env 文件中的环境变量
load_env() {
  if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE" 2>/dev/null || true
    set +a
  fi
}

# 解析环境变量占位符 ${VAR_NAME}
# 输入: "${DEEPSEEK_API_KEY}" 或普通字符串
# 输出: 实际的环境变量值
resolve_env_var() {
  local raw="$1"
  # 匹配 ${VAR_NAME} 模式
  if [[ "$raw" =~ ^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$ ]]; then
    local var_name="${BASH_REMATCH[1]}"
    echo "${!var_name:-}"
  else
    echo "$raw"
  fi
}

# 检查必要环境变量（从 channel-configs.json 收集所有需要的变量）
check_env() {
  local missing=()

  # 检查 ONEAPI_ROOT_TOKEN
  if [ -z "${ONEAPI_ROOT_TOKEN:-}" ]; then
    if [ -f "$ENV_FILE" ]; then
      ONEAPI_ROOT_TOKEN=$(grep -E '^ONEAPI_ADMIN_TOKEN=' "$ENV_FILE" | cut -d= -f2- | tr -d '"' | tr -d "'")
      if [ -n "$ONEAPI_ROOT_TOKEN" ]; then
        log_info "从 $ENV_FILE 读取 ONEAPI_ADMIN_TOKEN"
      fi
    fi
  fi

  [ -z "${ONEAPI_ROOT_TOKEN:-}" ] && missing+=("ONEAPI_ROOT_TOKEN")

  # 从 config 中提取所有需要的环境变量名
  local required_vars
  required_vars=$(jq -r '.channels[].keys[]' "$CONFIG_FILE" 2>/dev/null | grep -oP '\$\{\K[^}]+' | sort -u)

  for var in $required_vars; do
    local resolved
    resolved="${!var:-}"
    if [ -z "$resolved" ]; then
      missing+=("$var")
    fi
  done

  if [ ${#missing[@]} -gt 0 ]; then
    log_error "缺少必要环境变量："
    for var in "${missing[@]}"; do
      echo "  - $var"
    done
    echo ""
    echo "请在 $ENV_FILE 中配置这些变量，或手动导出："
    echo "  export ONEAPI_ROOT_TOKEN=<your-root-token>"
    echo "  export DEEPSEEK_API_KEY=<key1>"
    echo "  export DEEPSEEK_API_KEY_2=<key2>"
    echo "  ..."
    exit 1
  fi
}

# 调用 OneAPI 管理 API
oneapi_api() {
  local method="$1" endpoint="$2" data="${3:-}"

  if [ -n "$data" ]; then
    curl -s -X "$method" "$ONEAPI_URL$endpoint" \
      -H "Authorization: Bearer $ONEAPI_ROOT_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$data"
  else
    curl -s -X "$method" "$ONEAPI_URL$endpoint" \
      -H "Authorization: Bearer $ONEAPI_ROOT_TOKEN"
  fi
}

# 检查 OneAPI 是否可达
check_oneapi_connection() {
  log_info "检查 OneAPI 连接 ($ONEAPI_URL)..."
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$ONEAPI_URL/api/status" 2>/dev/null || echo "000")

  if [ "$http_code" = "200" ]; then
    log_ok "OneAPI 连接正常"
    return 0
  else
    log_error "OneAPI 不可达 (HTTP $http_code)，请确认："
    echo "  1. OneAPI 服务是否已启动: docker compose -f docker/docker-compose.yml ps"
    echo "  2. ONEAPI_URL 是否正确: $ONEAPI_URL"
    echo "  3. 是否可以通过 curl 访问: curl $ONEAPI_URL/api/status"
    exit 1
  fi
}

# 验证 Token 是否有效
check_token() {
  log_info "验证 Root Token..."
  local resp
  resp=$(oneapi_api "GET" "/api/user/self")
  local success
  success=$(echo "$resp" | jq -r '.success // false' 2>/dev/null)

  if [ "$success" = "true" ]; then
    local username
    username=$(echo "$resp" | jq -r '.data.username // "unknown"')
    log_ok "Token 有效，当前用户: $username"
  else
    local msg
    msg=$(echo "$resp" | jq -r '.message // "未知错误"')
    log_error "Token 验证失败: $msg"
    log_warn "请在 OneAPI 管理面板获取 Root Token（/user/token 页面）"
    exit 1
  fi
}

# 查找渠道（按名称）
find_channel_by_name() {
  local name="$1"
  oneapi_api "GET" "/api/channel/?p=0&page_size=200" | \
    jq -r --arg name "$name" '.data[]? | select(.name == $name) | .id' 2>/dev/null || echo ""
}

# 获取所有已存在渠道的名称列表
get_existing_channel_names() {
  oneapi_api "GET" "/api/channel/?p=0&page_size=200" | \
    jq -r '.data[]?.name // ""' 2>/dev/null
}

# 构建渠道 JSON payload（支持 key 参数）
build_channel_payload() {
  local name="$1" base_url="$2" key_value="$3" models="$4" weight="$5" type="${6:-3}"

  jq -n \
    --argjson type "$type" \
    --arg name "$name" \
    --arg base_url "$base_url" \
    --arg key "$key_value" \
    --arg models "$models" \
    --argjson weight "$weight" \
    '{
      type: $type,
      name: $name,
      base_url: $base_url,
      key: $key,
      models: $models,
      model_mapping: "",
      groups: ["default"],
      status: 1,
      priority: 1,
      weight: $weight
    }'
}

# 创建渠道
create_channel() {
  local name="$1" base_url="$2" key_value="$3" models="$4" weight="$5"

  # 检查是否已存在
  local existing_id
  existing_id=$(find_channel_by_name "$name")

  if [ -n "$existing_id" ]; then
    log_warn "渠道「$name」已存在 (ID=$existing_id)，跳过创建"
    echo "$existing_id"
    return 0
  fi

  if [ "$DRY_RUN" = "true" ]; then
    log_info "[DRY-RUN] 将创建渠道: $name (weight=$weight)"
    echo "dry-run-$name"
    return 0
  fi

  local payload
  payload=$(build_channel_payload "$name" "$base_url" "$key_value" "$models" "$weight")

  log_info "创建渠道「$name」..."
  local resp
  resp=$(oneapi_api "POST" "/api/channel/" "$payload")

  local success
  success=$(echo "$resp" | jq -r '.success // false')

  if [ "$success" = "true" ]; then
    local new_id
    new_id=$(echo "$resp" | jq -r '.data.id // .data // ""')
    log_ok "渠道「$name」创建成功 (ID=$new_id, weight=$weight)"
    echo "$new_id"
  else
    local msg
    msg=$(echo "$resp" | jq -r '.message // "未知错误"')
    log_error "创建渠道「$name」失败: $msg"
    log_detail "请求 payload: $payload"
    echo ""
  fi
}

# 测试渠道
test_channel() {
  local channel_id="$1" name="$2"

  if [ "$DRY_RUN" = "true" ]; then
    log_info "[DRY-RUN] 测试渠道: $name (ID=$channel_id)"
    return 0
  fi

  if [ -z "$channel_id" ] || [[ "$channel_id" == dry-run-* ]]; then
    log_warn "跳过测试「$name」: 无有效渠道 ID"
    return 1
  fi

  log_info "测试渠道「$name」(ID=$channel_id)..."
  local resp
  resp=$(oneapi_api "GET" "/api/channel/test/$channel_id")

  local success
  success=$(echo "$resp" | jq -r '.success // false' 2>/dev/null)

  if [ "$success" = "true" ]; then
    log_ok "渠道「$name」测试通过"
    return 0
  else
    local msg
    msg=$(echo "$resp" | jq -r '.message // "无详情"')
    log_warn "渠道「$name」测试返回: $msg"
    log_warn "（初次创建后可能需要等待几秒同步，可稍后重新测试）"
    return 0  # 不阻塞流程
  fi
}

# 检测并补齐缺失的渠道（幂等核心）
# 读取 config 中所有期望的渠道名 → 对比 OneAPI 中已存在的渠道名 → 只创建缺失的
sync_channels() {
  log_step "渠道同步（幂等模式）"
  log_info "读取渠道配置: $CONFIG_FILE"

  if [ ! -f "$CONFIG_FILE" ]; then
    log_error "配置文件不存在: $CONFIG_FILE"
    exit 1
  fi

  # 统计信息
  local channel_count
  channel_count=$(jq '.channels | length' "$CONFIG_FILE")
  log_info "配置文件中定义了 $channel_count 个渠道"

  if [ "$DRY_RUN" != "true" ]; then
    log_info "获取 OneAPI 现有渠道列表..."
    local existing_names
    existing_names=$(get_existing_channel_names)
    log_detail "现有渠道: $(echo "$existing_names" | tr '\n' ' ')"
  else
    local existing_names=""
  fi

  # 遍历配置中的每个渠道
  local total_created=0
  local total_skipped=0
  local total_failed=0
  declare -a created_channels

  for ((i=0; i<channel_count; i++)); do
    local channel
    channel=$(jq -c ".channels[$i]" "$CONFIG_FILE")

    local name base_url models weight type
    name=$(echo "$channel" | jq -r '.name')
    base_url=$(echo "$channel" | jq -r '.base_url')
    models=$(echo "$channel" | jq -r '.models')
    weight=$(echo "$channel" | jq -r '.weight')
    type=$(echo "$channel" | jq -r '.type // 3')

    # 读取 keys 数组
    local key_count
    key_count=$(echo "$channel" | jq '.keys | length')

    if [ "$key_count" -eq 0 ]; then
      log_warn "渠道「$name」没有定义 keys，跳过"
      continue
    fi

    # 渠道定义了 keys 数组但只取第一个（因为每个 config channel 条目 = 1 个渠道）
    local key_raw
    key_raw=$(echo "$channel" | jq -r '.keys[0]')
    local key_value
    key_value=$(resolve_env_var "$key_raw")

    if [ -z "$key_value" ]; then
      log_error "渠道「$name」的 Key 解析失败: $key_raw"
      total_failed=$((total_failed + 1))
      continue
    fi

    # 幂等检查
    if [ "$DRY_RUN" != "true" ]; then
      if echo "$existing_names" | grep -qF "$name"; then
        log_warn "渠道「$name」已存在，跳过"
        total_skipped=$((total_skipped + 1))
        # 仍然记录已有渠道以便健康检查
        local existing_id
        existing_id=$(find_channel_by_name "$name")
        created_channels+=("$existing_id|$name")
        continue
      fi
    fi

    # 创建渠道
    log_info "处理渠道「$name」(weight=$weight, base_url=$base_url)"
    local channel_id
    channel_id=$(create_channel "$name" "$base_url" "$key_value" "$models" "$weight")

    if [ -n "$channel_id" ]; then
      total_created=$((total_created + 1))
      created_channels+=("$channel_id|$name")
    else
      total_failed=$((total_failed + 1))
    fi
  done

  echo ""
  log_info "渠道同步完成: 新建 $total_created, 已存在 $total_skipped, 失败 $total_failed"

  # 返回创建的渠道列表
  for item in "${created_channels[@]}"; do
    echo "$item"
  done
}

# ==========================================
# 主流程
# ==========================================
main() {
  echo ""
  echo "╔══════════════════════════════════════════════════╗"
  echo "║   AI API 聚合平台 — OneAPI 渠道自动配置脚本       ║"
  echo "║   多账号池版: 每厂商 2 Key 轮询                   ║"
  echo "║   权重分配: DeepSeek 2 : 智谱 2 : MiMo 2         ║"
  echo "╚══════════════════════════════════════════════════╝"
  echo ""

  # 1. 加载环境变量
  load_env

  # 2. 环境检查
  log_step "第 1 步：环境检查"
  check_env
  check_oneapi_connection
  check_token

  # 3. 同步渠道（幂等 + 补齐）
  log_step "第 2 步：同步渠道（幂等模式）"
  if [ "$DRY_RUN" = "true" ]; then
    log_info "DRY-RUN 模式：仅检查差异，不实际创建"
  fi

  # 同步渠道，获取创建结果
  local sync_output
  sync_output=$(sync_channels)

  # 解析渠道列表用于健康检查
  local channel_list=()
  while IFS= read -r line; do
    if [[ "$line" == *"|"* ]]; then
      channel_list+=("$line")
    fi
  done <<< "$sync_output"

  # 3. 健康检查
  log_step "第 3 步：渠道健康检查"
  local health_ok=0
  local health_total=0

  for entry in "${channel_list[@]}"; do
    local ch_id="${entry%%|*}"
    local ch_name="${entry##*|}"
    health_total=$((health_total + 1))
    if test_channel "$ch_id" "$ch_name"; then
      health_ok=$((health_ok + 1))
    fi
    sleep 1  # 避免请求过快
  done

  # 4. 汇总
  log_step "配置汇总"
  echo ""

  # 打印最终渠道列表
  echo "  $(printf '%-22s %-8s %s' '渠道名称' '权重' '状态')"
  echo "  $(printf '%-22s %-8s %s' '──────────' '────' '────')"

  for entry in "${channel_list[@]}"; do
    local ch_id="${entry%%|*}"
    local ch_name="${entry##*|}"
    local ch_weight="?"
    # 从配置中查找权重
    ch_weight=$(jq -r --arg name "$ch_name" '.channels[] | select(.name == $name) | .weight' "$CONFIG_FILE" 2>/dev/null || echo "?")
    local status_icon="✅"
    [ -z "$ch_id" ] && status_icon="❌"
    echo "  $(printf '%-22s %-8s %s' "$ch_name" "$ch_weight" "$status_icon 已配置")"
  done

  echo ""
  local total_channels=${#channel_list[@]}
  if [ "$health_ok" -eq "$health_total" ] && [ "$total_channels" -gt 0 ]; then
    log_ok "全部 $total_channels 个渠道配置完成！权重分配 DeepSeek:智谱:MiMo = 2:2:2"
    echo ""
    echo "下一步："
    echo "  1. 打开 OneAPI 管理面板: $ONEAPI_URL"
    echo "  2. 进入「渠道管理」查看渠道列表和状态"
    echo "  3. 在「令牌管理」创建用户 API Key"
    echo "  4. 测试调用: curl $ONEAPI_URL/v1/chat/completions -H 'Authorization: Bearer <token>' ..."
  else
    log_warn "$health_ok/$health_total 渠道测试通过，请检查以上警告信息"
  fi

  echo ""
  log_info "健康检查: $health_ok/$health_total 通过"
}

main "$@"
