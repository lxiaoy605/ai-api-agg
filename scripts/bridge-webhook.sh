#!/usr/bin/env bash
# ============================================================
# bridge-webhook.sh — 桥（AI 助手）监听通道
# ============================================================
# 定期检查 ops-notify.log 中带 bridge 标记的事件，
# 格式化上下文发送给桥以便主动跟进
#
# 工作模式：
#   1. poll  — 拉取最近 N 分钟内的 bridge 事件并推送给桥
#   2. watch — 持续监听（tail -f），有新事件时推送
#   3. dump  — 输出指定时间范围的 bridge 事件（供外部系统消费）
#
# 用法：
#   ./bridge-webhook.sh poll [--minutes 10]    # 拉取最近 N 分钟事件
#   ./bridge-webhook.sh watch                   # 持续监听
#   ./bridge-webhook.sh dump [--since 1h]       # 输出指定范围事件
#
# 环境变量：
#   TELEGRAM_BOT_TOKEN          Bot Token
#   TELEGRAM_BRIDGE_CHAT_ID     桥的 Chat ID（接收事件推送）
#   TELEGRAM_CHAT_ID            主频道（桥事件回退目标）
# ============================================================

set -euo pipefail

# ---------- 路径 ----------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_DIR/logs"
ENV_FILE="$PROJECT_DIR/docker/.env"
OPS_LOG="$LOG_DIR/ops-notify.log"
BRIDGE_LOG="$LOG_DIR/bridge-webhook.log"
NOTIFY_SCRIPT="$SCRIPT_DIR/ops-notify.sh"
STATE_FILE="$LOG_DIR/bridge-webhook.state"

mkdir -p "$LOG_DIR"

# ---------- 加载环境变量 ----------
load_env() {
  if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE" 2>/dev/null || true
    set +a
  fi
}

# ---------- 日志 ----------
log_bridge() {
  local timestamp
  timestamp=$(date -Iseconds)
  echo "[$timestamp] $*" >> "$BRIDGE_LOG"
}

# ---------- 获取上次检查位置 ----------
get_cursor() {
  if [ -f "$STATE_FILE" ]; then
    cat "$STATE_FILE"
  else
    echo "0"
  fi
}

set_cursor() {
  echo "$1" > "$STATE_FILE"
}

# ---------- 解析 ops-notify.log 中的 bridge 事件 ----------
# 格式: [timestamp] [level] [ch=bridge] title=xxx | message
parse_bridge_events() {
  local since_minutes="${1:-10}"
  local since_time
  since_time=$(date -d "$since_minutes minutes ago" -Iseconds 2>/dev/null || date -v-${since_minutes}M -Iseconds 2>/dev/null || echo "")

  if [ ! -f "$OPS_LOG" ]; then
    echo "暂无运维通知日志"
    return
  fi

  local events=""
  local count=0

  while IFS= read -r line; do
    # 只匹配 bridge 通道的事件
    if echo "$line" | grep -q "ch=bridge"; then
      # 提取时间戳
      local line_ts
      line_ts=$(echo "$line" | grep -oP '^\[\K[^\]]+' || echo "")

      # 时间过滤
      if [ -n "$since_time" ] && [ -n "$line_ts" ]; then
        if [[ "$line_ts" < "$since_time" ]]; then
          continue
        fi
      fi

      # 解析字段
      local level
      level=$(echo "$line" | grep -oP '\] \[\K[^\]]+' || echo "?")
      local title_part
      title_part=$(echo "$line" | grep -oP 'title=\K[^|]+' || echo "?")
      local msg_part
      msg_part=$(echo "$line" | grep -oP '\| \K.*' || echo "")

      title_part=$(echo "$title_part" | xargs)
      msg_part=$(echo "$msg_part" | xargs)

      local emoji="🔵"
      case "$level" in
        critical) emoji="🔴" ;;
        warning)  emoji="🟡" ;;
      esac

      events+="${emoji} [${level}] ${title_part}"$'\n'
      [ -n "$msg_part" ] && events+="   ${msg_part}"$'\n'
      count=$((count + 1))
    fi
  done < "$OPS_LOG"

  if [ "$count" -eq 0 ]; then
    echo "最近 ${since_minutes} 分钟无 bridge 事件"
  else
    echo "bridge 事件 (最近${since_minutes}分钟, 共${count}条):"$'\n'"$events"
  fi
}

# ---------- 格式化推送给桥的消息 ----------
format_for_bridge() {
  local content="$1"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  cat <<MSG
🤖 *桥 · 运维事件推送*
⏰ ${timestamp}

${content}

━━━━━━━━━━━━━━━━━━━━
💡 建议跟进：如有 critical 事件请优先排查
MSG
}

# ---------- 模式: poll ----------
do_poll() {
  local minutes="${1:-10}"

  log_bridge "poll: 拉取最近 ${minutes} 分钟 bridge 事件"

  local events
  events=$(parse_bridge_events "$minutes")

  # 获取 bridge chat id
  local bridge_chat="${TELEGRAM_BRIDGE_CHAT_ID:-}"
  if [ -z "$bridge_chat" ]; then
    log_bridge "TELEGRAM_BRIDGE_CHAT_ID 未配置，跳过推送"
    echo "$events"
    return 0
  fi

  # 检查是否有实际事件
  if echo "$events" | grep -q "无 bridge 事件"; then
    log_bridge "无新事件，跳过推送"
    return 0
  fi

  # 格式化并推送
  local msg
  msg=$(format_for_bridge "$events")

  "$NOTIFY_SCRIPT" \
    --level warning \
    --title "桥事件汇总 (${minutes}min)" \
    --message "$msg" \
    --channel bridge \
    --silent

  log_bridge "已推送 ${minutes} 分钟内 bridge 事件到桥"
}

# ---------- 模式: watch ----------
do_watch() {
  log_bridge "watch: 开始持续监听 ops-notify.log"

  if [ ! -f "$OPS_LOG" ]; then
    touch "$OPS_LOG"
  fi

  tail -n 0 -f "$OPS_LOG" 2>/dev/null | while IFS= read -r line; do
    if echo "$line" | grep -q "ch=bridge"; then
      local level
      level=$(echo "$line" | grep -oP '\] \[\K[^\]]+' || echo "info")
      local title_part
      title_part=$(echo "$line" | grep -oP 'title=\K[^|]+' || echo "新事件")
      local msg_part
      msg_part=$(echo "$line" | grep -oP '\| \K.*' || echo "")

      # 仅 critical 和 warning 实时推送
      if [ "$level" = "critical" ] || [ "$level" = "warning" ]; then
        "$NOTIFY_SCRIPT" \
          --level "$level" \
          --title "桥: $(echo "$title_part" | xargs)" \
          --message "$(echo "$msg_part" | xargs)" \
          --channel bridge \
          --silent
      fi
    fi
  done
}

# ---------- 模式: dump ----------
do_dump() {
  local since="${1:-1h}"
  local minutes

  case "$since" in
    *h) minutes=$((${since%h} * 60)) ;;
    *m) minutes=${since%m} ;;
    *)  minutes=60 ;;
  esac

  parse_bridge_events "$minutes"
}

# ---------- 主流程 ----------
main() {
  load_env

  local mode="${1:-poll}"
  local arg="${2:-}"

  case "$mode" in
    poll)
      local minutes=10
      if [ "$arg" = "--minutes" ] && [ -n "${3:-}" ]; then
        minutes="$3"
      fi
      do_poll "$minutes"
      ;;
    watch)
      do_watch
      ;;
    dump)
      local since="1h"
      if [ "$arg" = "--since" ] && [ -n "${3:-}" ]; then
        since="$3"
      fi
      do_dump "$since"
      ;;
    *)
      echo "用法: $0 {poll [--minutes N]|watch|dump [--since 1h]}"
      exit 1
      ;;
  esac
}

main "${@:-}"
