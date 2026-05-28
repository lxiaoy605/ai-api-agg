#!/usr/bin/env bash
# =============================================
# AI API 聚合平台 — 蓝绿环境一键部署
# =============================================
# 功能：
#   1. 启动 HAProxy + Blue + Green 三个容器
#   2. 验证双端健康状态
#   3. 确认 HAProxy 正确路由流量
#   4. 输出部署状态摘要
#
# 用法：
#   ./bluegreen-deploy.sh                     # 标准部署
#   ./bluegreen-deploy.sh --with-override     # 使用 override 配置
#   ./bluegreen-deploy.sh --status            # 仅查看状态
#   ./bluegreen-deploy.sh --down              # 停止蓝绿环境
# =============================================

set -euo pipefail

# ==========================================
# 路径
# ==========================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DOCKER_DIR="$PROJECT_DIR/docker"
LOG_DIR="$PROJECT_DIR/logs"
ENV_FILE="$DOCKER_DIR/.env"
STATE_FILE="$LOG_DIR/bluegreen.state"
mkdir -p "$LOG_DIR"

COMPOSE_BASE="$DOCKER_DIR/docker-compose.yml"
COMPOSE_OVERRIDE="$DOCKER_DIR/bluegreen-docker-compose.override.yml"

# ==========================================
# 颜色
# ==========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ==========================================
# 函数
# ==========================================
banner() {
    echo ""
    echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║  蓝绿部署 — AI API 聚合平台              ║${NC}"
    echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════╝${NC}"
    echo ""
}

ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
info() { echo -e "  ${CYAN}→${NC} $1"; }

# ==========================================
# 加载环境变量
# ==========================================
load_env() {
    if [ -f "$ENV_FILE" ]; then
        set -a
        # shellcheck source=/dev/null
        source "$ENV_FILE"
        set +a
    fi
}

# ==========================================
# 构建 Docker Compose 命令
# ==========================================
compose_cmd() {
    if [ "$USE_OVERRIDE" = true ] && [ -f "$COMPOSE_OVERRIDE" ]; then
        docker compose -f "$COMPOSE_BASE" -f "$COMPOSE_OVERRIDE" "$@"
    else
        docker compose -f "$COMPOSE_BASE" "$@"
    fi
}

# ==========================================
# 健康检查
# ==========================================
check_health() {
    local name="$1"
    local port="$2"
    local max_retries="${3:-10}"
    local retry=0

    while [ $retry -lt $max_retries ]; do
        local code
        code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
            "http://localhost:${port}/api/status" 2>/dev/null || echo "000")

        if [ "$code" = "200" ]; then
            ok "$name (:${port}) 健康检查通过"
            return 0
        fi
        retry=$((retry + 1))
        if [ $((retry % 3)) -eq 0 ]; then
            info "$name 等待中... ($retry/$max_retries)"
        fi
        sleep 5
    done

    fail "$name (:${port}) 健康检查失败 (尝试 $max_retries 次)"
    return 1
}

# ==========================================
# 部署
# ==========================================
do_deploy() {
    banner

    # 1. 检查前置条件
    echo -e "${BOLD}[1/6] 检查前置条件...${NC}"
    if ! command -v docker &>/dev/null; then
        fail "Docker 未安装"
        exit 1
    fi
    ok "Docker 已就绪"

    if docker compose version &>/dev/null; then
        ok "Docker Compose 已就绪"
    else
        fail "Docker Compose 不可用"
        exit 1
    fi

    if [ ! -f "$COMPOSE_BASE" ]; then
        fail "docker-compose.yml 不存在: $COMPOSE_BASE"
        exit 1
    fi
    ok "docker-compose.yml 已找到"

    if [ ! -f "$DOCKER_DIR/haproxy/haproxy.cfg" ]; then
        fail "HAProxy 配置不存在: $DOCKER_DIR/haproxy/haproxy.cfg"
        exit 1
    fi
    ok "HAProxy 配置已找到"

    # 检查 OneAPI .env
    if [ ! -f "$DOCKER_DIR/oneapi/.env" ]; then
        warn "OneAPI .env 不存在，从模板创建..."
        cp "$DOCKER_DIR/oneapi/.env.example" "$DOCKER_DIR/oneapi/.env"
        ok "已创建 $DOCKER_DIR/oneapi/.env"
    else
        ok "OneAPI .env 已配置"
    fi

    # 检查主 .env
    if [ ! -f "$ENV_FILE" ]; then
        warn "主 .env 不存在，从模板创建..."
        cp "$DOCKER_DIR/.env.example" "$ENV_FILE"
        ok "已创建 $ENV_FILE (请编辑填入实际值)"
    else
        ok "主 .env 已配置"
    fi

    # 2. 拉取镜像
    echo ""
    echo -e "${BOLD}[2/6] 拉取 Docker 镜像...${NC}"
    local pull_ok=true

    info "拉取 haproxy:3-alpine..."
    if docker pull haproxy:3-alpine 2>&1 | tail -1; then
        ok "haproxy:3-alpine"
    else
        fail "HAProxy 镜像拉取失败"
        pull_ok=false
    fi

    info "拉取 justsong/one-api:latest..."
    if docker pull justsong/one-api:latest 2>&1 | tail -1; then
        ok "justsong/one-api:latest"
    else
        fail "OneAPI 镜像拉取失败"
        pull_ok=false
    fi

    if [ "$pull_ok" = false ]; then
        fail "镜像拉取失败，请检查网络连接"
        exit 1
    fi

    # 3. 停止现有的单实例（如果运行中）
    echo ""
    echo -e "${BOLD}[3/6] 检查现有实例...${NC}"
    local has_oneapi
    has_oneapi=$(docker ps --filter "name=ai-api-agg-oneapi" --format '{{.Names}}' 2>/dev/null | grep -v "blue\|green" || true)
    if [ -n "$has_oneapi" ]; then
        warn "检测到旧单实例 oneapi 正在运行"
        warn "蓝绿模式需要 blue/green 双实例替代单实例"
        read -r -p "是否停止单实例 oneapi 并启动蓝绿环境? (y/N): " answer
        case "$answer" in
            [Yy]|[Yy][Ee][Ss])
                info "停止旧实例..."
                docker compose -f "$COMPOSE_BASE" stop oneapi 2>/dev/null || true
                ok "旧实例已停止"
                ;;
            *)
                warn "保留旧实例，蓝绿环境将与单实例并存"
                ;;
        esac
    else
        ok "无冲突实例"
    fi

    # 4. 启动 Blue + Green
    echo ""
    echo -e "${BOLD}[4/6] 启动 OneAPI Blue + Green 实例...${NC}"

    info "启动 oneapi-blue..."
    compose_cmd up -d oneapi-blue
    ok "oneapi-blue 已启动"

    info "启动 oneapi-green..."
    compose_cmd up -d oneapi-green
    ok "oneapi-green 已启动"

    # 5. 健康检查
    echo ""
    echo -e "${BOLD}[5/6] 健康检查...${NC}"

    info "等待 OneAPI 实例就绪（最多 60s）..."
    local health_ok=true

    if ! check_health "Blue" 3001 12; then
        health_ok=false
    fi

    if ! check_health "Green" 3002 12; then
        health_ok=false
    fi

    if [ "$health_ok" = false ]; then
        echo ""
        fail "部分实例健康检查未通过"
        echo ""
        echo "排查建议:"
        echo "  1. 查看容器日志: docker logs ai-api-agg-oneapi-blue"
        echo "  2. 检查端口占用: ss -tlnp | grep -E '300[12]'"
        echo "  3. 检查 OneAPI 配置: cat $DOCKER_DIR/oneapi/.env"
        exit 1
    fi

    # 6. 启动 HAProxy
    echo ""
    echo -e "${BOLD}[6/6] 启动 HAProxy 负载均衡...${NC}"

    info "启动 HAProxy..."
    compose_cmd up -d haproxy

    # 验证 HAProxy
    sleep 5
    local haproxy_status
    haproxy_status=$(docker inspect "ai-api-agg-haproxy" --format '{{.State.Status}}' 2>/dev/null || echo "stopped")

    if [ "$haproxy_status" = "running" ]; then
        ok "HAProxy 已启动"

        # 验证 HAProxy 可以路由到后端
        info "验证 HAProxy 路由..."
        local proxy_code
        proxy_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
            "http://localhost:8080/api/status" 2>/dev/null || echo "000")

        if [ "$proxy_code" = "200" ]; then
            ok "HAProxy 路由正常 (通过 8080 → 后端)"
        else
            warn "HAProxy 通过 8080 返回 $proxy_code，可能需要更多时间预热"
            warn "请手动验证: curl http://localhost:8080/api/status"
        fi
    else
        fail "HAProxy 启动失败"
        docker logs "ai-api-agg-haproxy" --tail 20 2>/dev/null || true
        exit 1
    fi

    # 初始化状态文件
    echo "blue" > "$STATE_FILE"

    # ==========================================
    # 部署摘要
    # ==========================================
    echo ""
    echo -e "${BOLD}${GREEN}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║  ✅ 蓝绿环境部署完成！                    ║${NC}"
    echo -e "${BOLD}${GREEN}╚═══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}服务端点:${NC}"
    echo -e "  ┌─────────────────────────────────────────┐"
    echo -e "  │ HAProxy (入口):   ${CYAN}http://localhost:8080${NC}    │"
    echo -e "  │ HAProxy (管理):   ${CYAN}http://localhost:8081/stats${NC} │"
    echo -e "  │ Blue (active):    ${GREEN}http://localhost:3001${NC}     │"
    echo -e "  │ Green (standby):  ${YELLOW}http://localhost:3002${NC}     │"
    echo -e "  └─────────────────────────────────────────┘"
    echo ""
    echo -e "  ${BOLD}当前状态:${NC}"
    echo -e "  ${GREEN}●${NC} Blue  : ACTIVE  (weight=100, port 3001)"
    echo -e "  ${YELLOW}○${NC} Green : STANDBY (weight=0,   port 3002)"
    echo ""
    echo -e "  ${BOLD}常用命令:${NC}"
    echo -e "  查看状态:     ${CYAN}./scripts/bluegreen-switch.sh status${NC}"
    echo -e "  切到 Green:   ${CYAN}./scripts/bluegreen-switch.sh --target green --mode instant${NC}"
    echo -e "  灰度 30%:     ${CYAN}./scripts/bluegreen-switch.sh --target green --mode gradual --weight 30${NC}"
    echo -e "  紧急回滚:     ${CYAN}./scripts/rollback.sh --layer 1 --auto${NC}"
    echo -e "  停止环境:     ${CYAN}./scripts/bluegreen-deploy.sh --down${NC}"
    echo ""
}

# ==========================================
# 停止环境
# ==========================================
do_down() {
    banner

    echo -e "${YELLOW}将停止 HAProxy + Blue + Green 容器${NC}"
    echo ""

    if [ "${FORCE:-false}" != "true" ]; then
        read -r -p "确认停止? (y/N): " answer
        case "$answer" in
            [Yy]|[Yy][Ee][Ss]) ;;
            *)
                info "已取消"
                exit 0
                ;;
        esac
    fi

    info "停止 haproxy..."
    compose_cmd stop haproxy 2>/dev/null || true

    info "停止 oneapi-blue..."
    compose_cmd stop oneapi-blue 2>/dev/null || true

    info "停止 oneapi-green..."
    compose_cmd stop oneapi-green 2>/dev/null || true

    ok "蓝绿环境已停止"

    # 可选：移除状态文件
    rm -f "$STATE_FILE"
    ok "状态文件已清理"
}

# ==========================================
# 状态
# ==========================================
do_status() {
    banner

    load_env

    local haproxy_status blue_status green_status
    haproxy_status=$(docker inspect "ai-api-agg-haproxy" --format '{{.State.Status}}' 2>/dev/null || echo "stopped")
    blue_status=$(docker inspect "ai-api-agg-oneapi-blue" --format '{{.State.Status}}' 2>/dev/null || echo "stopped")
    green_status=$(docker inspect "ai-api-agg-oneapi-green" --format '{{.State.Status}}' 2>/dev/null || echo "stopped")

    echo -e "  HAProxy: $([ "$haproxy_status" = "running" ] && echo "${GREEN}●${NC}" || echo "${RED}●${NC}") $haproxy_status"
    echo -e "  Blue:    $([ "$blue_status" = "running" ] && echo "${GREEN}●${NC}" || echo "${RED}●${NC}") $blue_status"
    echo -e "  Green:   $([ "$green_status" = "running" ] && echo "${GREEN}●${NC}" || echo "${RED}●${NC}") $green_status"
    echo ""

    if [ -f "$STATE_FILE" ]; then
        echo -e "  活跃实例: ${GREEN}$(cat "$STATE_FILE")${NC}"
    fi

    # 快速健康探测
    if [ "$blue_status" = "running" ]; then
        local code
        code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://localhost:3001/api/status" 2>/dev/null || echo "000")
        echo -e "  Blue 健康:  HTTP $code"
    fi

    if [ "$green_status" = "running" ]; then
        local code
        code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://localhost:3002/api/status" 2>/dev/null || echo "000")
        echo -e "  Green 健康: HTTP $code"
    fi

    if [ "$haproxy_status" = "running" ]; then
        local code
        code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://localhost:8080/api/status" 2>/dev/null || echo "000")
        echo -e "  代理路由:   HTTP $code (via :8080)"
    fi
}

# ==========================================
# 使用帮助
# ==========================================
usage() {
    cat << 'EOF'
用法: bluegreen-deploy.sh [选项]

选项:
  (无参数)                标准部署（启动 Blue + Green + HAProxy）
  --with-override         使用 bluegreen-docker-compose.override.yml
  --status                查看蓝绿环境状态
  --down                  停止蓝绿环境（保留数据卷）
  --down --force          强制停止（跳过确认）
  -h, --help              显示帮助

示例:
  ./bluegreen-deploy.sh                        # 标准蓝绿部署
  ./bluegreen-deploy.sh --with-override        # 使用 override 配置部署
  ./bluegreen-deploy.sh --status               # 查看状态
  ./bluegreen-deploy.sh --down                 # 停止环境

部署后:
  HAProxy 入口:         http://localhost:8080
  HAProxy 状态页:       http://localhost:8081/stats (admin/admin123)
  Blue (active):        http://localhost:3001
  Green (standby):      http://localhost:3002
EOF
}

# ==========================================
# 主流程
# ==========================================
USE_OVERRIDE=false
FORCE=false

if [ $# -eq 0 ]; then
    do_deploy
    exit 0
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --with-override)
            USE_OVERRIDE=true
            shift
            # 如果只有此选项，执行部署
            if [ $# -eq 0 ]; then
                do_deploy
                exit 0
            fi
            ;;
        --status)
            do_status
            exit 0
            ;;
        --down)
            shift
            if [ "${1:-}" = "--force" ]; then
                FORCE=true
                shift
            fi
            do_down
            exit 0
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "未知参数: $1"
            usage
            exit 1
            ;;
    esac
done
