#!/bin/bash
# ============================================================
# ai-api-agg 备份健康检查脚本
# ============================================================
# 功能：
#   1. 检查最近备份时间（> 25h 无备份 → 告警）
#   2. 检查备份文件完整性（SHA256 验证）
#   3. 检查远程备份可达性
#   4. 异常时 Telegram 通知
#
# 用法：
#   bash backup-health.sh                  # 标准检查
#   bash backup-health.sh --json           # JSON 输出（供监控系统使用）
#   bash backup-health.sh --no-telegram    # 跳过 Telegram 通知
#   bash backup-health.sh --quick          # 快速模式（仅时间检查，跳过校验）
#
# 环境变量：
#   BACKUP_ALERT_HOURS           告警阈值（小时，默认 25）
#   REMOTE_BACKUP_HOST           远程备份主机
#   REMOTE_BACKUP_PATH           远程备份路径
#   TELEGRAM_BOT_TOKEN           Telegram Bot Token
#   TELEGRAM_CHAT_ID             Telegram Chat ID
# ============================================================

set -euo pipefail

# ---------- 路径配置 ----------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$PROJECT_DIR/backups"
LOG_FILE="$BACKUP_DIR/health-check.log"
MANIFEST_FILE="$BACKUP_DIR/manifest.json"

mkdir -p "$BACKUP_DIR"

# ---------- 默认值 ----------
ALERT_HOURS="${BACKUP_ALERT_HOURS:-25}"
OUTPUT_MODE="text"
SKIP_TELEGRAM=false
QUICK_MODE=false

# ---------- 参数解析 ----------
while [ $# -gt 0 ]; do
    case "$1" in
        --json)
            OUTPUT_MODE="json"
            ;;
        --no-telegram)
            SKIP_TELEGRAM=true
            ;;
        --quick)
            QUICK_MODE=true
            ;;
        *)
            echo "未知参数: $1"
            echo "用法: $0 [--json] [--no-telegram] [--quick]"
            exit 1
            ;;
    esac
    shift
done

# ---------- 日志函数 ----------
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# ---------- 颜色 ----------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# ---------- Telegram 通知 ----------
NOTIFY_SCRIPT="${SCRIPT_DIR:-$(dirname "$0")}/ops-notify.sh"

tg_notify() {
    local message="$1"

    if [ "${SKIP_TELEGRAM:-false}" = true ]; then
        return 0
    fi

    # 根据消息内容推断级别
    local level="warning"
    if echo "$message" | grep -qi "emergency\|critical\|danger\|crash\|panic"; then
        level="critical"
    fi

    if [ -x "$NOTIFY_SCRIPT" ]; then
        "$NOTIFY_SCRIPT" --level "$level" --title "备份健康告警" --message "$message" --silent || true
    fi
}

# ---------- 结果收集 ----------
ISSUES=()
WARNINGS=()
OK_CHECKS=()

add_issue() {
    ISSUES+=("$1")
    if [ "$OUTPUT_MODE" = "text" ]; then
        echo -e "  ${RED}✗${NC} $1"
    fi
}

add_warning() {
    WARNINGS+=("$1")
    if [ "$OUTPUT_MODE" = "text" ]; then
        echo -e "  ${YELLOW}⚠${NC} $1"
    fi
}

add_ok() {
    OK_CHECKS+=("$1")
    if [ "$OUTPUT_MODE" = "text" ]; then
        echo -e "  ${GREEN}✓${NC} $1"
    fi
}

# ============================================================
# 检查 1: 最近备份时间
# ============================================================
check_recent_backup() {
    local now
    now=$(date +%s)
    local latest_ts=0
    local latest_name="无"

    if [ -f "$MANIFEST_FILE" ]; then
        # 从 manifest 中获取最新备份时间
        latest_ts=$(jq -r '[.backups[].timestamp] | max // 0' "$MANIFEST_FILE" 2>/dev/null || echo "0")
        latest_name=$(jq -r --arg ts "$latest_ts" \
            '.backups[] | select(.timestamp == ($ts | tonumber)) | .filename' \
            "$MANIFEST_FILE" 2>/dev/null | head -1 || echo "未知")
    fi

    # 如果 manifest 不可用，检查文件系统
    if [ "$latest_ts" = "0" ] || [ -z "$latest_ts" ]; then
        local latest_file
        latest_file=$(find "$BACKUP_DIR" -name "backup-*.tar.gz" -not -name "backup-latest.tar.gz" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 || echo "")
        if [ -n "$latest_file" ]; then
            latest_ts=$(echo "$latest_file" | awk '{print int($1)}')
            latest_name=$(basename "$(echo "$latest_file" | awk '{print $2}')")
        fi
    fi

    # 也检查 v2 子目录
    if [ "$latest_ts" = "0" ]; then
        for subdir in full incremental; do
            local f
            f=$(find "$BACKUP_DIR/$subdir" -name "backup-*.tar.gz" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 || echo "")
            if [ -n "$f" ]; then
                local sub_ts
                sub_ts=$(echo "$f" | awk '{print int($1)}')
                if [ "$sub_ts" -gt "$latest_ts" ]; then
                    latest_ts=$sub_ts
                    latest_name=$(basename "$(echo "$f" | awk '{print $2}')")
                fi
            fi
        done
    fi

    if [ "$latest_ts" = "0" ]; then
        add_issue "未找到任何备份文件"
        echo "0|无"
        return 1
    fi

    local hours_ago
    hours_ago=$(( (now - latest_ts) / 3600 ))

    local latest_time
    latest_time=$(date -d "@$latest_ts" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "未知")

    if [ "$hours_ago" -gt "$ALERT_HOURS" ]; then
        add_issue "最近备份 ${hours_ago} 小时前（阈值: ${ALERT_HOURS}h）\n         文件: $latest_name\n         时间: $latest_time"
        echo "$hours_ago|$latest_name|$latest_time"
        return 1
    elif [ "$hours_ago" -gt $((ALERT_HOURS * 2 / 3)) ]; then
        add_warning "最近备份 ${hours_ago} 小时前（接近告警阈值 ${ALERT_HOURS}h）\n         文件: $latest_name"
        echo "$hours_ago|$latest_name|$latest_time"
        return 0
    else
        add_ok "最近备份: ${hours_ago} 小时前 ($latest_name)"
        echo "$hours_ago|$latest_name|$latest_time"
        return 0
    fi
}

# ============================================================
# 检查 2: 备份文件完整性（SHA256）
# ============================================================
check_backup_integrity() {
    if [ "$QUICK_MODE" = true ]; then
        add_ok "SHA256 校验: 已跳过（快速模式）"
        return 0
    fi

    local total=0 ok=0 fail=0

    # 检查最新的 3 个备份
    local backups
    backups=$(jq -r '.backups | sort_by(.timestamp) | reverse | .[0:3][] | .filename' "$MANIFEST_FILE" 2>/dev/null || echo "")

    if [ -z "$backups" ]; then
        add_warning "manifest.json 中无备份记录，跳过 SHA256 校验"
        return 0
    fi

    while IFS= read -r filename; do
        [ -z "$filename" ] && continue
        total=$((total + 1))

        # 找到文件路径
        local file_path=""
        for subdir in full incremental ""; do
            local candidate
            if [ -n "$subdir" ]; then
                candidate="$BACKUP_DIR/$subdir/$filename"
            else
                candidate="$BACKUP_DIR/$filename"
            fi
            if [ -f "$candidate" ]; then
                file_path="$candidate"
                break
            fi
        done

        if [ -z "$file_path" ] || [ ! -f "$file_path" ]; then
            add_warning "备份文件不存在: $filename"
            fail=$((fail + 1))
            continue
        fi

        local sha256_file="${file_path}.sha256"
        if [ -f "$sha256_file" ]; then
            local expected actual
            expected=$(awk '{print $1}' "$sha256_file")
            actual=$(sha256sum "$file_path" | awk '{print $1}')
            if [ "$expected" = "$actual" ]; then
                ok=$((ok + 1))
            else
                add_issue "SHA256 校验失败: $filename"
                fail=$((fail + 1))
            fi
        else
            add_warning "无 .sha256 文件: $filename"
        fi
    done <<< "$backups"

    if [ $fail -eq 0 ] && [ $ok -gt 0 ]; then
        add_ok "SHA256 完整性校验: $ok/$total 通过"
    elif [ $total -eq 0 ]; then
        add_warning "无备份可供校验"
    fi

    return $fail
}

# ============================================================
# 检查 3: 远程备份可达性
# ============================================================
check_remote_accessibility() {
    local host="${REMOTE_BACKUP_HOST:-}"
    local path="${REMOTE_BACKUP_PATH:-}"

    if [ -z "$host" ]; then
        add_ok "远程备份: 未配置（仅本地备份模式）"
        return 0
    fi

    # 检查 SSH 连接
    if ssh -o ConnectTimeout=10 -o BatchMode=yes "$host" "echo ok" >/dev/null 2>&1; then
        # 检查备份路径是否存在
        if ssh -o ConnectTimeout=10 "$host" "test -d ${path}" 2>/dev/null; then
            # 检查路径内容是否可读
            local file_count
            file_count=$(ssh -o ConnectTimeout=10 "$host" "find ${path}/ -name 'backup-*.tar.gz' 2>/dev/null | wc -l" 2>/dev/null || echo "0")
            local disk_usage
            disk_usage=$(ssh -o ConnectTimeout=10 "$host" "du -sh ${path}/ 2>/dev/null | cut -f1" 2>/dev/null || echo "未知")

            add_ok "远程备份: $host:$path 可达 (${file_count} 个备份, ${disk_usage})"
        else
            add_issue "远程备份路径不存在: $host:$path"
            return 1
        fi

        # 检查远程 manifest
        if ssh -o ConnectTimeout=10 "$host" "test -f ${path}/manifest.json" 2>/dev/null; then
            local remote_latest
            remote_latest=$(ssh -o ConnectTimeout=10 "$host" \
                "jq -r '[.backups[].timestamp] | max // 0' ${path}/manifest.json" 2>/dev/null || echo "0")

            if [ "$remote_latest" != "0" ]; then
                local remote_time
                remote_time=$(date -d "@$remote_latest" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "未知")
                local remote_hours_ago
                remote_hours_ago=$(( ($(date +%s) - remote_latest) / 3600 ))

                if [ "$remote_hours_ago" -gt "$ALERT_HOURS" ]; then
                    add_warning "远程最新备份: ${remote_hours_ago} 小时前 ($remote_time)"
                else
                    add_ok "远程备份同步正常: ${remote_hours_ago} 小时前"
                fi
            fi
        fi
    else
        add_issue "远程备份主机不可达: $host"
        return 1
    fi

    return 0
}

# ============================================================
# 检查 4: 备份目录磁盘空间
# ============================================================
check_backup_disk_space() {
    local usage_pct
    usage_pct=$(df -h "$BACKUP_DIR" | tail -1 | awk '{print $5}' | sed 's/%//')

    if [ "$usage_pct" -gt 90 ]; then
        add_issue "磁盘使用率 ${usage_pct}%（备份目录所在分区空间不足）"
        return 1
    elif [ "$usage_pct" -gt 75 ]; then
        add_warning "磁盘使用率 ${usage_pct}%（建议清理旧备份）"
        return 0
    else
        add_ok "磁盘空间充足（使用率 ${usage_pct}%）"
        return 0
    fi
}

# ============================================================
# 检查 5: manifest.json 健康
# ============================================================
check_manifest_health() {
    if [ ! -f "$MANIFEST_FILE" ]; then
        add_warning "manifest.json 不存在（可能是首次运行）"
        return 0
    fi

    # 验证 JSON 格式
    if jq empty "$MANIFEST_FILE" 2>/dev/null; then
        local backup_count
        backup_count=$(jq '.backups | length' "$MANIFEST_FILE" 2>/dev/null || echo "0")
        add_ok "manifest.json 正常（$backup_count 条记录）"
    else
        add_issue "manifest.json 格式损坏"
        return 1
    fi

    return 0
}

# ============================================================
# 主流程
# ============================================================
main() {
    if [ "$OUTPUT_MODE" = "text" ]; then
        {
            echo ""
            echo "========================================="
            echo " 备份健康检查 — $(date '+%Y-%m-%d %H:%M:%S')"
            echo " 主机: $(hostname)"
            echo "========================================="
            echo ""
        } | tee "$LOG_FILE"
    fi

    local overall=0

    # 检查 1: 最近备份时间
    if [ "$OUTPUT_MODE" = "text" ]; then
        echo "── 最近备份时间 ──"
    fi
    local time_info
    time_info=$(check_recent_backup) || true
    local time_rc=$?
    local hours_ago
    hours_ago=$(echo "$time_info" | cut -d'|' -f1)
    local latest_name
    latest_name=$(echo "$time_info" | cut -d'|' -f2)
    local latest_time
    latest_time=$(echo "$time_info" | cut -d'|' -f3)

    # 检查 2: 完整性
    if [ "$OUTPUT_MODE" = "text" ]; then
        echo "── 备份完整性 ──"
    fi
    check_backup_integrity || overall=1

    # 检查 3: 远程可达性
    if [ "$OUTPUT_MODE" = "text" ]; then
        echo "── 远程备份可达性 ──"
    fi
    check_remote_accessibility || overall=1

    # 检查 4: 磁盘空间
    if [ "$OUTPUT_MODE" = "text" ]; then
        echo "── 磁盘空间 ──"
    fi
    check_backup_disk_space || true  # 磁盘告警不阻断

    # 检查 5: manifest 健康
    if [ "$OUTPUT_MODE" = "text" ]; then
        echo "── Manifest 健康 ──"
    fi
    check_manifest_health || true

    # ---------- 汇总 ----------
    local issue_count=${#ISSUES[@]}
    local warning_count=${#WARNINGS[@]}
    local ok_count=${#OK_CHECKS[@]}

    if [ "$OUTPUT_MODE" = "text" ]; then
        echo ""
        echo "─────────────────────────────────────────"
        printf " 汇总: ${GREEN}通过 %d${NC} / ${RED}问题 %d${NC} / ${YELLOW}警告 %d${NC}\n" "$ok_count" "$issue_count" "$warning_count"
        echo "─────────────────────────────────────────"
        echo ""

        if [ "$issue_count" -eq 0 ]; then
            echo -e " ${GREEN}✓ 备份系统运行正常${NC}"
        fi
        echo ""
    elif [ "$OUTPUT_MODE" = "json" ]; then
        # JSON 输出
        jq -n \
            --arg hostname "$(hostname)" \
            --arg timestamp "$(date -Iseconds)" \
            --arg hours_ago "$hours_ago" \
            --arg latest_backup "$latest_name" \
            --arg latest_backup_time "$latest_time" \
            --argjson ok_count "$ok_count" \
            --argjson issue_count "$issue_count" \
            --argjson warning_count "$warning_count" \
            --arg issues "$(printf '%s\n' "${ISSUES[@]}" | jq -R -s 'split("\n") | map(select(. != ""))')" \
            --arg warnings "$(printf '%s\n' "${WARNINGS[@]}" | jq -R -s 'split("\n") | map(select(. != ""))')" \
            '{
                hostname: $hostname,
                timestamp: $timestamp,
                status: (if $issue_count == 0 then "healthy" else "degraded" end),
                latest_backup_hours_ago: ($hours_ago | tonumber),
                latest_backup: $latest_backup,
                latest_backup_time: $latest_backup_time,
                checks: {ok: $ok_count, issues: $issue_count, warnings: $warning_count},
                issues: ($issues | fromjson),
                warnings: ($warnings | fromjson)
            }'
    fi

    # 如果有严重问题，发送 Telegram 告警
    if [ "$issue_count" -gt 0 ]; then
        local alert_msg
        alert_msg=$(printf '⚠️ *备份健康检查异常*\n主机: %s\n时间: %s\n最近备份: %s (%s 小时前)\n问题: %d 项\n警告: %d 项\n\n' \
            "$(hostname)" "$(date '+%Y-%m-%d %H:%M:%S')" "$latest_name" "$hours_ago" "$issue_count" "$warning_count")

        for issue in "${ISSUES[@]}"; do
            alert_msg="${alert_msg}❌ ${issue}\n"
        done

        tg_notify "$alert_msg"
    fi

    return $overall
}

main
