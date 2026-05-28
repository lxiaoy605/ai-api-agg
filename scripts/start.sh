#!/usr/bin/env bash
# =============================================
# AI API 聚合平台 — 开发环境一键启动
# =============================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "========================================="
echo " AI API 聚合平台 — 开发环境启动"
echo "========================================="

# ---------- 1. 检查前置依赖 ----------
check_command() {
    local cmd="$1"
    local name="${2:-$cmd}"
    if ! command -v "$cmd" &>/dev/null; then
        echo "[错误] $name 未安装，请先安装"
        exit 1
    fi
    echo "  ✓ $name 已就绪"
}

echo ""
echo "[1/4] 检查前置依赖..."
check_command go "Go"
check_command node "Node.js"
check_command docker "Docker"
check_command docker "Docker Compose"  # Docker Desktop 自带 compose

# ---------- 2. 启动基础设施（OneAPI + Nginx）----------
echo ""
echo "[2/4] 启动基础设施（OneAPI + Nginx）..."
cd "$PROJECT_ROOT/docker"

# 初始化 OneAPI .env（若不存在）
if [ ! -f oneapi/.env ]; then
    cp oneapi/.env.example oneapi/.env
    echo "  ✓ 已创建 docker/oneapi/.env（请根据需要修改）"
fi

docker compose up -d oneapi nginx
echo "  ✓ Docker 服务已启动"

# ---------- 3. 启动 Go 后端 ----------
echo ""
echo "[3/4] 启动 Go 后端..."
cd "$PROJECT_ROOT/backend"
go build -o /tmp/ai-api-agg-server ./cmd/server
/tmp/ai-api-agg-server &
BACKEND_PID=$!
echo "  ✓ 后端已启动 (PID=$BACKEND_PID, 端口 8080)"

# ---------- 4. 启动前端开发服务器 ----------
echo ""
echo "[4/4] 启动 Next.js 前端开发服务器..."
cd "$PROJECT_ROOT/frontend"
npm run dev &
FRONTEND_PID=$!
echo "  ✓ 前端已启动 (PID=$FRONTEND_PID, 端口 3001)"

# ---------- 完成 ----------
echo ""
echo "========================================="
echo " 开发环境启动完成！"
echo ""
echo "  前端页面:  http://localhost:3001"
echo "  OneAPI:    http://localhost:3000"
echo "  后端 API:  http://localhost:8080"
echo "  Nginx:     http://localhost:80"
echo ""
echo "  停止开发环境: kill $BACKEND_PID $FRONTEND_PID"
echo "========================================="

# 等待子进程
wait
