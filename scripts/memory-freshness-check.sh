#!/usr/bin/env bash
# 每 3 天检查 projects.md 活跃项目「上次状态」是否过期
# 用途：心跳 job 调用，过期则提醒
PROJECTS_FILE="/mnt/d/WSL/openclawWorkspace/workspace/memory/projects.md"
THRESHOLD_DAYS=3
NOW=$(date +%s)

# 查找「上次状态」行中的日期
# 格式: - **上次状态**: xxx, 2026-06-03
while IFS= read -r line; do
    if [[ "$line" =~ 上次状态.*([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
        last_date="${BASH_REMATCH[1]}"
        last_ts=$(date -d "$last_date" +%s 2>/dev/null || echo 0)
        age_days=$(( (NOW - last_ts) / 86400 ))
        if [ "$age_days" -gt "$THRESHOLD_DAYS" ]; then
            # 取项目名（上面几行的 ### 标题）
            echo "STALE: $line (${age_days}d old)"
        fi
    fi
done < <(grep -B5 "上次状态" "$PROJECTS_FILE" | grep -v "^--$")

# 无过期则静默
