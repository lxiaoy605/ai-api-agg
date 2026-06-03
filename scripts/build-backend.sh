#!/usr/bin/env bash
# =============================================
# AI API 聚合平台 — Go 后端构建与蓝绿发布
# =============================================
# 功能：
#   1. 构建 Go 后端 Docker 镜像
#   2. 确定当前 inactive 实例
#   3. 启动 inactive 实例并等待健康检查
#   4. 灰度切换（gradual）或瞬间切换流量
#   5. 停止旧实例
#
# 用法：
#   ./build-backend.sh                        # 标准发布（灰度 100%）
#   ./build-backend.sh --no-build             # 跳过构建，仅切换
#   ./build-backend.sh --mode instant         # 瞬间切换模式
#   ./build-backend.sh --rollback             # 紧急回滚
#   ./build-backend.sh --status               # 查看状态
# =============================================

set -euo pipefail

# ==========================================
# 路径
# ==========================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DOCKER_DIR="$PROJECT_DIR/docker"
LOG_DIR="$PROJECT_DIR/logs"
BG_SWITCH="$SCRIPT_DIR/bluegreen-switch.sh"
mkdir -p "$LOG_DIR"

BUILD_LOG="$LOG_DIR/build-backend.log"

# ==========================================
# 颜色
# ==========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ==========================================
# 选项
# ==========================================
DO_BUILD=true
SWITCH_MODE="gradual"  # instant 或 gradual
ROLLBACK=false
SHOW_STATUS=false

# ==========================================
# 日志
# ==========================================
log() {
    local level="$1"; shift
    local color=""
    case "$level" in
        INFO)  color="$CYAN" ;;
        OK)    color="$GREEN" ;;
        WARN)  color="$YELLOW" ;;
        ERROR) color="$RED" ;;
        *)     color="$NC" ;;
    esac
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
    echo -e "${color}${msg}${NC}"
    echo "$msg" >> "$BUILD_LOG"
}

log_info()  { log INFO "$@"; }
log_ok()    { log OK "$@"; }
log_warn()  { log WARN "$@"; }
log_error() { log ERROR "$@"; }

banner() {
    echo ""
    echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║  Go 后端构建与蓝绿发布                    ║${NC}"
    echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════╝${NC}"
    echo ""
}

# ==========================================
# 使用帮助
# ==========================================
usage() {
    cat << 'EOF'
用法: build-backend.sh [选项]

选项:
  (无参数)                 构建镜像 + 灰度发布（默认 gradual 模式）
  --no-build               跳过镜像构建，仅执行切换
  --mode instant           使用瞬间切换模式（默认 gradual）
  --rollback               紧急回滚到另一实例
  --status                 查看后端池状态
  -h, --help               显示帮助

示例:
  ./build-backend.sh                              # 标准发布
  ./build-backend.sh --no-build --mode instant    # 跳过构建，瞬间切换
  ./build-backend.sh --rollback                   # 紧急回滚
  ./build-backend.sh --status                     # 查看状态
EOF
}

# ==========================================
# 获取当前活跃实例
# ==========================================
get_active() {
    local state_file="$LOG_DIR/bluegreen.state"
    if [ -f "$state_file" ]; then
        grep "^backend_active=" "$state_file" 2>/dev/null | cut -d= -f2 || echo "blue"
    else
        echo "blue"
    fi
}

get_inactive() {
    local active
    active=$(get_active)
    if [ "$active" = "blue" ]; then
        echo "green"
    else
        echo "blue"
    fi
}

# ==========================================
# 构建镜像
# ==========================================
do_build() {
    log_info "构建 Go 后端 Docker 镜像..."
    echo ""

    if docker build \
        -t ai-api-agg-backend:latest \
        -f "$PROJECT_DIR/backend/Dockerfile" \
        "$PROJECT_DIR/backend" 2>&1 | tee -a "$BUILD_LOG"; then
        log_ok "镜像构建成功: ai-api-agg-backend:latest"
    else
        log_error "镜像构建失败，请检查日志"
        return 1
    fi

    # 显示镜像大小
    local img_size
    img_size=$(docker images ai-api-agg-backend:latest --format '{{.Size}}' 2>/dev/null || echo "unknown")
    log_info "镜像大小: $img_size"
    return 0
}

# ==========================================
# 健康检查等待
# ==========================================
wait_healthy() {
    local port="$1"
    local max_retries="${2:-12}"
    local retry=0

    while [ $retry -lt $max_retries ]; do
        local code
        code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
            "http://localhost:${port}/health" 2>/dev/null || echo "000")
        if [ "$code" = "200" ]; then
            log_ok "后端 :${port} 健康检查通过 (HTTP $code)"
            return 0
        fi
        retry=$((retry + 1))
        if [ $((retry % 3)) -eq 0 ]; then
            log_info "等待后端就绪... ($retry/$max_retries)"
        fi
        sleep 5
    done

    log_error "后端 :${port} 健康检查超时"
    return 1
}

# ==========================================
# 发布流程
# ==========================================
do_deploy() {
    banner

    local active inactive inactive_port
    active=$(get_active)
    inactive=$(get_inactive)

    if [ "$inactive" = "green" ]; then
        inactive_port="${BACKEND_GREEN_PORT:-8083}"
    else
        inactive_port="${BACKEND_BLUE_PORT:-8082}"
    fi

    log_info "当前活跃: ${GREEN}${active}${NC}"
    log_info "目标实例: ${YELLOW}${inactive}${NC} (端口 :${inactive_port})"
    echo ""

    # 1. 构建镜像
    if [ "$DO_BUILD" = true ]; then
        echo -e "${BOLD}[1/4] 构建镜像${NC}"
        if ! do_build; then
            exit 1
        fi
    else
        echo -e "${BOLD}[1/4] 跳过构建${NC}"
        log_info "--no-build 模式，使用现有镜像"
    fi
    echo ""

    # 清理孤儿 docker-proxy（Docker 偶发 bug，旧 proxy 残留在宿主端口）
    "$SCRIPT_DIR/cleanup-orphan-proxies.sh" || true

    # 2. 启动 inactive 实例
    echo -e "${BOLD}[2/4] 启动 inactive 实例${NC}"
    local compose_svc
    if [ "$inactive" = "green" ]; then
        compose_svc="backend-green"
    else
        compose_svc="backend-blue"
    fi

    log_info "启动 $compose_svc..."
    docker compose -f "$DOCKER_DIR/docker-compose.yml" up -d "$compose_svc" 2>&1 | tee -a "$BUILD_LOG"

    log_info "等待 $inactive 实例健康就绪..."
    if ! wait_healthy "$inactive_port" 12; then
        log_error "inactive 实例启动失败，终止发布"
        exit 1
    fi
    echo ""

    # 3. 蓝绿切换
    echo -e "${BOLD}[3/4] 流量切换${NC}"

    if [ "$SWITCH_MODE" = "instant" ]; then
        log_info "使用瞬间切换模式..."
        if ! "$BG_SWITCH" --pool backend --target "$inactive" --mode instant; then
            log_error "切换失败！"
            exit 1
        fi
    else
        log_info "使用灰度切换模式 (每次 +20%, 间隔 30s)..."
        if ! "$BG_SWITCH" --pool backend --target "$inactive" --mode gradual --weight 100; then
            log_error "灰度切换失败！"
            exit 1
        fi
    fi
    echo ""

    # 4. 停止旧实例（可选，保留一段时间以便回滚）
    echo -e "${BOLD}[4/4] 清理旧实例${NC}"
    local old_svc
    if [ "$active" = "green" ]; then
        old_svc="backend-green"
    else
        old_svc="backend-blue"
    fi

    log_warn "旧实例 ($active) 将在 10 分钟后自动停止"
    log_info "如需立即停止: docker compose -f $DOCKER_DIR/docker-compose.yml stop $old_svc"
    log_info "如需回滚: $SCRIPT_DIR/build-backend.sh --rollback"

    echo ""
    echo -e "${BOLD}${GREEN}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║  ✅ Go 后端发布完成！                     ║${NC}"
    echo -e "${BOLD}${GREEN}╚═══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  活跃实例: ${GREEN}${inactive}${NC} (${inactive_port})"
    echo -e "  旧实例:   ${YELLOW}${active}${NC} (可回滚用)"
    echo ""
}

# ==========================================
# 回滚
# ==========================================
do_rollback() {
    banner
    echo -e "${YELLOW}紧急回滚 Go 后端...${NC}"
    echo ""

    if ! "$BG_SWITCH" rollback --pool backend; then
        log_error "回滚失败！请手动检查"
        exit 1
    fi

    echo ""
    log_ok "回滚完成"
}

# ==========================================
# 主流程
# ==========================================

# 解析参数
while [ $# -gt 0 ]; do
    case "$1" in
        --no-build)
            DO_BUILD=false
            shift
            ;;
        --mode)
            SWITCH_MODE="$2"
            shift 2
            ;;
        --rollback)
            ROLLBACK=true
            shift
            ;;
        --status)
            SHOW_STATUS=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "未知参数: $1"
            usage
            exit 1
            ;;
    esac
done

# 加载环境变量
if [ -f "$DOCKER_DIR/.env" ]; then
    set -a
    source "$DOCKER_DIR/.env"
    set +a
fi

# 执行操作
if [ "$SHOW_STATUS" = true ]; then
    "$BG_SWITCH" status --pool backend
elif [ "$ROLLBACK" = true ]; then
    do_rollback
else
    do_deploy
fi
