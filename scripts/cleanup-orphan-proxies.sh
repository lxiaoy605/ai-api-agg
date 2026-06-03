#!/bin/bash
# =============================================
# 清理孤儿 docker-proxy 进程
# 
# 问题：Docker 偶发 bug，容器重建后旧的 docker-proxy 进程
# 未被清理，残留进程劫持宿主机端口，导致新容器无法正常绑定。
# 
# 使用：在任何 docker compose up -d 之前调用
# =============================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "[cleanup-orphan-proxies] 检查孤儿 docker-proxy 进程..."

ORPHAN_COUNT=0

# 遍历所有 docker-proxy 进程
for pid in $(pgrep -f 'docker-proxy' 2>/dev/null || true); do
    cmdline=$(cat "/proc/$pid/cmdline" 2>/dev/null | tr '\0' ' ')
    if [ -z "$cmdline" ]; then
        continue
    fi

    # 提取 container-ip
    container_ip=$(echo "$cmdline" | grep -oP 'container-ip \K[\d.]+' || true)
    host_port=$(echo "$cmdline" | grep -oP 'host-port \K\d+' || true)

    if [ -z "$container_ip" ] || [ -z "$host_port" ]; then
        continue
    fi

    # 检查该 IP 是否属于任何运行中的容器
    alive=$(docker ps -q 2>/dev/null | while read cid; do
        docker inspect "$cid" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{"\n"}}{{end}}' 2>/dev/null
    done | grep -c "^${container_ip}$" || true)

    if [ "$alive" -eq 0 ]; then
        echo "⚠️  孤儿 proxy: PID=$pid host-port=$host_port -> $container_ip (目标容器已不存在)"
        if kill "$pid" 2>/dev/null; then
            echo "  ✅ 已清理 PID=$pid"
            ORPHAN_COUNT=$((ORPHAN_COUNT + 1))
        else
            echo "  ❌ 清理失败（无权限），需要 sudo kill $pid"
        fi
    fi
done

if [ "$ORPHAN_COUNT" -eq 0 ]; then
    echo "✅ 无孤儿 docker-proxy 进程"
else
    echo "✅ 已清理 $ORPHAN_COUNT 个孤儿进程"
fi
