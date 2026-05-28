#!/usr/bin/env bash
# =============================================
# AI API 聚合平台 — 一键全堆栈部署
# =============================================
# 功能：
#   1. 启动所有服务: oneapi-blue/green, backend-blue/green,
#      haproxy, nginx, prometheus, grafana
#   2. 自动等待各服务健康状态
#   3. 输出部署摘要表格
#
# 用法：
#   ./deploy.sh                     # 标准全栈部署
#   ./deploy.sh --status            # 仅查看状态
#   ./deploy.sh --down              # 停止所有服务
#   ./deploy.sh --reload-haproxy    # 重载 HAProxy 配置
# =============================================

set -euo pipefail

# ==========================================
# 路径
# ==========================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DOCKER_DIR="${PROJECT_DIR}/stack"
LOG_DIR="$PROJECT_DIR/logs"
ENV_FILE="$DOCKER_DIR/.env"
STATE_FILE="$LOG_DIR/bluegreen.state"
DEPLOY_LOG="$LOG_DIR/deploy.log"
mkdir -p "$LOG_DIR"

COMPOSE_FILE="$DOCKER_DIR/docker-compose.yml"

# 检测 Docker Compose 命令（优先插件版，fallback 独立版）
if docker compose version &>/dev/null; then
    COMPOSE_CMD="docker compose"
elif docker-compose version &>/dev/null; then
    COMPOSE_CMD="docker-compose"
else
    COMPOSE_CMD=""
fi

# ==========================================
# 颜色
# ==========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
info() { echo -e "  ${CYAN}→${NC} $1"; }

# ==========================================
# 日志
# ==========================================
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" >> "$DEPLOY_LOG"
}

banner() {
    echo ""
    echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║  AI API 聚合平台 — 全栈一键部署          ║${NC}"
    echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════╝${NC}"
    echo ""
}

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
# 健康检查
# ==========================================
wait_for_http() {
    local name="$1"
    local url="$2"
    local max_retries="${3:-12}"
    local retry=0

    while [ $retry -lt $max_retries ]; do
        local code
        code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || echo "000")
        if [ "$code" = "200" ]; then
            ok "$name 健康检查通过"
            return 0
        fi
        retry=$((retry + 1))
        if [ $((retry % 3)) -eq 0 ]; then
            info "$name 等待中... ($retry/$max_retries)"
        fi
        sleep 5
    done

    fail "$name 健康检查超时 ($max_retries 次尝试)"
    return 1
}

# ==========================================
# 初始化状态文件
# ==========================================
init_state() {
    if [ ! -f "$STATE_FILE" ]; then
        cat > "$STATE_FILE" << 'EOF'
oneapi_active=blue
backend_active=blue
EOF
        ok "状态文件已初始化"
    fi
}

# ==========================================
# 部署
# ==========================================
do_deploy() {
    banner
    load_env
    log "===== 开始全栈部署 ====="

    # ======================================
    # [1/5] 前置条件检查
    # ======================================
    echo -e "${BOLD}[1/5] 检查前置条件...${NC}"

    if ! command -v docker &>/dev/null; then
        fail "Docker 未安装"
        exit 1
    fi
    ok "Docker 已就绪"

    if [ -n "$COMPOSE_CMD" ]; then
        ok "Docker Compose 已就绪 ($COMPOSE_CMD)"
    else
        fail "Docker Compose 不可用"
        exit 1
    fi

    if [ ! -f "$COMPOSE_FILE" ]; then
        fail "docker-compose.yml 不存在: $COMPOSE_FILE"
        exit 1
    fi
    ok "docker-compose.yml 已找到"

    if [ ! -f "$ENV_FILE" ]; then
        warn "docker/.env 不存在，从模板创建..."
        cp "$DOCKER_DIR/.env.example" "$ENV_FILE"
        ok "已创建 $ENV_FILE (请编辑填入实际值)"
    else
        ok "docker/.env 已配置"
    fi

    log "前置条件检查完成"
    echo ""

    # ======================================
    # [2/5] 拉取/构建镜像
    # ======================================
    echo -e "${BOLD}[2/5] 准备镜像...${NC}"

    local pull_errors=0

    # 拉取外部镜像
    for img in "haproxy:3-alpine" "justsong/one-api:latest" "nginx:alpine" \
               "prom/prometheus:latest" "prom/alertmanager:latest" \
               "prom/blackbox-exporter:latest" "grafana/grafana:latest"; do
        info "拉取 $img..."
        if docker pull "$img" 2>&1 | tail -1; then
            ok "$img"
        else
            warn "$img 拉取失败，将使用本地缓存"
            pull_errors=$((pull_errors + 1))
        fi
    done

    # 构建 Go 后端镜像
    if [ -f "$PROJECT_DIR/backend/Dockerfile" ]; then
        info "构建 Go 后端镜像..."
        if docker build \
            -t ai-api-agg-backend:latest \
            -f "$PROJECT_DIR/backend/Dockerfile" \
            "$PROJECT_DIR/backend" 2>&1 | tail -3; then
            ok "Go 后端镜像构建成功"
        else
            warn "Go 后端镜像构建失败（如不需要后端可跳过）"
        fi
    else
        info "未找到 backend/Dockerfile，跳过后端构建"
    fi

    log "镜像准备完成"
    echo ""

    # ======================================
    # [3/5] 启动核心服务
    # ======================================
    echo -e "${BOLD}[3/5] 启动核心服务...${NC}"

    # OneAPI 实例
    info "启动 oneapi-blue..."
    $COMPOSE_CMD -f "$COMPOSE_FILE" up -d oneapi-blue 2>&1 | tail -1
    ok "oneapi-blue 已启动"

    info "启动 oneapi-green..."
    $COMPOSE_CMD -f "$COMPOSE_FILE" up -d oneapi-green 2>&1 | tail -1
    ok "oneapi-green 已启动"

    # Go 后端实例
    info "启动 backend-blue..."
    $COMPOSE_CMD -f "$COMPOSE_FILE" up -d backend-blue 2>&1 | tail -1 || warn "backend-blue 启动失败（后端可能未就绪）"

    info "启动 backend-green..."
    $COMPOSE_CMD -f "$COMPOSE_FILE" up -d backend-green 2>&1 | tail -1 || warn "backend-green 启动失败（后端可能未就绪）"

    # Nginx
    info "启动 nginx..."
    $COMPOSE_CMD -f "$COMPOSE_FILE" up -d nginx 2>&1 | tail -1 || warn "nginx 启动失败"

    log "核心服务启动完成"
    echo ""

    # ======================================
    # [4/5] 健康检查
    # ======================================
    echo -e "${BOLD}[4/5] 健康检查...${NC}"

    local health_ok=true

    info "等待 OneAPI Blue 就绪..."
    if ! wait_for_http "OneAPI Blue" "http://localhost:3001/api/status" 12; then
        health_ok=false
    fi

    info "等待 OneAPI Green 就绪..."
    if ! wait_for_http "OneAPI Green" "http://localhost:3002/api/status" 12; then
        health_ok=false
    fi

    # 后端健康检查（可能尚未构建/启动）
    local backend_blue_code
    backend_blue_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 \
        "http://localhost:${BACKEND_BLUE_PORT:-8082}/health" 2>/dev/null || echo "000")
    if [ "$backend_blue_code" = "200" ]; then
        ok "Backend Blue (:${BACKEND_BLUE_PORT:-8082}) 健康"
    else
        warn "Backend Blue 未就绪 (HTTP $backend_blue_code)"
    fi

    local backend_green_code
    backend_green_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 \
        "http://localhost:${BACKEND_GREEN_PORT:-8083}/health" 2>/dev/null || echo "000")
    if [ "$backend_green_code" = "200" ]; then
        ok "Backend Green (:${BACKEND_GREEN_PORT:-8083}) 健康"
    else
        warn "Backend Green 未就绪 (HTTP $backend_green_code)"
    fi

    # 启动 HAProxy
    info "启动 HAProxy..."
    $COMPOSE_CMD -f "$COMPOSE_FILE" up -d haproxy 2>&1 | tail -1
    sleep 5

    # 验证 HAProxy
    local haproxy_code
    haproxy_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
        "http://localhost:8080/api/status" 2>/dev/null || echo "000")
    if [ "$haproxy_code" = "200" ]; then
        ok "HAProxy 路由正常 (:8080 → OneAPI)"
    else
        warn "HAProxy 返回 HTTP $haproxy_code，可能需要预热"
    fi

    # 启动监控服务
    info "启动 Prometheus..."
    $COMPOSE_CMD -f "$COMPOSE_FILE" up -d prometheus 2>&1 | tail -1 || true

    info "启动 Grafana..."
    $COMPOSE_CMD -f "$COMPOSE_FILE" up -d grafana 2>&1 | tail -1 || true

    # 初始化状态
    init_state

    log "健康检查完成"
    echo ""

    # ======================================
    # [5/5] 部署摘要
    # ======================================
    echo -e "${BOLD}[5/5] 部署摘要${NC}"
    echo ""

    # 收集各服务状态
    local oneapi_blue oneapi_green backend_blue backend_green haproxy_s nginx_s prom_s grafana_s
    oneapi_blue=$(docker inspect "ai-api-agg-oneapi-blue" --format '{{.State.Status}}' 2>/dev/null || echo "N/A")
    oneapi_green=$(docker inspect "ai-api-agg-oneapi-green" --format '{{.State.Status}}' 2>/dev/null || echo "N/A")
    backend_blue=$(docker inspect "ai-api-agg-backend-blue" --format '{{.State.Status}}' 2>/dev/null || echo "N/A")
    backend_green=$(docker inspect "ai-api-agg-backend-green" --format '{{.State.Status}}' 2>/dev/null || echo "N/A")
    haproxy_s=$(docker inspect "ai-api-agg-haproxy" --format '{{.State.Status}}' 2>/dev/null || echo "N/A")
    nginx_s=$(docker inspect "ai-api-agg-nginx" --format '{{.State.Status}}' 2>/dev/null || echo "N/A")
    prom_s=$(docker inspect "ai-api-agg-prometheus" --format '{{.State.Status}}' 2>/dev/null || echo "N/A")
    grafana_s=$(docker inspect "ai-api-agg-grafana" --format '{{.State.Status}}' 2>/dev/null || echo "N/A")

    # 状态图标
    icon() {
        case "$1" in
            running) echo -e "${GREEN}●${NC}" ;;
            *)       echo -e "${RED}●${NC}" ;;
        esac
    }

    echo -e "  ${BOLD}${GREEN}╔═══════════════════════════════════════════╗${NC}"
    echo -e "  ${BOLD}${GREEN}║  ✅ 全栈部署完成！                        ║${NC}"
    echo -e "  ${BOLD}${GREEN}╚═══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}服务端点:${NC}"
    echo -e "  ┌──────────────────────────────────────────────────┐"
    echo -e "  │ $(icon "$haproxy_s") HAProxy (入口):     ${CYAN}http://localhost:8080${NC}          │"
    echo -e "  │ $(icon "$haproxy_s") HAProxy (管理):     ${CYAN}http://localhost:8081/stats${NC}        │"
    echo -e "  │ $(icon "$oneapi_blue") OneAPI Blue:        ${GREEN}http://localhost:3001${NC}           │"
    echo -e "  │ $(icon "$oneapi_green") OneAPI Green:       ${YELLOW}http://localhost:3002${NC}           │"
    echo -e "  │ $(icon "$backend_blue") Backend Blue:       ${GREEN}http://localhost:${BACKEND_BLUE_PORT:-8082}${NC}      │"
    echo -e "  │ $(icon "$backend_green") Backend Green:      ${YELLOW}http://localhost:${BACKEND_GREEN_PORT:-8083}${NC}      │"
    echo -e "  │ $(icon "$nginx_s") Nginx:              ${CYAN}http://localhost:80/443${NC}         │"
    echo -e "  │ $(icon "$prom_s") Prometheus:         ${CYAN}http://localhost:9090${NC}              │"
    echo -e "  │ $(icon "$grafana_s") Grafana:            ${CYAN}http://localhost:3030${NC}              │"
    echo -e "  └──────────────────────────────────────────────────┘"
    echo ""
    echo -e "  ${BOLD}运维命令:${NC}"
    echo -e "  查看状态:     ${CYAN}./scripts/deploy.sh --status${NC}"
    echo -e "  后端蓝绿:     ${CYAN}./scripts/bluegreen-switch.sh --pool backend --target green --mode instant${NC}"
    echo -e "  OneAPI 蓝绿:  ${CYAN}./scripts/bluegreen-switch.sh --target green --mode instant${NC}"
    echo -e "  重载 HAProxy: ${CYAN}./scripts/deploy.sh --reload-haproxy${NC}"
    echo -e "  停止服务:     ${CYAN}./scripts/deploy.sh --down${NC}"
    echo ""

    if [ "$health_ok" = false ]; then
        echo -e "  ${YELLOW}⚠ 部分服务健康检查未通过，请检查: $COMPOSE_CMD -f $COMPOSE_FILE ps${NC}"
        echo ""
    fi
}

# ==========================================
# 状态
# ==========================================
do_status() {
    banner
    load_env

    echo -e "  ${BOLD}服务状态:${NC}"
    echo ""

    local services=(
        "ai-api-agg-oneapi-blue:OneAPI Blue:3001"
        "ai-api-agg-oneapi-green:OneAPI Green:3002"
        "ai-api-agg-backend-blue:Backend Blue:${BACKEND_BLUE_PORT:-8082}"
        "ai-api-agg-backend-green:Backend Green:${BACKEND_GREEN_PORT:-8083}"
        "ai-api-agg-haproxy:HAProxy:8080"
        "ai-api-agg-nginx:Nginx:80"
        "ai-api-agg-prometheus:Prometheus:9090"
        "ai-api-agg-grafana:Grafana:3030"
    )

    for svc_def in "${services[@]}"; do
        IFS=':' read -r container name port <<< "$svc_def"
        local status
        status=$(docker inspect "$container" --format '{{.State.Status}}' 2>/dev/null || echo "stopped")
        local icon
        case "$status" in
            running) icon="${GREEN}●${NC}" ;;
            *)       icon="${RED}●${NC}" ;;
        esac

        # 快速健康探测
        local health=""
        if [ "$status" = "running" ]; then
            local code
            if [ "$name" = "HAProxy" ]; then
                code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://localhost:${port}/api/status" 2>/dev/null || echo "000")
            elif [ "$name" = "Backend Blue" ] || [ "$name" = "Backend Green" ]; then
                code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://localhost:${port}/health" 2>/dev/null || echo "000")
            elif [ "$name" = "OneAPI Blue" ] || [ "$name" = "OneAPI Green" ]; then
                code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://localhost:${port}/api/status" 2>/dev/null || echo "000")
            else
                code="---"
            fi
            if [ "$code" = "200" ]; then
                health=" ${GREEN}✓${NC}"
            elif [ "$code" = "---" ]; then
                health=""
            else
                health=" ${RED}HTTP ${code}${NC}"
            fi
        fi

        printf "  %s %-16s %-10s%s\n" "$icon" "$name" "$status" "$health"
    done

    echo ""
    echo -e "  ${BOLD}HAProxy 状态页:${NC} http://localhost:8081/stats"
    echo ""
}

# ==========================================
# 停止服务
# ==========================================
do_down() {
    banner

    echo -e "${YELLOW}将停止所有核心服务...${NC}"
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

    local services=(
        "grafana" "prometheus" "alertmanager" "blackbox-exporter"
        "nginx" "haproxy"
        "backend-green" "backend-blue"
        "oneapi-green" "oneapi-blue"
    )

    for svc in "${services[@]}"; do
        info "停止 $svc..."
        $COMPOSE_CMD -f "$COMPOSE_FILE" stop "$svc" 2>/dev/null || true
    done

    ok "所有服务已停止"
    rm -f "$STATE_FILE"
    ok "状态文件已清理"
}

# ==========================================
# 重载 HAProxy
# ==========================================
do_reload_haproxy() {
    info "重载 HAProxy 配置..."
    $COMPOSE_CMD -f "$COMPOSE_FILE" exec haproxy sh -c \
        'echo "reload" | socat stdio /var/run/haproxy.sock' 2>/dev/null || {
        warn "Socket 重载失败，尝试重启容器..."
        $COMPOSE_CMD -f "$COMPOSE_FILE" restart haproxy
    }
    ok "HAProxy 已重载"
}

# ==========================================
# 使用帮助
# ==========================================
usage() {
    cat << 'EOF'
用法: deploy.sh [选项]

选项:
  (无参数)                 标准全栈部署
  --status                 查看服务状态
  --down                   停止所有服务
  --down --force           强制停止（跳过确认）
  --reload-haproxy         重载 HAProxy 配置
  -h, --help               显示帮助

示例:
  ./deploy.sh                               # 一键全栈部署
  ./deploy.sh --status                      # 查看状态
  ./deploy.sh --down                        # 停止服务
EOF
}

# ==========================================
# 主流程
# ==========================================
FORCE=false

if [ $# -eq 0 ]; then
    do_deploy
    exit 0
fi

while [ $# -gt 0 ]; do
    case "$1" in
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
        --reload-haproxy)
            do_reload_haproxy
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
