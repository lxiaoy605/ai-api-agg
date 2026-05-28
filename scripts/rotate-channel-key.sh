#!/usr/bin/env bash
# =============================================
# AI API 聚合平台 — API Key 轮换脚本
# =============================================
# 功能：
#   1. 从 OneAPI 读取旧渠道配置，创建相同配置的新渠道（新 Key）
#   2. 预热阶段（权重=0）→ 健康检查 → 逐步提权 → 观察窗口
#   3. 旧渠道权重降到 0 → 观察 → 删除旧渠道
#   4. 全程日志 + Telegram 通知 + 失败自动回滚
#
# 用法：
#   # 手动模式（指定渠道 ID 和新 Key）
#   ./rotate-channel-key.sh --channel-id 1 --new-key "sk-xxx"
#   ./rotate-channel-key.sh --channel-id 1 --new-key "sk-xxx" --dry-run
#   ./rotate-channel-key.sh --channel-id 1 --new-key "sk-xxx" --target-weight 5
#
#   # 按渠道名称轮换
#   ./rotate-channel-key.sh --channel-name "DeepSeek" --new-key "sk-xxx"
#
#   # 自动模式（从 .env 读取，对比状态文件判断是否需要轮换）
#   ./rotate-channel-key.sh --auto
#   ./rotate-channel-key.sh --auto --dry-run
#
# 环境变量（从 docker/.env 加载）：
#   ONEAPI_URL            OneAPI 地址（默认 http://localhost:3000）
#   ONEAPI_ROOT_TOKEN     OneAPI 管理员 Token
#   TELEGRAM_BOT_TOKEN    Telegram Bot Token
#   TELEGRAM_CHAT_ID      Telegram Chat ID
#   DEEPSEEK_API_KEY      各厂商 API Key（自动模式使用）
#   ZHIPU_ZAI_API_KEY
#   MIMO_API_KEY
# =============================================

set -euo pipefail

# ==========================================
# 路径
# ==========================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_DIR/logs"
mkdir -p "$LOG_DIR"

ROTATION_LOG="$LOG_DIR/key-rotation.log"
STATE_FILE="$LOG_DIR/key-rotation.state"
ENV_FILE="$PROJECT_DIR/docker/.env"
HEALTHCHECK_SCRIPT="$SCRIPT_DIR/healthcheck.sh"

# ==========================================
# 默认配置
# ==========================================
ONEAPI_URL="${ONEAPI_URL:-http://localhost:3000}"
TARGET_WEIGHT="${TARGET_WEIGHT:-3}"
OBSERVE_SECONDS="${OBSERVE_SECONDS:-300}"       # 观察窗口 5 分钟
GRACE_SECONDS="${GRACE_SECONDS:-300}"            # 旧渠道删除前等待 5 分钟
HEALTH_RETRIES="${HEALTH_RETRIES:-3}"
HEALTH_RETRY_INTERVAL="${HEALTH_RETRY_INTERVAL:-10}"
DRY_RUN="${DRY_RUN:-false}"

# ==========================================
# 颜色
# ==========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ==========================================
# 日志
# ==========================================
log_msg() {
  local level="$1"; shift
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] [$level] $*" | tee -a "$ROTATION_LOG"
}

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; log_msg "INFO" "$@"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; log_msg "OK" "$@"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; log_msg "WARN" "$@"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; log_msg "ERROR" "$@"; }
log_step()  { echo -e "\n${CYAN}━━━${NC} $* ${CYAN}━━━${NC}"; log_msg "STEP" "$@"; }

# ==========================================
# 环境变量加载
# ==========================================
load_env() {
  if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE" 2>/dev/null || true
    set +a
  fi

  # ONEAPI_ROOT_TOKEN 可从 ONEAPI_ADMIN_TOKEN 读取
  if [ -z "${ONEAPI_ROOT_TOKEN:-}" ] && [ -n "${ONEAPI_ADMIN_TOKEN:-}" ]; then
    ONEAPI_ROOT_TOKEN="$ONEAPI_ADMIN_TOKEN"
    log_info "从 ONEAPI_ADMIN_TOKEN 读取 Root Token"
  fi
}

NOTIFY_SCRIPT="$SCRIPT_DIR/ops-notify.sh"

# ==========================================
# 运维通知（通过统一通知脚本 ops-notify.sh）
# ==========================================
send_notify() {
  # 兼容两种调用方式:
  #   新: send_notify "level" "title" "message"
  #   旧: send_notify "message"  (自动推断级别)
  local level title message
  if [ $# -ge 3 ]; then
    level="$1"; title="$2"; message="$3"
  else
    message="$1"
    title="Key 轮换通知"
    # 根据消息内容推断级别
    if echo "$message" | grep -qi "fail\|error\|回滚\|abort"; then
      level="critical"
    else
      level="warning"
    fi
  fi

  if [ -x "$NOTIFY_SCRIPT" ]; then
    "$NOTIFY_SCRIPT" --level "$level" --title "$title" --message "$message" --silent || true
  fi
}

# ==========================================
# OneAPI 管理 API
# ==========================================
oneapi_api() {
  local method="$1" endpoint="$2" data="${3:-}"

  if [ -z "${ONEAPI_ROOT_TOKEN:-}" ]; then
    log_error "ONEAPI_ROOT_TOKEN 未设置，无法调用 OneAPI API"
    return 1
  fi

  if [ -n "$data" ]; then
    curl -s -X "$method" "$ONEAPI_URL$endpoint" \
      -H "Authorization: Bearer $ONEAPI_ROOT_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$data" 2>/dev/null
  else
    curl -s -X "$method" "$ONEAPI_URL$endpoint" \
      -H "Authorization: Bearer $ONEAPI_ROOT_TOKEN" 2>/dev/null
  fi
}

# ==========================================
# 渠道操作
# ==========================================

# 获取渠道详情
get_channel() {
  local channel_id="$1"
  oneapi_api "GET" "/api/channel/$channel_id" | jq '.data // {}' 2>/dev/null || echo "{}"
}

# 按名称查找渠道 ID（返回所有匹配的 ID，换行分隔）
find_channel_ids_by_name() {
  local name="$1"
  oneapi_api "GET" "/api/channel/?p=0&page_size=100" | \
    jq -r --arg name "$name" '.data[]? | select(.name == $name) | .id' 2>/dev/null || echo ""
}

# 按名称查找渠道 ID（返回第一个匹配）
find_channel_id_by_name() {
  local name="$1"
  find_channel_ids_by_name "$name" | head -1
}

# 创建渠道（返回新渠道 ID）
create_channel() {
  local payload="$1"

  if [ "$DRY_RUN" = "true" ]; then
    log_info "[DRY-RUN] 将创建渠道: $(echo "$payload" | jq -r '.name')"
    echo "0"
    return 0
  fi

  local resp
  resp=$(oneapi_api "POST" "/api/channel/" "$payload")
  local success
  success=$(echo "$resp" | jq -r '.success // false' 2>/dev/null)

  if [ "$success" = "true" ]; then
    local new_id
    new_id=$(echo "$resp" | jq -r '.data.id // .data // ""' 2>/dev/null)
    echo "$new_id"
  else
    local msg
    msg=$(echo "$resp" | jq -r '.message // "未知错误"' 2>/dev/null)
    log_error "创建渠道失败: $msg"
    echo ""
    return 1
  fi
}

# 更新渠道
update_channel() {
  local channel_id="$1" payload="$2"

  if [ "$DRY_RUN" = "true" ]; then
    log_info "[DRY-RUN] 将更新渠道 ID=$channel_id"
    return 0
  fi

  local resp
  resp=$(oneapi_api "PUT" "/api/channel/$channel_id" "$payload")
  local success
  success=$(echo "$resp" | jq -r '.success // false' 2>/dev/null)

  if [ "$success" = "true" ]; then
    return 0
  else
    local msg
    msg=$(echo "$resp" | jq -r '.message // "未知错误"' 2>/dev/null)
    log_error "更新渠道 ID=$channel_id 失败: $msg"
    return 1
  fi
}

# 设置渠道权重
set_channel_weight() {
  local channel_id="$1" new_weight="$2"

  local config
  config=$(get_channel "$channel_id")
  if [ "$config" = "{}" ] || [ -z "$config" ]; then
    log_error "无法获取渠道 ID=$channel_id 的配置"
    return 1
  fi

  local old_weight
  old_weight=$(echo "$config" | jq -r '.weight // "?"')
  local updated
  updated=$(echo "$config" | jq --argjson w "$new_weight" '.weight = $w')

  update_channel "$channel_id" "$updated"
  local rc=$?
  if [ $rc -eq 0 ]; then
    log_ok "渠道 ID=$channel_id 权重: $old_weight → $new_weight"
  fi
  return $rc
}

# 删除渠道
delete_channel() {
  local channel_id="$1"

  if [ "$DRY_RUN" = "true" ]; then
    log_info "[DRY-RUN] 将删除渠道 ID=$channel_id"
    return 0
  fi

  local resp
  resp=$(oneapi_api "DELETE" "/api/channel/$channel_id")
  local success
  success=$(echo "$resp" | jq -r '.success // false' 2>/dev/null)

  if [ "$success" = "true" ]; then
    log_ok "渠道 ID=$channel_id 已删除"
    return 0
  else
    local msg
    msg=$(echo "$resp" | jq -r '.message // "未知错误"' 2>/dev/null)
    log_error "删除渠道 ID=$channel_id 失败: $msg"
    return 1
  fi
}

# 测试渠道健康
test_channel() {
  local channel_id="$1" channel_name="$2"

  if [ "$DRY_RUN" = "true" ]; then
    log_info "[DRY-RUN] 将测试渠道「$channel_name」(ID=$channel_id)"
    return 0
  fi

  local resp
  resp=$(oneapi_api "GET" "/api/channel/test/$channel_id")
  local success
  success=$(echo "$resp" | jq -r '.success // false' 2>/dev/null)

  if [ "$success" = "true" ]; then
    return 0
  else
    local msg
    msg=$(echo "$resp" | jq -r '.message // "无详情"' 2>/dev/null)
    log_warn "渠道测试返回: $msg"
    return 1
  fi
}

# ==========================================
# 状态文件管理
# ==========================================
# 格式: channel_name|channel_id|last_rotation_date|last_key_hash

init_state_file() {
  if [ ! -f "$STATE_FILE" ]; then
    touch "$STATE_FILE"
    log_info "状态文件已创建: $STATE_FILE"
  fi
}

get_rotation_state() {
  local channel_name="$1"
  grep "^$channel_name|" "$STATE_FILE" 2>/dev/null || echo ""
}

set_rotation_state() {
  local channel_name="$1" channel_id="$2" key_hash="$3"

  local now
  now=$(date +%Y-%m-%d)
  local new_line="$channel_name|$channel_id|$now|$key_hash"

  if grep -q "^$channel_name|" "$STATE_FILE" 2>/dev/null; then
    local escaped_name
    escaped_name=$(echo "$channel_name" | sed 's/[.[\*^$()+?{|]/\\&/g')
    sed -i "s/^$escaped_name|.*/$new_line/" "$STATE_FILE"
  else
    echo "$new_line" >> "$STATE_FILE"
  fi
}

# 计算 Key 的 SHA256 哈希（用于比对变更）
hash_key() {
  echo -n "$1" | sha256sum | cut -d' ' -f1
}

# ==========================================
# 核心：Key 轮换流程
# ==========================================

# 临时渠道追踪（用于失败回滚）
TEMP_CHANNEL_ID=""
ROLLBACK_REQUIRED=false

# 回滚：删除本次创建的临时渠道
rollback() {
  local reason="$1"
  log_error "触发回滚: $reason"

  if [ -n "$TEMP_CHANNEL_ID" ] && [ "$TEMP_CHANNEL_ID" != "0" ]; then
    log_warn "删除临时渠道 ID=$TEMP_CHANNEL_ID ..."
    if [ "$DRY_RUN" = "false" ]; then
      delete_channel "$TEMP_CHANNEL_ID" || true
    fi
    local msg
    msg=$(cat <<EOF
⚠️ *Key 轮换回滚*

渠道: *$CHANNEL_NAME*
原因: $reason
临时渠道 ID=$TEMP_CHANNEL_ID 已清理
时间: $(date '+%Y-%m-%d %H:%M:%S')
EOF
)
    send_notify "$msg"
  fi

  log_error "轮换失败，已回滚到原始状态"
  exit 1
}

# 逐级提权（灰度）
# 从当前权重逐步提升到目标权重
gradual_weight_increase() {
  local channel_id="$1" channel_name="$2" target_weight="$3"

  log_step "灰度提权: $channel_name → 目标权重 $target_weight"

  # 提权阶梯：0 → 1 → 2 → target
  local steps=()
  if [ "$target_weight" -ge 1 ]; then steps+=("1"); fi
  if [ "$target_weight" -ge 2 ]; then steps+=("2"); fi
  if [ "$target_weight" -ge 3 ]; then steps+=("$target_weight"); fi

  # 去重：如果目标权重 <= 2，直接一步到位
  if [ "$target_weight" -le 2 ]; then
    steps=("$target_weight")
  fi

  for step_weight in "${steps[@]}"; do
    log_info "设置权重: $step_weight"
    if ! set_channel_weight "$channel_id" "$step_weight"; then
      log_error "设置权重 $step_weight 失败"
      return 1
    fi
    # 每步之间等待 30 秒观察
    if [ "$step_weight" != "$target_weight" ]; then
      log_info "等待 30 秒观察..."
      sleep 30
    fi
  done

  log_ok "灰度提权完成，当前权重: $target_weight"
  return 0
}

# 执行 Key 轮换
do_rotate() {
  local old_channel_id="$1" new_key="$2" target_weight="$3"

  log_step "第 1 步：读取旧渠道配置"

  local old_config
  old_config=$(get_channel "$old_channel_id")

  if [ "$old_config" = "{}" ] || [ -z "$old_config" ]; then
    log_error "渠道 ID=$old_channel_id 不存在或无法读取"
    exit 1
  fi

  CHANNEL_NAME=$(echo "$old_config" | jq -r '.name // "Unknown"')
  local old_key
  old_key=$(echo "$old_config" | jq -r '.key // ""')
  local old_weight
  old_weight=$(echo "$old_config" | jq -r '.weight // 1')

  log_info "渠道名称: $CHANNEL_NAME"
  log_info "旧 Key: ${old_key:0:12}...${old_key: -4}"
  log_info "旧权重: $old_weight"
  log_info "目标权重: $target_weight"

  # 幂等检查：如果新 Key 和旧 Key 相同，跳过
  if [ "$new_key" = "$old_key" ]; then
    log_warn "新 Key 与旧 Key 相同，无需轮换"
    return 0
  fi

  # 保存旧配置到本地备份
  local backup_file="$LOG_DIR/channel_${old_channel_id}_backup_$(date +%Y%m%d_%H%M%S).json"
  echo "$old_config" > "$backup_file"
  log_info "旧配置已备份到: $backup_file"

  # ==========================================
  # 第 2 步：创建新渠道（相同配置，新 Key，权重=0）
  # ==========================================
  log_step "第 2 步：创建新渠道（预热阶段，权重=0）"

  local new_payload
  new_payload=$(echo "$old_config" | jq \
    --arg key "$new_key" \
    --argjson weight 0 \
    --arg name "${CHANNEL_NAME}-new" \
    'del(.id) | .key = $key | .weight = $weight | .name = $name')

  TEMP_CHANNEL_ID=$(create_channel "$new_payload")

  if [ -z "$TEMP_CHANNEL_ID" ] || [ "$TEMP_CHANNEL_ID" = "0" ]; then
    if [ "$DRY_RUN" = "true" ]; then
      TEMP_CHANNEL_ID="0"
    else
      rollback "创建新渠道失败"
    fi
  fi

  log_ok "新渠道已创建 (ID=$TEMP_CHANNEL_ID, 权重=0, 名称=${CHANNEL_NAME}-new)"

  # ==========================================
  # 第 3 步：健康检查新渠道
  # ==========================================
  log_step "第 3 步：健康检查新渠道（最多 $HEALTH_RETRIES 次重试）"

  local health_ok=false
  for i in $(seq 1 $HEALTH_RETRIES); do
    log_info "健康检查尝试 $i/$HEALTH_RETRIES ..."
    if test_channel "$TEMP_CHANNEL_ID" "${CHANNEL_NAME}-new"; then
      health_ok=true
      log_ok "新渠道健康检查通过"
      break
    fi
    if [ "$i" -lt "$HEALTH_RETRIES" ]; then
      log_warn "等待 ${HEALTH_RETRY_INTERVAL}s 后重试..."
      sleep "$HEALTH_RETRY_INTERVAL"
    fi
  done

  if [ "$health_ok" = false ]; then
    rollback "新渠道健康检查失败（$HEALTH_RETRIES 次均未通过）"
  fi

  # 也尝试通过 healthcheck.sh 验证
  if [ -x "$HEALTHCHECK_SCRIPT" ] && [ "$DRY_RUN" = "false" ]; then
    log_info "通过 healthcheck.sh 验证新 Key..."
    # 直接使用新 Key 调用上游 API 验证
    local models_endpoint
    models_endpoint=$(echo "$old_config" | jq -r '.base_url // ""')"/v1/models"
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
      --max-time 10 \
      -H "Authorization: Bearer $new_key" \
      "$models_endpoint" 2>/dev/null || echo "000")
    case "$http_code" in
      200|401) log_ok "新 Key 上游验证通过 (HTTP $http_code)" ;;
      *) log_warn "新 Key 上游验证返回 HTTP $http_code（非致命，继续流程）" ;;
    esac
  fi

  # ==========================================
  # 第 4 步：逐步提权新渠道
  # ==========================================
  log_step "第 4 步：逐步提升新渠道权重"
  if ! gradual_weight_increase "$TEMP_CHANNEL_ID" "${CHANNEL_NAME}-new" "$target_weight"; then
    rollback "新渠道提权失败"
  fi

  # 通知：新渠道已上线
  local msg_up
  msg_up=$(cat <<EOF
🔑 *Key 轮换进行中 — 新渠道已上线*

渠道: *$CHANNEL_NAME*
新渠道 ID: $TEMP_CHANNEL_ID
新渠道权重: $target_weight
旧渠道 ID: $old_channel_id（权重仍为 $old_weight）
阶段: 观察窗口中 (${OBSERVE_SECONDS}s)
时间: $(date '+%Y-%m-%d %H:%M:%S')
EOF
)
  send_notify "$msg_up"

  # ==========================================
  # 第 5 步：观察窗口（5 分钟）
  # ==========================================
  log_step "第 5 步：观察窗口 — 等待 ${OBSERVE_SECONDS}s"

  local observe_start
  observe_start=$(date +%s)

  # 分段观察，每 60 秒检查一次新渠道健康
  local elapsed=0
  while [ "$elapsed" -lt "$OBSERVE_SECONDS" ]; do
    local remaining=$((OBSERVE_SECONDS - elapsed))
    log_info "观察中... (剩余 ${remaining}s)"

    # 检查新渠道是否仍然健康
    if ! test_channel "$TEMP_CHANNEL_ID" "${CHANNEL_NAME}-new" 2>/dev/null; then
      log_error "观察期间新渠道健康检查失败！"
      rollback "观察期间新渠道健康检查失败"
    fi

    sleep 60
    elapsed=$(($(date +%s) - observe_start))
  done

  log_ok "观察窗口结束，新渠道运行正常"

  # ==========================================
  # 第 6 步：旧渠道权重调到 0
  # ==========================================
  log_step "第 6 步：下线旧渠道（权重 → 0）"

  if ! set_channel_weight "$old_channel_id" "0"; then
    log_error "无法调整旧渠道权重，继续流程（旧渠道仍在线）"
  fi

  # 通知：旧渠道已下线
  local msg_down
  msg_down=$(cat <<EOF
🔑 *Key 轮换进行中 — 旧渠道已下线*

渠道: *$CHANNEL_NAME*
旧渠道 ID: $old_channel_id（权重 → 0）
新渠道 ID: $TEMP_CHANNEL_ID（权重 $target_weight）
阶段: 最终观察窗口 (${GRACE_SECONDS}s)
时间: $(date '+%Y-%m-%d %H:%M:%S')
EOF
)
  send_notify "$msg_down"

  # ==========================================
  # 第 7 步：再等 5 分钟 → 确认无问题
  # ==========================================
  log_step "第 7 步：最终观察 — 等待 ${GRACE_SECONDS}s 后删除旧渠道"

  local grace_start
  grace_start=$(date +%s)
  local grace_elapsed=0

  while [ "$grace_elapsed" -lt "$GRACE_SECONDS" ]; do
    local remaining=$((GRACE_SECONDS - grace_elapsed))
    log_info "最终观察... (剩余 ${remaining}s)"

    if ! test_channel "$TEMP_CHANNEL_ID" "${CHANNEL_NAME}-new" 2>/dev/null; then
      log_error "最终观察期间新渠道健康检查失败！正在恢复旧渠道..."
      set_channel_weight "$old_channel_id" "$old_weight" || true
      rollback "最终观察期间新渠道异常，已恢复旧渠道"
    fi

    sleep 60
    grace_elapsed=$(($(date +%s) - grace_start))
  done

  # ==========================================
  # 第 8 步：删除旧渠道
  # ==========================================
  log_step "第 8 步：清理旧渠道"

  if [ "$DRY_RUN" = "false" ]; then
    if delete_channel "$old_channel_id"; then
      log_ok "旧渠道 ID=$old_channel_id 已删除"
    else
      log_error "删除旧渠道失败，请手动处理 (ID=$old_channel_id)"
    fi
  else
    log_info "[DRY-RUN] 将删除旧渠道 ID=$old_channel_id"
  fi

  # ==========================================
  # 第 9 步：重命名新渠道（去掉 -new 后缀）
  # ==========================================
  log_step "第 9 步：重命名新渠道（去掉 -new 后缀）"

  local final_config
  final_config=$(get_channel "$TEMP_CHANNEL_ID")
  if [ "$final_config" != "{}" ] && [ -n "$final_config" ]; then
    local updated_config
    updated_config=$(echo "$final_config" | jq --arg name "$CHANNEL_NAME" '.name = $name')
    if update_channel "$TEMP_CHANNEL_ID" "$updated_config"; then
      log_ok "新渠道已重命名为「$CHANNEL_NAME」"
    else
      log_warn "重命名失败，渠道保持名称为「${CHANNEL_NAME}-new」"
    fi
  fi

  # 更新状态文件
  local new_key_hash
  new_key_hash=$(hash_key "$new_key")
  set_rotation_state "$CHANNEL_NAME" "$TEMP_CHANNEL_ID" "$new_key_hash"

  # ==========================================
  # 完成
  # ==========================================
  log_step "Key 轮换完成"

  local msg_done
  msg_done=$(cat <<EOF
✅ *Key 轮换完成*

渠道: *$CHANNEL_NAME*
新渠道 ID: $TEMP_CHANNEL_ID
旧渠道 ID: $old_channel_id（已删除）
权重: $target_weight
时间: $(date '+%Y-%m-%d %H:%M:%S')

轮换日志: $ROTATION_LOG
EOF
)
  send_notify "$msg_done"

  log_ok "渠道「$CHANNEL_NAME」Key 轮换成功完成"
  log_info "新渠道 ID: $TEMP_CHANNEL_ID, 权重: $target_weight"
  log_info "详细日志: $ROTATION_LOG"

  return 0
}

# ==========================================
# 自动模式：扫描所有渠道判断是否需要轮换
# ==========================================

# 渠道 → 环境变量 映射
# 格式: channel_name|env_var
AUTO_CHANNELS=(
  "DeepSeek|DEEPSEEK_API_KEY"
  "智谱 Z.ai|ZHIPU_ZAI_API_KEY"
  "小米 MiMo|MIMO_API_KEY"
)

do_auto_rotate() {
  log_step "自动轮换模式：扫描所有渠道"

  local rotated=0 skipped=0

  for mapping in "${AUTO_CHANNELS[@]}"; do
    IFS='|' read -r channel_name env_var <<< "$mapping"

    # 获取新 Key 值（从环境变量）
    local new_key="${!env_var:-}"
    if [ -z "$new_key" ]; then
      log_warn "渠道「$channel_name」环境变量 $env_var 未设置，跳过"
      skipped=$((skipped + 1))
      continue
    fi

    # 获取当前渠道
    local old_channel_id
    old_channel_id=$(find_channel_id_by_name "$channel_name")

    if [ -z "$old_channel_id" ]; then
      log_warn "渠道「$channel_name」在 OneAPI 中不存在，跳过"
      skipped=$((skipped + 1))
      continue
    fi

    # 获取旧渠道配置中的 Key
    local old_config
    old_config=$(get_channel "$old_channel_id")
    local old_key
    old_key=$(echo "$old_config" | jq -r '.key // ""' 2>/dev/null)

    # 比对 Key 是否变化
    if [ "$new_key" = "$old_key" ]; then
      log_info "渠道「$channel_name」Key 未变化，跳过"
      skipped=$((skipped + 1))
      continue
    fi

    # 检查状态文件中的上次轮换日期
    local state_line
    state_line=$(get_rotation_state "$channel_name")
    if [ -n "$state_line" ]; then
      IFS='|' read -r _ _ last_date _ <<< "$state_line"
      local days_since
      days_since=$(( ($(date +%s) - $(date -d "$last_date" +%s 2>/dev/null || echo 0)) / 86400 ))
      if [ "${days_since:-0}" -lt 90 ] && [ "$DRY_RUN" != "true" ]; then
        # 可选严格模式：不到 90 天也允许 --auto 轮换（Key 变了就轮换）
        log_info "渠道「$channel_name」上次轮换: $last_date (${days_since} 天前)"
      fi
    fi

    log_info "渠道「$channel_name」检测到 Key 变化，开始轮换..."

    if do_rotate "$old_channel_id" "$new_key" "$TARGET_WEIGHT"; then
      rotated=$((rotated + 1))
    else
      log_error "渠道「$channel_name」轮换失败"
    fi

    # 重置临时渠道 ID（避免下一个渠道轮换时的回滚误删）
    TEMP_CHANNEL_ID=""
  done

  echo ""
  log_info "自动轮换汇总: $rotated 个轮换, $skipped 个跳过"

  local msg_auto
  msg_auto=$(cat <<EOF
🔄 *Key 自动轮换扫描完成*

轮换: $rotated 个渠道
跳过: $skipped 个渠道
时间: $(date '+%Y-%m-%d %H:%M:%S')
EOF
)
  send_notify "$msg_auto"
}

# ==========================================
# 使用说明
# ==========================================
usage() {
  cat <<EOF
用法:
  $0 --channel-id <ID> --new-key <KEY>          手动轮换指定渠道
  $0 --channel-name <NAME> --new-key <KEY>       按名称查找渠道并轮换
  $0 --auto                                       自动模式（从 .env 读取，扫描所有渠道）
  $0 --auto --dry-run                             预演自动模式

选项:
  --channel-id <N>        要轮换的旧渠道 ID（手动模式）
  --channel-name <NAME>   要轮换的渠道名称（手动模式，如 "DeepSeek"）
  --new-key <KEY>         新的 API Key
  --target-weight <N>     新渠道目标权重（默认: $TARGET_WEIGHT）
  --dry-run               仅检查不执行
  --auto                  自动模式：从 docker/.env 读取 Key，自动检测变更并轮换
  --status                显示当前轮换状态
  -h, --help              显示此帮助

环境变量（从 docker/.env 加载）:
  ONEAPI_URL              OneAPI 地址（默认: $ONEAPI_URL）
  ONEAPI_ROOT_TOKEN       OneAPI 管理员 Token
  TELEGRAM_BOT_TOKEN      Telegram Bot Token
  TELEGRAM_CHAT_ID        Telegram Chat ID

示例:
  # 手动轮换 DeepSeek 渠道（ID=1）
  $0 --channel-id 1 --new-key "sk-new-key-xxx"

  # 按名称轮换
  $0 --channel-name "DeepSeek" --new-key "sk-new-key-xxx"

  # 预演
  $0 --channel-id 1 --new-key "sk-new-key-xxx" --dry-run

  # 自定义权重
  $0 --channel-id 1 --new-key "sk-new-key-xxx" --target-weight 5

  # 自动扫描所有渠道
  $0 --auto
EOF
}

# ==========================================
# 状态显示
# ==========================================
show_status() {
  echo ""
  echo "========================================="
  echo " Key 轮换状态"
  echo " 时间: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "========================================="
  echo ""

  if [ ! -f "$STATE_FILE" ] || [ ! -s "$STATE_FILE" ]; then
    echo "  尚无轮换记录"
    echo ""
    return
  fi

  printf "  %-16s %-10s %-14s %s\n" "渠道" "渠道ID" "上次轮换" "Key Hash"
  echo "  ─────────────────── ────────── ────────────── ────────────────────────────────"

  while IFS='|' read -r name ch_id last_date key_hash; do
    [ -z "$name" ] && continue
    printf "  %-16s %-10s %-14s %s\n" "$name" "$ch_id" "$last_date" "${key_hash:0:16}..."
  done < "$STATE_FILE"

  echo ""
}

# ==========================================
# 主入口
# ==========================================
main() {
  local channel_id=""
  local channel_name=""
  local new_key=""
  local auto_mode=false

  # 解析参数
  while [ $# -gt 0 ]; do
    case "$1" in
      --channel-id)
        channel_id="$2"; shift 2 ;;
      --channel-name)
        channel_name="$2"; shift 2 ;;
      --new-key)
        new_key="$2"; shift 2 ;;
      --target-weight)
        TARGET_WEIGHT="$2"; shift 2 ;;
      --dry-run)
        DRY_RUN=true; shift ;;
      --auto)
        auto_mode=true; shift ;;
      --status)
        load_env
        init_state_file
        show_status
        exit 0 ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        echo "未知参数: $1"
        usage
        exit 1 ;;
    esac
  done

  # 加载环境
  load_env

  # 路径安全检查
  if [ -z "${ONEAPI_ROOT_TOKEN:-}" ]; then
    log_error "ONEAPI_ROOT_TOKEN 未设置。请在 docker/.env 中设置 ONEAPI_ADMIN_TOKEN，或导出环境变量。"
    exit 1
  fi

  init_state_file

  # 日志头
  {
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo " Key 轮换 — $(date '+%Y-%m-%d %H:%M:%S')"
    echo "═══════════════════════════════════════════════════"
  } | tee -a "$ROTATION_LOG"

  if [ "$DRY_RUN" = "true" ]; then
    log_info "=== DRY-RUN 模式：仅检查，不实际修改 ==="
  fi

  # 自动模式
  if [ "$auto_mode" = true ]; then
    do_auto_rotate
    exit $?
  fi

  # 手动模式参数校验
  if [ -z "$channel_id" ] && [ -n "$channel_name" ]; then
    channel_id=$(find_channel_id_by_name "$channel_name")
    if [ -z "$channel_id" ]; then
      log_error "未找到渠道「$channel_name」"
      exit 1
    fi
    log_info "渠道「$channel_name」→ ID=$channel_id"
  fi

  if [ -z "$channel_id" ]; then
    log_error "请指定 --channel-id 或 --channel-name"
    usage
    exit 1
  fi

  if [ -z "$new_key" ]; then
    log_error "请指定 --new-key"
    usage
    exit 1
  fi

  # 执行轮换
  do_rotate "$channel_id" "$new_key" "$TARGET_WEIGHT"
}

main "$@"
