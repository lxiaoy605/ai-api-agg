#!/usr/bin/env bash
# ============================================================
# AI API 聚合平台 — 支付对账脚本
# ============================================================
# 功能：
#   1. 按日对账（默认昨天，--date YYYY-MM-DD 指定日期）
#   2. Stripe 对账：API balance_transactions vs 本地 payment_log
#   3. USDT 对账：TronGrid API vs 本地 payment_log
#   4. 输出格式化对账报告 / JSON 报告
#   5. 不一致时红色标记 + Telegram 告警
#
# 用法：
#   ./reconcile-payments.sh                     # 对账昨天
#   ./reconcile-payments.sh --date 2026-05-27   # 对账指定日期
#   ./reconcile-payments.sh --json              # JSON 输出
#
# 环境变量：
#   STRIPE_SECRET       Stripe Secret Key（未配则跳过 Stripe）
#   TRON_PRO_API_KEY    TronGrid API Key（未配则跳过 USDT 链上查询）
#   USDT_WALLET         USDT TRC-20 收款地址
#   DATABASE_PATH       SQLite 数据库路径
#   TELEGRAM_BOT_TOKEN  Telegram Bot Token（告警用）
#   TELEGRAM_CHAT_ID    Telegram Chat ID（告警用）
# ============================================================

set -euo pipefail

# ---------- 路径配置 ----------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_DIR/logs"
LOG_FILE="$LOG_DIR/reconcile.log"
ENV_FILE="$PROJECT_DIR/docker/.env"

mkdir -p "$LOG_DIR"

# ---------- 颜色 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ---------- 默认值 ----------
OUTPUT_JSON=false
TARGET_DATE=""
DB_PATH="${DATABASE_PATH:-$PROJECT_DIR/backend/user-auth.db}"

# USDT TRC-20 合约地址（主网）
USDT_CONTRACT="TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"

# ---------- 工具函数 ----------

log_msg() {
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] $*" >> "$LOG_FILE"
}

load_env() {
  if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE" 2>/dev/null || true
    set +a
  fi
}

NOTIFY_SCRIPT="$SCRIPT_DIR/ops-notify.sh"

send_notify() {
  local level="$1" title="$2" message="$3"
  if [ -x "$NOTIFY_SCRIPT" ]; then
    "$NOTIFY_SCRIPT" --level "$level" --title "$title" --message "$message" --silent || true
  else
    log_msg "ops-notify.sh 不可执行，跳过通知"
  fi
}

date_to_unix() {
  local d="$1" time="$2"
  date -d "${d} ${time}" +%s 2>/dev/null || date -d "${d}T${time}" +%s 2>/dev/null || echo "0"
}

cents_to_usd() {
  local cents="${1:-0}"
  python3 -c "print(f'{int($cents)/100:.2f}')" 2>/dev/null || echo "0.00"
}

# ---------- 本地数据库查询 ----------
# 输出格式: count|amount_usd

query_local() {
  local provider="$1" date_str="$2"

  local table_exists
  table_exists=$(sqlite3 "$DB_PATH" \
    "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='payment_log';" 2>/dev/null || echo "0")

  if [ "$table_exists" = "0" ]; then
    echo "0|0.00"
    return
  fi

  local result
  result=$(sqlite3 "$DB_PATH" \
    "SELECT COUNT(*), COALESCE(SUM(amount_cents), 0) FROM payment_log
     WHERE provider='$provider' AND status='completed'
     AND date(created_at, 'unixepoch') = '$date_str';" 2>/dev/null || echo "0|0")

  local count="${result%%|*}"
  local cents="${result##*|}"
  local usd
  usd=$(cents_to_usd "${cents:-0}")

  echo "${count:-0}|${usd}"
}

# ---------- JSON 解析工具（用 Python 代替 jq） ----------

# 解析 Stripe balance_transactions 响应
# 输出: count|amount_cents
parse_stripe_balance() {
  python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    charges = [t for t in data.get('data', []) if t.get('type') == 'charge']
    total = sum(t.get('amount', 0) for t in charges)
    print(f'{len(charges)}|{total}')
except Exception as e:
    print(f'0|0|{e}')
"
}

# 解析 TronGrid TRC-20 交易响应
# 输出: count|raw_value_sum
parse_trongrid_transfers() {
  local wallet="$1"
  python3 -c "
import json, sys
wallet = '$wallet'
try:
    data = json.load(sys.stdin)
    transfers = [t for t in data.get('data', [])
                 if t.get('to') == wallet and t.get('type') == 'Transfer']
    total = sum(int(t.get('value', 0)) for t in transfers)
    print(f'{len(transfers)}|{total}')
except Exception as e:
    print(f'0|0|{e}')
"
}

# ---------- Stripe API 查询 ----------
# 输出格式: status|count|amount_usd[|error_msg]

query_stripe_api() {
  local start_ts="$1" end_ts="$2"
  local stripe_key="${STRIPE_SECRET:-}"

  if [ -z "$stripe_key" ]; then
    echo "N/A|0|0.00"
    return
  fi

  local resp
  resp=$(curl -s -u "${stripe_key}:" \
    --max-time 30 \
    "https://api.stripe.com/v1/balance_transactions?created[gte]=${start_ts}&created[lte]=${end_ts}&type=charge&limit=100" 2>/dev/null || true)

  if [ -z "$resp" ]; then
    echo "ERROR|0|0.00|curl 请求失败"
    return
  fi

  # 检查是否为 Stripe 错误响应
  if echo "$resp" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if 'error' in d else 1)" 2>/dev/null; then
    local err_msg
    err_msg=$(echo "$resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('error',{}).get('message','unknown'))" 2>/dev/null || echo "unknown")
    echo "ERROR|0|0.00|${err_msg}"
    return
  fi

  local parsed
  parsed=$(echo "$resp" | parse_stripe_balance 2>/dev/null || echo "0|0")
  local count="${parsed%%|*}"
  local amount_cents="${parsed##*|}"

  local usd
  usd=$(cents_to_usd "${amount_cents:-0}")

  echo "OK|${count}|${usd}"
}

# ---------- TronGrid API 查询 ----------
# 输出格式: status|count|amount_usd[|error_msg]

query_trongrid_api() {
  local start_ms="$1" end_ms="$2"
  local tron_key="${TRON_PRO_API_KEY:-}"
  local wallet="${USDT_WALLET:-}"

  if [ -z "$tron_key" ] || [ -z "$wallet" ]; then
    echo "N/A|0|0.00"
    return
  fi

  local url="https://api.trongrid.io/v1/accounts/${wallet}/transactions/trc20"
  url="${url}?limit=200"
  url="${url}&order_by=block_timestamp,desc"
  url="${url}&min_timestamp=${start_ms}"
  url="${url}&max_timestamp=${end_ms}"
  url="${url}&contract_address=${USDT_CONTRACT}"

  local resp
  resp=$(curl -s --max-time 30 \
    -H "TRON-PRO-API-KEY: ${tron_key}" \
    -H "Accept: application/json" \
    "$url" 2>/dev/null || true)

  if [ -z "$resp" ]; then
    echo "ERROR|0|0.00|curl 请求失败"
    return
  fi

  # 检查是否为错误响应
  if echo "$resp" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if 'error' in d else 1)" 2>/dev/null; then
    local err_msg
    err_msg=$(echo "$resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('error','unknown'))" 2>/dev/null || echo "unknown")
    echo "ERROR|0|0.00|${err_msg}"
    return
  fi

  local parsed
  parsed=$(echo "$resp" | parse_trongrid_transfers "$wallet" 2>/dev/null || echo "0|0")
  local count="${parsed%%|*}"
  local raw_value="${parsed##*|}"

  # USDT TRC-20 有 6 位小数
  local usd
  usd=$(python3 -c "print(f'{int(${raw_value:-0})/1000000:.2f}')" 2>/dev/null || echo "0.00")

  echo "OK|${count}|${usd}"
}

# ---------- 文本报告输出 ----------

print_text_report() {
  local date_str="$1"
  local s_status="$2" s_api_count="$3" s_api_amt="$4" s_local_count="$5" s_local_amt="$6"
  local u_status="$7" u_api_count="$8" u_api_amt="$9" u_local_count="${10}" u_local_amt="${11}"

  echo ""
  echo "============================================"
  echo "  支付对账报告 — $date_str"
  echo "============================================"
  echo ""

  # --- Stripe 行 ---
  case "$s_status" in
    "N/A")
      echo -e " Stripe:  ${YELLOW}N/A（未配置 STRIPE_SECRET）${NC}"
      ;;
    "ERROR")
      echo -e " Stripe:  ${RED}API 查询失败${NC}"
      ;;
    "OK")
      local s_ok=true s_diff_count=0 s_diff_amt="0.00"
      if [ "$s_api_count" != "$s_local_count" ]; then
        s_ok=false
        s_diff_count=$((s_api_count - s_local_count))
      fi
      s_diff_amt=$(python3 -c "print(f'{float($s_api_amt) - float($s_local_amt):.2f}')" 2>/dev/null || echo "0.00")
      if [ "$s_diff_amt" != "0.00" ] && [ "$s_diff_amt" != "-0.00" ]; then
        s_ok=false
      fi

      if $s_ok; then
        echo -e " Stripe:  API ${s_api_count}笔/\$${s_api_amt} | 本地 ${s_local_count}笔/\$${s_local_amt} | 差异 0 ${GREEN}✅${NC}"
      else
        echo -e " Stripe:  API ${s_api_count}笔/\$${s_api_amt} | 本地 ${s_local_count}笔/\$${s_local_amt} | ${RED}差异 ${s_diff_count}笔/\$${s_diff_amt} ❌${NC}"
      fi
      ;;
  esac

  # --- USDT 行 ---
  case "$u_status" in
    "N/A")
      echo -e " USDT:   ${YELLOW}N/A（未配置 TRON_PRO_API_KEY/USDT_WALLET）${NC}"
      ;;
    "ERROR")
      echo -e " USDT:   ${RED}TronGrid API 查询失败${NC}"
      ;;
    "OK")
      local u_ok=true u_diff_count=0 u_diff_amt="0.00"
      if [ "$u_api_count" != "$u_local_count" ]; then
        u_ok=false
        u_diff_count=$((u_api_count - u_local_count))
      fi
      u_diff_amt=$(python3 -c "print(f'{float($u_api_amt) - float($u_local_amt):.2f}')" 2>/dev/null || echo "0.00")
      if [ "$u_diff_amt" != "0.00" ] && [ "$u_diff_amt" != "-0.00" ]; then
        u_ok=false
      fi

      if $u_ok; then
        echo -e " USDT:   链上 ${u_api_count}笔/\$${u_api_amt} | 本地 ${u_local_count}笔/\$${u_local_amt} | 差异 0 ${GREEN}✅${NC}"
      else
        echo -e " USDT:   链上 ${u_api_count}笔/\$${u_api_amt} | 本地 ${u_local_count}笔/\$${u_local_amt} | ${RED}差异 ${u_diff_count}笔/\$${u_diff_amt} ❌${NC}"
      fi
      ;;
  esac

  echo ""
  echo "────────────────────────────────────────────"

  # 未入账统计
  local missing_stripe=0 missing_usdt=0
  if [ "$s_status" = "OK" ] && [ "$s_api_count" -gt "$s_local_count" ]; then
    missing_stripe=$((s_api_count - s_local_count))
  fi
  if [ "$u_status" = "OK" ] && [ "$u_api_count" -gt "$u_local_count" ]; then
    missing_usdt=$((u_api_count - u_local_count))
  fi

  # 未到账统计（本地有但 API 没有）
  local over_stripe=0 over_usdt=0
  if [ "$s_status" = "OK" ] && [ "$s_local_count" -gt "$s_api_count" ]; then
    over_stripe=$((s_local_count - s_api_count))
  fi
  if [ "$u_status" = "OK" ] && [ "$u_local_count" -gt "$u_api_count" ]; then
    over_usdt=$((u_local_count - u_api_count))
  fi

  echo -e " 未入账交易: $((missing_stripe + missing_usdt)) 笔"
  echo -e " 未到账支付: $((over_stripe + over_usdt)) 笔"
  echo "============================================"
  echo ""
}

# ---------- JSON 报告输出 ----------

print_json_report() {
  local date_str="$1"
  local s_status="$2" s_api_count="$3" s_api_amt="$4" s_local_count="$5" s_local_amt="$6"
  local u_status="$7" u_api_count="$8" u_api_amt="$9" u_local_count="${10}" u_local_amt="${11}"

  python3 -c "
import json
from datetime import datetime, timezone

s_ok = True
s_diff_count = int($s_api_count) - int($s_local_count)
s_diff_amt = round(float($s_api_amt) - float($s_local_amt), 2)
if s_diff_count != 0 or s_diff_amt != 0.0:
    s_ok = False

u_ok = True
u_diff_count = int($u_api_count) - int($u_local_count)
u_diff_amt = round(float($u_api_amt) - float($u_local_amt), 2)
if u_diff_count != 0 or u_diff_amt != 0.0:
    u_ok = False

missing = 0
over = 0
if '$s_status' == 'OK':
    if int($s_api_count) > int($s_local_count):
        missing += int($s_api_count) - int($s_local_count)
    if int($s_local_count) > int($s_api_count):
        over += int($s_local_count) - int($s_api_count)
if '$u_status' == 'OK':
    if int($u_api_count) > int($u_local_count):
        missing += int($u_api_count) - int($u_local_count)
    if int($u_local_count) > int($u_api_count):
        over += int($u_local_count) - int($u_api_count)

report = {
    'date': '$date_str',
    'generated_at': datetime.now(timezone.utc).isoformat(),
    'stripe': {
        'status': '$s_status',
        'api': {'count': int($s_api_count), 'amount_usd': '$s_api_amt'},
        'local': {'count': int($s_local_count), 'amount_usd': '$s_local_amt'},
        'diff': {'count': s_diff_count, 'amount_usd': f'{s_diff_amt:.2f}'},
        'match': s_ok
    },
    'usdt': {
        'status': '$u_status',
        'api': {'count': int($u_api_count), 'amount_usd': '$u_api_amt'},
        'local': {'count': int($u_local_count), 'amount_usd': '$u_local_amt'},
        'diff': {'count': u_diff_count, 'amount_usd': f'{u_diff_amt:.2f}'},
        'match': u_ok
    },
    'summary': {
        'missing_from_local': missing,
        'extra_in_local': over
    }
}
print(json.dumps(report, ensure_ascii=False, indent=2))
"
}

# ---------- 差异检测 ----------

has_discrepancy() {
  local status="$1" api_count="$2" api_amt="$3" local_count="$4" local_amt="$5"

  if [ "$status" = "ERROR" ]; then
    return 0
  fi
  if [ "$status" != "OK" ]; then
    return 1
  fi

  if [ "$api_count" != "$local_count" ]; then
    return 0
  fi

  local diff
  diff=$(python3 -c "print(f'{float($api_amt) - float($local_amt):.2f}')" 2>/dev/null || echo "0.00")
  if [ "$diff" != "0.00" ] && [ "$diff" != "-0.00" ]; then
    return 0
  fi

  return 1
}

# ---------- Telegram 告警 ----------

send_alert_if_needed() {
  local date_str="$1"
  local s_status="$2" s_api_count="$3" s_api_amt="$4" s_local_count="$5" s_local_amt="$6"
  local u_status="$7" u_api_count="$8" u_api_amt="$9" u_local_count="${10}" u_local_amt="${11}"

  local s_issue=false u_issue=false
  if has_discrepancy "$s_status" "$s_api_count" "$s_api_amt" "$s_local_count" "$s_local_amt"; then
    s_issue=true
  fi
  if has_discrepancy "$u_status" "$u_api_count" "$u_api_amt" "$u_local_count" "$u_local_amt"; then
    u_issue=true
  fi

  if ! $s_issue && ! $u_issue; then
    log_msg "对账完成，无差异"
    return 0
  fi

  local msg="⚠️ 支付对账异常 — ${date_str}"

  if $s_issue; then
    if [ "$s_status" = "ERROR" ]; then
      msg+="\n\nStripe: API 查询失败"
    elif [ "$s_status" = "OK" ]; then
      local sd_count=$((s_api_count - s_local_count))
      local sd_amt
      sd_amt=$(python3 -c "print(f'{float($s_api_amt) - float($s_local_amt):.2f}')")
      msg+="\n\nStripe 差异:"
      msg+="\n  API: ${s_api_count}笔 / \$${s_api_amt}"
      msg+="\n  本地: ${s_local_count}笔 / \$${s_local_amt}"
      msg+="\n  差异: ${sd_count}笔 / \$${sd_amt}"
    fi
  fi

  if $u_issue; then
    if [ "$u_status" = "ERROR" ]; then
      msg+="\n\nUSDT: TronGrid API 查询失败"
    elif [ "$u_status" = "OK" ]; then
      local ud_count=$((u_api_count - u_local_count))
      local ud_amt
      ud_amt=$(python3 -c "print(f'{float($u_api_amt) - float($u_local_amt):.2f}')")
      msg+="\n\nUSDT 差异:"
      msg+="\n  链上: ${u_api_count}笔 / \$${u_api_amt}"
      msg+="\n  本地: ${u_local_count}笔 / \$${u_local_amt}"
      msg+="\n  差异: ${ud_count}笔 / \$${ud_amt}"
    fi
  fi

  send_notify "critical" "支付对账异常" "$msg"
  log_msg "发现对账差异，已发送运维通知"
}

# ============================================================
# 主流程
# ============================================================

main() {
  # 解析参数
  while [ $# -gt 0 ]; do
    case "$1" in
      --json)
        OUTPUT_JSON=true
        ;;
      --date)
        TARGET_DATE="$2"
        shift
        ;;
      *)
        ;;
    esac
    shift
  done

  load_env

  # 确定对账日期（默认昨天）
  if [ -z "$TARGET_DATE" ]; then
    TARGET_DATE=$(date -d "yesterday" +%Y-%m-%d 2>/dev/null || date -d "-1 day" +%Y-%m-%d)
  fi

  # 计算时间范围
  local start_ts end_ts start_ms end_ms
  start_ts=$(date_to_unix "$TARGET_DATE" "00:00:00")
  end_ts=$(date_to_unix "$TARGET_DATE" "23:59:59")
  start_ms=$((start_ts * 1000))
  end_ms=$((end_ts * 1000))

  # 数据库路径覆盖
  if [ -n "${DATABASE_PATH:-}" ]; then
    DB_PATH="$DATABASE_PATH"
  fi

  log_msg "========== 开始对账: $TARGET_DATE =========="

  # --- 查询所有数据 ---
  local stripe_data local_data_s usdt_data local_data_u
  stripe_data=$(query_stripe_api "$start_ts" "$end_ts")
  local_data_s=$(query_local "stripe" "$TARGET_DATE")
  usdt_data=$(query_trongrid_api "$start_ms" "$end_ms")
  local_data_u=$(query_local "usdt" "$TARGET_DATE")

  # --- 解析数据 ---
  local s_status="${stripe_data%%|*}"; local s_rest="${stripe_data#*|}"
  local s_api_count="${s_rest%%|*}"; local s_api_amt="${s_rest##*|}"
  local s_local_count="${local_data_s%%|*}"; local s_local_amt="${local_data_s##*|}"

  local u_status="${usdt_data%%|*}"; local u_rest="${usdt_data#*|}"
  local u_api_count="${u_rest%%|*}"; local u_api_amt="${u_rest##*|}"
  local u_local_count="${local_data_u%%|*}"; local u_local_amt="${local_data_u##*|}"

  # --- 输出报告 ---
  if [ "$OUTPUT_JSON" = true ]; then
    print_json_report "$TARGET_DATE" \
      "$s_status" "$s_api_count" "$s_api_amt" "$s_local_count" "$s_local_amt" \
      "$u_status" "$u_api_count" "$u_api_amt" "$u_local_count" "$u_local_amt"
    log_msg "JSON 报告已生成"
  else
    print_text_report "$TARGET_DATE" \
      "$s_status" "$s_api_count" "$s_api_amt" "$s_local_count" "$s_local_amt" \
      "$u_status" "$u_api_count" "$u_api_amt" "$u_local_count" "$u_local_amt"

    # 发送 Telegram 告警
    send_alert_if_needed "$TARGET_DATE" \
      "$s_status" "$s_api_count" "$s_api_amt" "$s_local_count" "$s_local_amt" \
      "$u_status" "$u_api_count" "$u_api_amt" "$u_local_count" "$u_local_amt"
  fi
}

main "$@"
