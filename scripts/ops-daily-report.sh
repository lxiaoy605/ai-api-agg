#!/usr/bin/env bash
# ============================================================
# ops-daily-report.sh — AI API 聚合平台每日运维摘要
# ============================================================
# 汇总过去 24h 的运维数据，通过 ops-notify.sh 推送
# 定时：每天早上 9:00（由 systemd timer 或 cron 触发）
#
# 汇总内容：
#   - 请求量 / 错误数（从 OneAPI 日志或 healthcheck 日志推算）
#   - 渠道健康状态（从 failover.state 读取）
#   - 余额变动（从 balance-monitor 日志读取）
#   - 备份状态（从 backup 日志读取）
#   - ops-notify 事件统计（从 ops-notify.log 读取）
#
# 用法：
#   ./ops-daily-report.sh                  # 标准模式（推送 + 记录日志）
#   ./ops-daily-report.sh --dry-run         # 仅输出到终端，不推送
#   ./ops-daily-report.sh --date 2026-05-27 # 指定日期（默认昨天）
# ============================================================

set -euo pipefail

# ---------- 路径 ----------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_DIR/logs"
NOTIFY_SCRIPT="$SCRIPT_DIR/ops-notify.sh"

# 日志文件
OPS_LOG="$LOG_DIR/ops-notify.log"
HEALTH_LOG="$LOG_DIR/healthcheck.log"
FAILOVER_LOG="$LOG_DIR/failover.log"
BALANCE_LOG="$LOG_DIR/balance-monitor.log"
STATE_FILE="$LOG_DIR/failover.state"
BACKUP_LOG="$PROJECT_DIR/backups/backup.log"

# ---------- 参数 ----------
DRY_RUN=false
REPORT_DATE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --date) REPORT_DATE="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [ -z "$REPORT_DATE" ]; then
  REPORT_DATE=$(date -d "yesterday" '+%Y-%m-%d' 2>/dev/null || date -v-1d '+%Y-%m-%d' 2>/dev/null || echo "")
fi

# ---------- 工具函数 ----------

# 统计日志文件中某日期的行数
count_date_lines() {
  local file="$1" date_str="$2"
  if [ -f "$file" ]; then
    grep -c "$date_str" "$file" 2>/dev/null || echo "0"
  else
    echo "N/A"
  fi
}

# 统计 ops-notify 日志中某级别的事件数
count_level() {
  local level="$1" date_str="$2"
  if [ -f "$OPS_LOG" ]; then
    grep "$date_str" "$OPS_LOG" 2>/dev/null | grep -c "\[$level\]" 2>/dev/null || echo "0"
  else
    echo "0"
  fi
}

# 获取最近备份状态
get_backup_status() {
  if [ -f "$BACKUP_LOG" ]; then
    local last_backup
    last_backup=$(grep "备份完成" "$BACKUP_LOG" 2>/dev/null | tail -1 || echo "")
    if [ -n "$last_backup" ]; then
      echo "$last_backup"
    else
      echo "无最近备份记录"
    fi
  else
    echo "备份日志不存在"
  fi
}

# 获取渠道健康状态
get_channel_health() {
  if [ -f "$STATE_FILE" ]; then
    local lines=""
    while IFS='|' read -r name weight failures status last_update; do
      [[ "$name" =~ ^# ]] && continue
      [ -z "$name" ] && continue
      local icon="✅"
      [ "$status" = "DOWN" ] && icon="❌"
      lines+="${icon} ${name}: ${status} (失败${failures}次)"$'\n'
    done < "$STATE_FILE"
    echo "$lines"
  else
    echo "状态文件不存在（failover 未初始化）"
  fi
}

# 获取余额状态
get_balance_status() {
  if [ -f "$BALANCE_LOG" ]; then
    local last_run
    last_run=$(grep "$REPORT_DATE" "$BALANCE_LOG" 2>/dev/null | grep "汇总:" | tail -1 || echo "")
    if [ -n "$last_run" ]; then
      echo "$last_run"
    else
      echo "今日无余额检查记录"
    fi
  else
    echo "余额监控日志不存在"
  fi
}

# ---------- 生成报告 ----------
generate_report() {
  local date_display="$REPORT_DATE"
  local today
  today=$(date '+%Y-%m-%d')

  cat <<REPORT
📊 *AI API 聚合平台 — 每日运维摘要*
📅 ${date_display}

━━━━━━━━━━━━━━━━━━━━
📈 *事件统计*
━━━━━━━━━━━━━━━━━━━━
🔴 严重事件: $(count_level "critical" "$REPORT_DATE") 条
🟡 警告事件: $(count_level "warning" "$REPORT_DATE") 条
🔵 信息事件: $(count_level "info" "$REPORT_DATE") 条

━━━━━━━━━━━━━━━━━━━━
🏥 *渠道健康*
━━━━━━━━━━━━━━━━━━━━
$(get_channel_health)

━━━━━━━━━━━━━━━━━━━━
💰 *余额监控*
━━━━━━━━━━━━━━━━━━━━
$(get_balance_status)

━━━━━━━━━━━━━━━━━━━━
💾 *备份状态*
━━━━━━━━━━━━━━━━━━━━
$(get_backup_status)

━━━━━━━━━━━━━━━━━━━━
🕐 报告生成时间: $(date '+%Y-%m-%d %H:%M:%S')
REPORT
}

# ---------- 主流程 ----------
main() {
  local report
  report=$(generate_report)

  if $DRY_RUN; then
    echo "$report"
    echo ""
    echo "[DRY-RUN] 以上为预览，未实际推送"
    return 0
  fi

  # 通过 ops-notify.sh 推送（warning 级别静默推送，不打扰但确保送达）
  "$NOTIFY_SCRIPT" \
    --level warning \
    --title "每日运维摘要 — $REPORT_DATE" \
    --message "$report" \
    --silent

  echo "[ops-daily-report] 每日摘要已推送"
}

main
