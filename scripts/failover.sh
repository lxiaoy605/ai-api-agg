#!/usr/bin/env bash
# =============================================
# AI API 聚合平台 — 故障自动切换脚本
# =============================================
# 功能：
#   1. 调用 healthcheck.sh 检测各渠道健康状态
#   2. 连续 3 次失败 → 标记为 DOWN，通过 OneAPI API 将权重调为 0
#   3. 恢复后自动还原原始权重
#   4. Telegram Bot 通知所有故障/恢复事件
#   5. 日志写入 logs/failover.log
#
# 用法：
#   ./failover.sh                    # 标准模式（检测 + 切换）
#   ./failover.sh --dry-run          # 模拟运行（不实际修改权重）
#   ./failover.sh --status           # 仅显示当前状态
#   ./failover.sh --reset-channel "DeepSeek"  # 手动重置渠道状态
#
# 环境变量：
#   ONEAPI_URL             OneAPI 内部地址（默认 http://localhost:3000）
#   ONEAPI_ROOT_TOKEN      OneAPI 管理员 Token（从管理面板获取）
#   TELEGRAM_BOT_TOKEN     Telegram Bot Token（@Xiao_friend_bot）
#   TELEGRAM_CHAT_ID       Telegram Chat ID
#   FAILOVER_THRESHOLD     连续失败次数阈值（默认 3）
# =============================================

set -euo pipefail

# ==========================================
# 路径
# ==========================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_DIR/logs"
mkdir -p "$LOG_DIR"

STATE_FILE="$LOG_DIR/failover.state"
FAILOVER_LOG="$LOG_DIR/failover.log"
ENV_FILE="$PROJECT_DIR/docker/.env"
HEALTHCHECK_SCRIPT="$SCRIPT_DIR/healthcheck.sh"

# ==========================================
# 配置
# ==========================================
ONEAPI_URL="${ONEAPI_URL:-http://localhost:3000}"
FAILOVER_THRESHOLD="${FAILOVER_THRESHOLD:-3}"

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
# 渠道定义（与 healthcheck.sh + channel-configs.json 保持一致）
# ==========================================
# 格式: name|default_weight
CHANNELS=(
  "DeepSeek|3"
  "智谱 Z.ai|3"
  "小米 MiMo|2"
)

# ==========================================
# 日志
# ==========================================
log_msg() {
  local level="$1"; shift
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] [$level] $*" | tee -a "$FAILOVER_LOG"
}

log_info()  { log_msg "INFO" "$@"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; log_msg "WARN" "$@"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; log_msg "ERROR" "$@"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; log_msg "OK" "$@"; }

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

  # ONEAPI_ROOT_TOKEN 也可从 ONEAPI_ADMIN_TOKEN 读取
  if [ -z "${ONEAPI_ROOT_TOKEN:-}" ] && [ -n "${ONEAPI_ADMIN_TOKEN:-}" ]; then
    ONEAPI_ROOT_TOKEN="$ONEAPI_ADMIN_TOKEN"
  fi
}

# 统一通知脚本路径
NOTIFY_SCRIPT="$SCRIPT_DIR/ops-notify.sh"

# ==========================================
# 运维通知（通过统一通知脚本 ops-notify.sh）
# ==========================================
send_notify() {
  local level="$1" title="$2" message="$3"
  local channel="${4:-default}"
  if [ -x "$NOTIFY_SCRIPT" ]; then
    "$NOTIFY_SCRIPT" --level "$level" --title "$title" --message "$message" --channel "$channel" --silent || true
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

# 按名称查找 OneAPI 渠道 ID
find_channel_id() {
  local name="$1"
  oneapi_api "GET" "/api/channel/?p=0&page_size=100" | \
    jq -r --arg name "$name" '.data[]? | select(.name == $name) | .id' 2>/dev/null || echo ""
}

# 获取渠道当前配置
get_channel_config() {
  local channel_id="$1"
  oneapi_api "GET" "/api/channel/$channel_id" | jq '.data // {}' 2>/dev/null || echo "{}"
}

# 设置渠道权重
# 返回: 0=成功, 1=失败
set_channel_weight() {
  local channel_name="$1"
  local new_weight="$2"

  local channel_id
  channel_id=$(find_channel_id "$channel_name")

  if [ -z "$channel_id" ]; then
    log_error "未在 OneAPI 中找到渠道「$channel_name」，无法调整权重"
    return 1
  fi

  # 获取当前渠道配置
  local current_config
  current_config=$(get_channel_config "$channel_id")

  if [ "$current_config" = "{}" ] || [ -z "$current_config" ]; then
    log_error "无法获取渠道「$channel_name」(ID=$channel_id) 的配置"
    return 1
  fi

  # 修改权重
  local updated_config
  updated_config=$(echo "$current_config" | jq --argjson w "$new_weight" '.weight = $w')

  # 提交更新
  local resp
  resp=$(oneapi_api "PUT" "/api/channel/$channel_id" "$updated_config")
  local success
  success=$(echo "$resp" | jq -r '.success // false' 2>/dev/null)

  if [ "$success" = "true" ]; then
    log_ok "渠道「$channel_name」(ID=$channel_id) 权重已更新: $(echo "$current_config" | jq -r '.weight') → $new_weight"
    return 0
  else
    local msg
    msg=$(echo "$resp" | jq -r '.message // "未知错误"')
    log_error "更新渠道「$channel_name」权重失败: $msg"
    return 1
  fi
}

# ==========================================
# 状态文件管理
# ==========================================

# 初始化状态文件
init_state() {
  if [ ! -f "$STATE_FILE" ]; then
    {
      echo "# AI API 聚合平台 — 故障切换状态"
      echo "# 格式: channel_name|original_weight|consecutive_failures|status|last_update"
      for channel_def in "${CHANNELS[@]}"; do
        IFS='|' read -r name weight <<< "$channel_def"
        local now
        now=$(date -Iseconds)
        echo "$name|$weight|0|UP|$now"
      done
    } > "$STATE_FILE"
    log_info "状态文件已初始化: $STATE_FILE"
  fi
}

# 读取渠道状态
# 输出: original_weight|failures|status|last_update
get_channel_state() {
  local name="$1"
  grep "^$name|" "$STATE_FILE" 2>/dev/null | head -1 || echo ""
}

# 更新渠道状态
update_channel_state() {
  local name="$1" weight="$2" failures="$3" status="$4"
  local now
  now=$(date -Iseconds)

  # 构建新行
  local new_line="$name|$weight|$failures|$status|$now"

  if grep -q "^$name|" "$STATE_FILE" 2>/dev/null; then
    # 更新现有行（用 | 做分隔符，转义特殊字符）
    local escaped_name
    escaped_name=$(echo "$name" | sed 's/[.[\*^$()+?{|]/\\&/g')
    sed -i "s/^$escaped_name|.*/$new_line/" "$STATE_FILE"
  else
    echo "$new_line" >> "$STATE_FILE"
  fi
}

# ==========================================
# 健康检查（调用 healthcheck.sh）
# ==========================================

check_channel_health() {
  local channel_name="$1"

  if [ ! -x "$HEALTHCHECK_SCRIPT" ]; then
    log_error "healthcheck.sh 不存在或不可执行: $HEALTHCHECK_SCRIPT"
    return 1
  fi

  # 调用 healthcheck.sh 检测指定渠道
  if "$HEALTHCHECK_SCRIPT" --channel "$channel_name" --no-external >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# ==========================================
# 故障切换引擎
# ==========================================

process_channel() {
  local name="$1" default_weight="$2" dry_run="${3:-false}"

  # 读取当前状态
  local state_line
  state_line=$(get_channel_state "$name")

  local orig_weight="$default_weight" failures=0 chan_status="UP"
  if [ -n "$state_line" ]; then
    IFS='|' read -r _ orig_weight failures chan_status _ <<< "$state_line"
  fi

  log_info "检测渠道「$name」(权重=$orig_weight, 失败=$failures, 状态=$chan_status)"

  # 执行健康检查
  local healthy=true
  if ! check_channel_health "$name"; then
    healthy=false
  fi

  if $healthy; then
    # 渠道健康
    if [ "$chan_status" = "DOWN" ]; then
      # 恢复：从 DOWN → UP
      log_ok "渠道「$name」已恢复！"

      if [ "$dry_run" = "false" ]; then
        set_channel_weight "$name" "$orig_weight" || true
      else
        log_info "[DRY-RUN] 将恢复渠道「$name」权重为 $orig_weight"
      fi

      update_channel_state "$name" "$orig_weight" "0" "UP"
      send_notify "warning" "渠道恢复: $name" "渠道 $name 已从 DOWN 恢复为 UP，权重已恢复为 $orig_weight"

    else
      # 持续健康，重置失败计数
      update_channel_state "$name" "$orig_weight" "0" "UP"
    fi
  else
    # 渠道不健康
    failures=$((failures + 1))
    log_warn "渠道「$name」检测失败 ($failures/$FAILOVER_THRESHOLD)"

    if [ "$failures" -ge "$FAILOVER_THRESHOLD" ] && [ "$chan_status" != "DOWN" ]; then
      # 触发故障切换
      log_error "渠道「$name」连续失败 $failures 次，触发故障切换！"

      if [ "$dry_run" = "false" ]; then
        set_channel_weight "$name" "0" || true
      else
        log_info "[DRY-RUN] 将设置渠道「$name」权重为 0"
      fi

      update_channel_state "$name" "$orig_weight" "$failures" "DOWN"
      send_notify "critical" "渠道故障切换: $name" "渠道 $name 连续失败 ${failures} 次，已自动切换。权重调为 0，流量已路由至其他渠道。请检查该渠道上游 API 是否正常。"

    elif [ "$chan_status" = "DOWN" ]; then
      # 持续 DOWN，继续跟踪
      update_channel_state "$name" "$orig_weight" "$failures" "DOWN"
      log_warn "渠道「$name」仍处于 DOWN 状态 (连续失败 $failures 次)"
    else
      # 失败次数不足，继续观察
      update_channel_state "$name" "$orig_weight" "$failures" "UP"
    fi
  fi
}

# ==========================================
# 显示状态
# ==========================================

show_status() {
  echo ""
  echo "========================================="
  echo " 故障切换状态"
  echo " 时间: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "========================================="
  echo ""

  if [ ! -f "$STATE_FILE" ]; then
    echo "  状态文件不存在，尚未初始化。"
    echo "  请先运行: ./failover.sh"
    echo ""
    return
  fi

  printf "  %-16s %-8s %-8s %-6s %s\n" "渠道" "原始权重" "失败次数" "状态" "最后更新"
  echo "  ─────────────────── ──────── ──────── ────── ───────────────────"

  while IFS='|' read -r name weight failures status last_update; do
    # 跳过注释行
    [[ "$name" =~ ^# ]] && continue
    [ -z "$name" ] && continue

    local color="$GREEN"
    local icon="✓"
    case "$status" in
      DOWN)
        color="$RED"
        icon="✗"
        ;;
      UP)
        color="$GREEN"
        icon="✓"
        ;;
    esac

    printf "  ${color}${icon}${NC} %-14s %-8s %-8s ${color}%-6s${NC} %s\n" \
      "$name" "$weight" "$failures" "$status" "$last_update"
  done < "$STATE_FILE"

  echo ""
}

# ==========================================
# 重置渠道
# ==========================================

reset_channel() {
  local name="$1"
  log_info "重置渠道「$name」状态..."

  # 查找默认权重
  local default_weight=""
  for channel_def in "${CHANNELS[@]}"; do
    IFS='|' read -r c_name c_weight <<< "$channel_def"
    if [ "$c_name" = "$name" ]; then
      default_weight="$c_weight"
      break
    fi
  done

  if [ -z "$default_weight" ]; then
    log_error "未知渠道: $name"
    return 1
  fi

  # 恢复权重
  set_channel_weight "$name" "$default_weight" || true

  # 重置状态
  local now
  now=$(date -Iseconds)
  update_channel_state "$name" "$default_weight" "0" "UP"

  log_ok "渠道「$name」已重置"
}

# ==========================================
# 主流程
# ==========================================

main() {
  local dry_run=false

  # 解析参数
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run)
        dry_run=true
        log_info "=== DRY-RUN 模式：不会实际修改渠道权重 ==="
        ;;
      --status)
        show_status
        exit 0
        ;;
      --reset-channel)
        load_env
        init_state
        reset_channel "$2"
        exit $?
        ;;
      *)
        echo "用法: $0 [--dry-run] [--status] [--reset-channel <name>]"
        exit 1
        ;;
    esac
    shift
  done

  load_env
  init_state

  echo ""
  echo "╔══════════════════════════════════════════════════╗"
  echo "║   AI API 聚合平台 — 故障自动切换引擎              ║"
  echo "║   阈值: 连续 $FAILOVER_THRESHOLD 次失败 → 切换       ║"
  if $dry_run; then
    echo "║   ⚠ DRY-RUN 模式                                ║"
  fi
  echo "╚══════════════════════════════════════════════════╝"
  echo ""

  log_info "========== 故障切换检测开始 =========="

  local has_down=false

  for channel_def in "${CHANNELS[@]}"; do
    IFS='|' read -r name weight <<< "$channel_def"
    process_channel "$name" "$weight" "$dry_run"

    # 检查当前状态
    local state_line
    state_line=$(get_channel_state "$name")
    local chan_status
    chan_status=$(echo "$state_line" | cut -d'|' -f4)
    if [ "$chan_status" = "DOWN" ]; then
      has_down=true
    fi
  done

  echo ""

  if $has_down; then
    echo -e " ${RED}⚠ 存在 DOWN 渠道，请及时处理${NC}"
    log_msg "SUMMARY" "存在 DOWN 渠道"
  else
    echo -e " ${GREEN}✓ 所有渠道正常${NC}"
    log_msg "SUMMARY" "所有渠道正常"
  fi

  echo ""
  log_info "========== 故障切换检测结束 =========="
}

main "$@"
