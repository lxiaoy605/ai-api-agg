#!/bin/bash
# usdt-reconcile.sh — USDT TRC-20 自动对账脚本
# 对比 TronGrid 链上交易 vs 本地 payment_log 数据库
# 日终运行（cron: 0 23 * * *）
#
# 用法:
#   ./usdt-reconcile.sh           # 对账最近 24 小时
#   ./usdt-reconcile.sh 7         # 对账最近 7 天
#   ./usdt-reconcile.sh 30        # 对账最近 30 天

set -euo pipefail

# ===== 配置 =====
WALLET_ADDR="${USDT_TRC20_WALLET:-TFdzo1emymQeSB9s5su3vZg4zNBYpFR7fS}"
TRONGRID_KEY="${TRON_PRO_API_KEY:-}"
DB_PATH="${USDT_DB_PATH:-../backend/data/app.db}"
DAYS="${1:-1}"
TG_BOT="${TELEGRAM_BOT_TOKEN:-}"
TG_CHAT="${TELEGRAM_CHAT_ID:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

ONCHAIN_FILE="$TEMP_DIR/onchain.json"
LOCAL_FILE="$TEMP_DIR/local.txt"
REPORT_FILE="$TEMP_DIR/report.txt"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# ===== 拉取链上交易 =====
fetch_onchain() {
    local since_ms
    since_ms=$(($(date -d "$DAYS days ago" +%s) * 1000))

    log "拉取 TronGrid 交易记录 (${DAYS}天内)..."
    local url="https://api.trongrid.io/v1/accounts/${WALLET_ADDR}/transactions/trc20?limit=200&only_confirmed=true&min_timestamp=${since_ms}"

    local headers=(-H "Accept: application/json")
    if [ -n "$TRONGRID_KEY" ]; then
        headers+=(-H "TRON-PRO-API-KEY: $TRONGRID_KEY")
    fi

    curl -s "${headers[@]}" "$url" | jq '[.data[] | {
        tx_hash: .transaction_id,
        from: .from,
        to: .to,
        value_usdt: ((.value | tonumber) / 1000000),
        symbol: .token_info.symbol,
        block_ts: .block_timestamp
    } | select(.symbol == "USDT" and (.to | ascii_downcase) == ("'"$WALLET_ADDR"'" | ascii_downcase))]' \
        > "$ONCHAIN_FILE" 2>/dev/null

    local count
    count=$(jq 'length' "$ONCHAIN_FILE" 2>/dev/null || echo 0)
    log "链上 USDT 转入: ${count} 笔"
    echo "$count"
}

# ===== 查询本地记录 =====
fetch_local() {
    local since_ts
    since_ts=$(date -d "$DAYS days ago" +%s)

    log "查询本地 payment_log (${DAYS}天内)..."
    sqlite3 "$DB_PATH" <<EOF
.mode csv
.headers off
SELECT tx_hash, user_id, amount_cents, status, completed_at
FROM payment_log
WHERE provider = 'usdt_trc20' AND created_at >= $since_ts
ORDER BY created_at DESC;
EOF
    > "$LOCAL_FILE"

    local count
    count=$(wc -l < "$LOCAL_FILE" 2>/dev/null || echo 0)
    log "本地 USDT 记录: ${count} 笔"
    echo "$count"
}

# ===== 对账 =====
reconcile() {
    local onchain_count=$1
    local local_count=$2

    {
        echo "=========================================="
        echo "  USDT TRC-20 对账报告"
        echo "  日期: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "  钱包: $WALLET_ADDR"
        echo "  范围: 最近 ${DAYS} 天"
        echo "=========================================="
        echo ""
        echo "链上 USDT 转入: ${onchain_count} 笔"
        echo "本地已记录:     ${local_count} 笔"
        echo ""

        # 差异分析: 链上有但本地没有的
        local missing=0
        if [ "$onchain_count" -gt 0 ] && [ -s "$ONCHAIN_FILE" ]; then
            echo "--- 链上存在但本地缺失 ---"
            jq -r '.[] | .tx_hash' "$ONCHAIN_FILE" 2>/dev/null | while read -r tx; do
                if ! grep -q "$tx" "$LOCAL_FILE" 2>/dev/null; then
                    local detail
                    detail=$(jq -r --arg tx "$tx" '.[] | select(.tx_hash == $tx) | "  \(.tx_hash) | \(.from) → \(.to) | $\(.value_usdt) USDT"' "$ONCHAIN_FILE" 2>/dev/null)
                    echo "缺失: $detail"
                    missing=$((missing + 1))
                fi
            done
            echo ""
        fi

        # 状态异常的记录
        echo "--- 状态异常记录 ---"
        sqlite3 "$DB_PATH" <<EOF
.mode column
.headers on
SELECT id, user_id, tx_hash, amount_cents, status, datetime(created_at, 'unixepoch') as created
FROM payment_log
WHERE provider = 'usdt_trc20' AND status != 'completed'
ORDER BY created_at DESC
LIMIT 20;
EOF
        echo ""

        # 汇总统计
        echo "--- 汇总统计 ---"
        sqlite3 "$DB_PATH" <<EOF
.mode column
.headers on
SELECT
    COUNT(*) as total,
    COALESCE(SUM(CASE WHEN status='completed' THEN amount_cents ELSE 0 END)/100.0, 0) as completed_usd,
    COALESCE(SUM(CASE WHEN status='pending' THEN amount_cents ELSE 0 END)/100.0, 0) as pending_usd,
    COALESCE(SUM(tokens), 0) as total_tokens,
    COALESCE(SUM(bonus), 0) as total_bonus
FROM payment_log
WHERE provider = 'usdt_trc20' AND created_at >= $since_ts;
EOF
        echo ""
        echo "=========================================="
        echo "  对账完成: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "=========================================="
    } > "$REPORT_FILE" 2>/dev/null

    cat "$REPORT_FILE"
}

# ===== Telegram 通知 =====
notify_tg() {
    if [ -z "$TG_BOT" ] || [ -z "$TG_CHAT" ]; then
        return 0
    fi
    local report_summary
    report_summary=$(head -20 "$REPORT_FILE")
    curl -s -X POST "https://api.telegram.org/bot${TG_BOT}/sendMessage" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg text "📊 USDT 对账报告 ($DAYS天)\n\`\`\`\n$report_summary\n\`\`\`" '{chat_id: $ENV.TG_CHAT, text: $text, parse_mode: "HTML"}')" \
        > /dev/null 2>&1 || true
}

# ===== 主流程 =====
log "开始 USDT 对账 (${DAYS}天)..."
onchain_count=$(fetch_onchain)
local_count=$(fetch_local)
reconcile "$onchain_count" "$local_count"
notify_tg

# 保存报告
REPORT_ARCHIVE="$PROJECT_DIR/logs/usdt-reconcile-$(date +%Y%m%d).txt"
mkdir -p "$PROJECT_DIR/logs"
cp "$REPORT_FILE" "$REPORT_ARCHIVE"
log "报告已保存到 $REPORT_ARCHIVE"
