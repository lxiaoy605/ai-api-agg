#!/usr/bin/env bash
# =============================================
# AI API 聚合平台 — 多渠道健康检查脚本
# =============================================
# 功能：
#   1. 测试每个渠道上游 /v1/models 端点（直连，10s 超时 + 2 次重试）
#   2. 测试 OneAPI 网关内部状态
#   3. 外部域名检测（https://<ONEAPI_DOMAIN>/v1/models）
#   4. 彩色输出 + 日志写入 logs/healthcheck.log
#
# 用法：
#   ./healthcheck.sh                    # 标准模式
#   ./healthcheck.sh --json             # JSON 输出（供 failover.sh 调用）
#   ./healthcheck.sh --no-external      # 跳过外部域名检测
#   ./healthcheck.sh --channel deepseek  # 仅检测指定渠道
#
# 环境变量：
#   ONEAPI_URL           OneAPI 内部地址（默认 http://localhost:3000）
#   ONEAPI_DOMAIN        生产域名（默认 aiflowhub.ai）
#   DEEPSEEK_API_KEY     DeepSeek API Key
#   ZHIPU_ZAI_API_KEY    智谱 Z.ai API Key
#   MIMO_API_KEY         小米 MiMo API Key
# =============================================

set -euo pipefail

# ==========================================
# 配置
# ==========================================
ONEAPI_URL="${ONEAPI_URL:-http://localhost:3000}"
ONEAPI_DOMAIN="${ONEAPI_DOMAIN:-aiflowhub.ai}"
TIMEOUT="${HEALTHCHECK_TIMEOUT:-10}"
MAX_RETRIES="${HEALTHCHECK_RETRIES:-2}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_DIR/logs"
LOG_FILE="$LOG_DIR/healthcheck.log"
ENV_FILE="$PROJECT_DIR/docker/.env"

mkdir -p "$LOG_DIR"

# ==========================================
# 颜色
# ==========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ==========================================
# 渠道定义（与 channel-configs.json 保持一致）
# ==========================================
# 格式: name|base_url|models_endpoint|key_env_var
CHANNELS=(
  "DeepSeek|https://api.deepseek.com|/v1/models|DEEPSEEK_API_KEY"
  "智谱 Z.ai|https://open.bigmodel.cn/api/paas/v4|/models|ZHIPU_ZAI_API_KEY"
  "小米 MiMo|https://token-plan-sgp.xiaomimimo.com/v1|/models|MIMO_API_KEY"
)

# ==========================================
# 工具函数
# ==========================================

# 输出模式: text (默认) 或 json
OUTPUT_MODE="text"
SKIP_EXTERNAL=false
TARGET_CHANNEL=""

log_text() {
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo -e "$*" | tee -a "$LOG_FILE"
}

log_json_item() {
  # JSON 条目由 end_json 汇总输出
  return 0
}

# 从 docker/.env 加载环境变量
load_env_file() {
  if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE" 2>/dev/null || true
    set +a
  fi
}

# 获取渠道 API Key（支持别名回退）
get_key() {
  local var_name="$1"
  local val="${!var_name:-}"

  # ZHIPU_ZAI_API_KEY 回退: 如果未设置，尝试 ZHIPU_API_KEY
  if [ -z "$val" ] && [ "$var_name" = "ZHIPU_ZAI_API_KEY" ]; then
    val="${ZHIPU_API_KEY:-}"
  fi

  echo "$val"
}

# 统一通知脚本路径
NOTIFY_SCRIPT="$SCRIPT_DIR/ops-notify.sh"

# 发送运维通知（通过统一通知脚本 ops-notify.sh）
send_notify() {
  local level="$1" title="$2" message="$3"
  if [ -x "$NOTIFY_SCRIPT" ]; then
    "$NOTIFY_SCRIPT" --level "$level" --title "$title" --message "$message" --silent || true
  fi
}

# HTTP 检测（含重试 + 延迟测量）
# 参数: url, headers (JSON 字符串), 超时秒数, 最大重试次数
# 输出: status_code:latency (如 "200:0.345")
do_request() {
  local url="$1"
  local headers_json="${2:-{}}"
  local timeout="${3:-$TIMEOUT}"
  local max_retries="${4:-$MAX_RETRIES}"

  local attempt=0
  local result=""

  # 构建 curl header 参数
  local header_args=()
  if [ -n "$headers_json" ] && [ "$headers_json" != "{}" ]; then
    while IFS='=' read -r key value; do
      [ -n "$key" ] && header_args+=(-H "$key: $value")
    done < <(echo "$headers_json" | jq -r 'to_entries[] | "\(.key)=\(.value)"' 2>/dev/null)
  fi

  while [ $attempt -le $max_retries ]; do
    local http_code total_time
    local resp
    resp=$(curl -s -w "\n%{http_code}:%{time_total}" \
      --connect-timeout "$timeout" \
      --max-time "$timeout" \
      "${header_args[@]}" \
      "$url" 2>/dev/null) || true

    http_code=$(echo "$resp" | tail -1 | cut -d: -f1)
    total_time=$(echo "$resp" | tail -1 | cut -d: -f2)

    # 200 或 401（认证通过但无权限列出所有模型）也算成功
    # 因为 401 说明服务可达，只是权限问题
    case "$http_code" in
      200|401)
        echo "${http_code}:${total_time}"
        return 0
        ;;
    esac

    attempt=$((attempt + 1))
    if [ $attempt -le $max_retries ]; then
      sleep 2
    fi
  done

  # 所有重试失败
  echo "${http_code:-000}:${total_time:-0.000}"
  return 1
}

# 格式化延迟输出（带颜色）
format_latency() {
  local latency="$1"
  local sec
  sec=$(printf "%.3f" "${latency:-0}" 2>/dev/null || echo "0.000")

  if (( $(echo "$sec < 1.0" | bc -l 2>/dev/null || echo 0) )); then
    echo -e "${GREEN}${sec}s${NC}"
  elif (( $(echo "$sec < 3.0" | bc -l 2>/dev/null || echo 0) )); then
    echo -e "${YELLOW}${sec}s${NC}"
  else
    echo -e "${RED}${sec}s${NC}"
  fi
}

# ==========================================
# 检测函数
# ==========================================

# 后端端口（蓝绿部署）
BACKEND_BLUE_PORT="${BACKEND_BLUE_PORT:-8082}"
BACKEND_GREEN_PORT="${BACKEND_GREEN_PORT:-8083}"

# 检测单个渠道上游 API
check_channel() {
  local name="$1"
  local base_url="$2"
  local endpoint="$3"
  local key_var="$4"

  local api_key
  api_key=$(get_key "$key_var")

  if [ -z "$api_key" ]; then
    if [ "$OUTPUT_MODE" = "json" ]; then
      echo "{\"channel\":\"$name\",\"status\":\"SKIP\",\"error\":\"未配置 API Key ($key_var)\"}"
    else
      echo -e "  ${YELLOW}⚠${NC} $name — 未配置 API Key ($key_var)，跳过"
    fi
    return 0
  fi

  local url="${base_url}${endpoint}"
  local headers
  headers=$(jq -n --arg key "Bearer $api_key" '{Authorization: $key}')

  local result
  result=$(do_request "$url" "$headers" "$TIMEOUT" "$MAX_RETRIES") || true

  local http_code="${result%%:*}"
  local latency="${result##*:}"

  local status="FAIL"
  local color="$RED"
  local icon="✗"

  case "$http_code" in
    200)
      status="OK"
      color="$GREEN"
      icon="✓"
      ;;
    401)
      status="OK"
      color="$GREEN"
      icon="✓"
      ;;
    000)
      status="FAIL"
      color="$RED"
      icon="✗"
      ;;
  esac

  if [ "$OUTPUT_MODE" = "json" ]; then
    echo "{\"channel\":\"$name\",\"status\":\"$status\",\"http_code\":$http_code,\"latency\":$latency,\"url\":\"$url\"}"
  else
    local latency_fmt
    latency_fmt=$(format_latency "$latency")
    echo -e "  ${color}${icon}${NC} $name — $status (HTTP $http_code, ${latency_fmt})"
  fi

  [ "$status" = "OK" ]
}

# 检测 OneAPI 内部状态
check_oneapi_internal() {
  local url="$ONEAPI_URL/api/status"
  local result
  result=$(do_request "$url" "{}" "$TIMEOUT" "1") || true

  local http_code="${result%%:*}"
  local latency="${result##*:}"

  local status="FAIL"
  local color="$RED"
  local icon="✗"

  if [ "$http_code" = "200" ]; then
    status="OK"
    color="$GREEN"
    icon="✓"
  fi

  if [ "$OUTPUT_MODE" = "json" ]; then
    echo "{\"channel\":\"OneAPI(内部)\",\"status\":\"$status\",\"http_code\":$http_code,\"latency\":$latency,\"url\":\"$url\"}"
  else
    local latency_fmt
    latency_fmt=$(format_latency "$latency")
    echo -e "  ${color}${icon}${NC} OneAPI 内部状态 — $status (HTTP $http_code, ${latency_fmt})"
  fi

  [ "$status" = "OK" ]
}

# 检测外部域名
check_external() {
  if [ "$SKIP_EXTERNAL" = true ]; then
    return 0
  fi

  local url="https://${ONEAPI_DOMAIN}/v1/models"
  local result
  result=$(do_request "$url" "{}" "$TIMEOUT" "1") || true

  local http_code="${result%%:*}"
  local latency="${result##*:}"

  local status="FAIL"
  local color="$RED"
  local icon="✗"

  # 外部域名可能返回 200/401/404（取决于 Nginx 配置和上游状态）
  case "$http_code" in
    200|401)
      status="OK"
      color="$GREEN"
      icon="✓"
      ;;
    404)
      # Nginx 可达但路由不存在或上游未启动
      status="WARN"
      color="$YELLOW"
      icon="⚠"
      ;;
  esac

  if [ "$OUTPUT_MODE" = "json" ]; then
    echo "{\"channel\":\"外部域名\",\"status\":\"$status\",\"http_code\":$http_code,\"latency\":$latency,\"url\":\"$url\"}"
  else
    local latency_fmt
    latency_fmt=$(format_latency "$latency")
    echo -e "  ${color}${icon}${NC} 外部域名 https://${ONEAPI_DOMAIN} — $status (HTTP $http_code, ${latency_fmt})"
  fi

  case "$status" in
    OK) return 0 ;;
    WARN) return 1 ;;
    *) return 2 ;;
  esac
}

# 检测 Go 后端实例
check_backend_instance() {
  local label="$1"
  local port="$2"

  local url="http://localhost:${port}/health"
  local result
  result=$(do_request "$url" "{}" "$TIMEOUT" "1") || true

  local http_code="${result%%:*}"
  local latency="${result##*:}"

  local status="FAIL"
  local color="$RED"
  local icon="✗"

  if [ "$http_code" = "200" ]; then
    status="OK"
    color="$GREEN"
    icon="✓"
  fi

  if [ "$OUTPUT_MODE" = "json" ]; then
    echo "{\"channel\":\"后端($label)\",\"status\":\"$status\",\"http_code\":$http_code,\"latency\":$latency,\"url\":\"$url\"}"
  else
    local latency_fmt
    latency_fmt=$(format_latency "$latency")
    echo -e "  ${color}${icon}${NC} Go 后端 ($label) — $status (HTTP $http_code, ${latency_fmt})"
  fi

  [ "$status" = "OK" ]
}

# 检测后端蓝绿实例
check_backend_blue() {
  check_backend_instance "Blue :${BACKEND_BLUE_PORT}" "$BACKEND_BLUE_PORT"
}

check_backend_green() {
  check_backend_instance "Green :${BACKEND_GREEN_PORT}" "$BACKEND_GREEN_PORT"
}

# ==========================================
# 主流程
# ==========================================

main() {
  load_env_file

  # 解析参数
  while [ $# -gt 0 ]; do
    case "$1" in
      --json)
        OUTPUT_MODE="json"
        ;;
      --no-external)
        SKIP_EXTERNAL=true
        ;;
      --channel)
        TARGET_CHANNEL="$2"
        shift
        ;;
      *)
        ;;
    esac
    shift
  done

  if [ "$OUTPUT_MODE" = "text" ]; then
    {
      echo ""
      echo "========================================="
      echo " AI API 聚合平台 — 多渠道健康检查"
      echo " 时间: $(date '+%Y-%m-%d %H:%M:%S')"
      echo " OneAPI: $ONEAPI_URL"
      echo " 域名: $ONEAPI_DOMAIN"
      echo "========================================="
      echo ""
    } | tee -a "$LOG_FILE"
  fi

  local total=0 ok=0 fail=0 warn=0

  # 检测各渠道上游
  for channel_def in "${CHANNELS[@]}"; do
    IFS='|' read -r name base_url endpoint key_var <<< "$channel_def"

    if [ -n "$TARGET_CHANNEL" ] && [ "$name" != "$TARGET_CHANNEL" ]; then
      continue
    fi

    if check_channel "$name" "$base_url" "$endpoint" "$key_var"; then
      ok=$((ok + 1))
    else
      fail=$((fail + 1))
    fi
    total=$((total + 1))
  done

  if [ "$OUTPUT_MODE" = "text" ]; then
    echo ""
  fi

  # 检测 OneAPI 内部
  if check_oneapi_internal; then
    ok=$((ok + 1))
  else
    fail=$((fail + 1))
  fi
  total=$((total + 1))

  if [ "$OUTPUT_MODE" = "text" ]; then
    echo ""
  fi

  # 检测 Go 后端蓝绿实例
  if check_backend_blue; then ok=$((ok + 1)); else fail=$((fail + 1)); fi
  total=$((total + 1))
  if check_backend_green; then ok=$((ok + 1)); else fail=$((fail + 1)); fi
  total=$((total + 1))

  if [ "$OUTPUT_MODE" = "text" ]; then
    echo ""
  fi

  # 检测外部域名（3 种状态：OK=0, WARN=1, FAIL=2）
  check_external
  local ext_rc=$?
  case $ext_rc in
    0) ok=$((ok + 1)) ;;
    1) warn=$((warn + 1)) ;;
    2) fail=$((fail + 1)) ;;
  esac
  total=$((total + 1))

  # 汇总
  if [ "$OUTPUT_MODE" = "text" ]; then
    echo ""
    echo "─────────────────────────────────────────"
    echo -e " 汇总: ${GREEN}通过 $ok${NC} / ${RED}失败 $fail${NC} / ${YELLOW}警告 $warn${NC} / 总计 $total"
    echo "─────────────────────────────────────────"

    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    if [ "$fail" -eq 0 ]; then
      echo -e " ${GREEN}✓ 所有检查通过${NC}"
      echo "[$timestamp] OK: $ok/$total 通过, 失败 $fail" >> "$LOG_FILE"
    else
      echo -e " ${RED}✗ $fail 项检查失败${NC}"
      echo "[$timestamp] FAIL: $ok/$total 通过, 失败 $fail" >> "$LOG_FILE"
    fi
    echo ""
  fi

  return $fail
}

main "$@"
