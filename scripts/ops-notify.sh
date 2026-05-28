#!/usr/bin/env bash
# ============================================================
# ops-notify.sh — AI API 聚合平台统一运维通知脚本
# ============================================================
# 所有运维事件统一走此脚本，替代分散的 Telegram 通知
#
# 用法：
#   ops-notify.sh --level critical|warning|info \
#                 --title "事件标题" \
#                 --message "事件详情" \
#                 [--channel bridge] \
#                 [--silent]
#
# 通知分级：
#   critical → 即时推送 + 响铃
#   warning  → 即时推送 + 静默
#   info     → 仅记录日志（等每日汇总）
#
# 通道：
#   default → TELEGRAM_CHAT_ID（运维主频道）
#   bridge  → TELEGRAM_BRIDGE_CHAT_ID（桥跟进频道）
#
# 环境变量（从 docker/.env 读取）：
#   TELEGRAM_BOT_TOKEN         Bot Token
#   TELEGRAM_CHAT_ID           运维主频道 Chat ID
#   TELEGRAM_BRIDGE_CHAT_ID    桥跟进频道 Chat ID
# ============================================================

set -euo pipefail

# ---------- 路径 ----------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_DIR/logs"
ENV_FILE="$PROJECT_DIR/docker/.env"
NOTIFY_LOG="$LOG_DIR/ops-notify.log"

mkdir -p "$LOG_DIR"

# ---------- 加载环境变量 ----------
load_env() {
  if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE" 2>/dev/null || true
    set +a
  fi
}

# ---------- 日志 ----------
log_notify() {
  local level="$1" channel="$2" title="$3" message="$4"
  local timestamp
  timestamp=$(date -Iseconds)
  echo "[$timestamp] [$level] [ch=$channel] title=$title | $message" >> "$NOTIFY_LOG"
}

# ---------- 发送 Telegram 消息 ----------
send_telegram() {
  local chat_id="$1" text="$2" silent="$3"
  local bot_token="${TELEGRAM_BOT_TOKEN:-}"

  if [ -z "$bot_token" ] || [ -z "$chat_id" ]; then
    echo "[ops-notify] WARN: Telegram 未配置 (bot_token/chat_id 为空)，跳过发送" >> "$NOTIFY_LOG"
    return 1
  fi

  local disable_notification="false"
  if [ "$silent" = "true" ]; then
    disable_notification="true"
  fi

  curl -s -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
      --arg chat_id "$chat_id" \
      --arg text "$text" \
      --arg disable "$disable_notification" \
      --arg parse_mode "Markdown" \
      '{chat_id: $chat_id, text: $text, parse_mode: $parse_mode, disable_notification: $disable}')" \
    >/dev/null 2>&1 || {
    echo "[ops-notify] ERROR: Telegram API 调用失败" >> "$NOTIFY_LOG"
    return 1
  }
}

# ---------- 格式化消息 ----------
format_message() {
  local level="$1" title="$2" message="$3"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local emoji=""

  case "$level" in
    critical) emoji="🔴" ;;
    warning)  emoji="🟡" ;;
    info)     emoji="🔵" ;;
    *)        emoji="📢" ;;
  esac

  # Markdown 格式，移动端友好
  cat <<MSG
${emoji} *${title}*
⏰ ${timestamp}

${message}
MSG
}

# ---------- 预定义事件（快捷方式） ----------
# 通过 --event <event_name> 可使用预定义通知模板
dispatch_event() {
  local event="$1" message="${2:-}"
  case "$event" in
    config-sync-success)
      level="info"
      title="Config Sync 完成"
      message="${message:-渠道配置已同步到 OneAPI，无差异。}"
      ;;
    config-sync-error)
      level="critical"
      title="Config Sync 失败"
      message="${message:-渠道配置同步失败，请检查审计日志。}"
      channel="bridge"
      ;;
    config-sync-diff)
      level="warning"
      title="Config Sync 检测到差异"
      message="${message:-OneAPI 渠道配置与本地 config 不一致。}"
      ;;
    keepalived-failover)
      level="critical"
      title="Keepalived 故障转移"
      message="${message:-VIP 已从 Master 漂移到 Backup。}"
      channel="bridge"
      ;;
    keepalived-recovery)
      level="warning"
      title="Keepalived 恢复"
      message="${message:-Master 节点已恢复，VIP 已绑定回原节点。}"
      ;;
    channel-health-fail)
      level="critical"
      title="渠道健康检查失败"
      message="${message:-渠道健康检查失败，可能影响服务。}"
      channel="bridge"
      ;;
    *)
      echo "未知事件: $event"
      usage
      ;;
  esac
}

# ---------- 使用说明 ----------
usage() {
  cat <<EOF
用法: $0 --level <level> --title <title> --message <msg> [选项]
      $0 --event <event_name> --message <msg> [选项]

必选参数（二选一）:
  --level     critical | warning | info
  --title     事件标题（简短）
  --message   事件详情（支持多行，用引号包裹）

  或使用预定义事件:
  --event     config-sync-success | config-sync-error | config-sync-diff |
              keepalived-failover | keepalived-recovery | channel-health-fail

可选参数:
  --channel   通知通道: default (主频道) | bridge (桥跟进频道)
  --silent    静默发送（不触发通知铃声）

示例:
  $0 --level warning --title "余额预警" --message "DeepSeek 余额 \$3.50，低于 \$5 阈值"
  $0 --level critical --title "渠道故障" --message "小米 MiMo 连续 3 次健康检查失败" --channel bridge
  $0 --level info --title "备份成功" --message "每日备份完成，大小 2.3MB"
  $0 --event config-sync-success --message "6 个渠道全部同步完成"
  $0 --event keepalived-failover --message "Master HAProxy 异常，VIP 已漂移"
EOF
  exit 0
}

# ---------- 主流程 ----------
main() {
  local level=""
  local title=""
  local message=""
  local channel="default"
  local silent="false"
  local event=""

  # 解析参数
  while [ $# -gt 0 ]; do
    case "$1" in
      --event)
        event="$2"; shift 2 ;;
      --level)
        level="$2"; shift 2 ;;
      --title)
        title="$2"; shift 2 ;;
      --message)
        message="$2"; shift 2 ;;
      --channel)
        channel="$2"; shift 2 ;;
      --silent)
        silent="true"; shift ;;
      --help|-h)
        usage ;;
      *)
        echo "未知参数: $1"
        usage ;;
    esac
  done

  # 如果指定了 --event，使用预定义模板
  if [ -n "$event" ]; then
    dispatch_event "$event" "${message:-}"
  fi

  # 验证必选参数
  if [ -z "$level" ] || [ -z "$title" ]; then
    echo "错误: --level 和 --title 为必选参数"
    usage
  fi

  # 验证 level 值
  case "$level" in
    critical|warning|info) ;;
    *)
      echo "错误: --level 必须为 critical | warning | info"
      exit 1 ;;
  esac

  # 验证 channel 值
  case "$channel" in
    default|bridge) ;;
    *)
      echo "错误: --channel 必须为 default | bridge"
      exit 1 ;;
  esac

  load_env

  # 格式化消息文本
  local formatted
  formatted=$(format_message "$level" "$title" "${message:-无详情}")

  # 记录日志（所有级别都记录）
  log_notify "$level" "$channel" "$title" "${message:-无详情}"

  # info 级别仅记录日志，不推送
  if [ "$level" = "info" ]; then
    echo "[ops-notify] INFO 级别，已记录日志: $title"
    return 0
  fi

  # 确定目标 Chat ID
  local chat_id=""
  if [ "$channel" = "bridge" ]; then
    chat_id="${TELEGRAM_BRIDGE_CHAT_ID:-}"
    if [ -z "$chat_id" ]; then
      echo "[ops-notify] WARN: TELEGRAM_BRIDGE_CHAT_ID 未配置，回退到主频道" >> "$NOTIFY_LOG"
      chat_id="${TELEGRAM_CHAT_ID:-}"
    fi
  else
    chat_id="${TELEGRAM_CHAT_ID:-}"
  fi

  if [ -z "$chat_id" ]; then
    echo "[ops-notify] ERROR: 无可用 Chat ID，无法发送通知" >> "$NOTIFY_LOG"
    return 1
  fi

  # warning 级别强制静默
  if [ "$level" = "warning" ]; then
    silent="true"
  fi

  # 发送通知
  if send_telegram "$chat_id" "$formatted" "$silent"; then
    echo "[ops-notify] 通知已发送: [$level] $title → chat=$chat_id"
    return 0
  else
    echo "[ops-notify] 通知发送失败: [$level] $title"
    return 1
  fi
}

main "$@"
