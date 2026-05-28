#!/usr/bin/env bash
# ============================================================
# config-sync.sh — GitOps 配置同步引擎（MVP Bash 版）
# ============================================================
# 功能：
#   1. 从 channels/channel-configs.json 读取渠道定义
#   2. 通过 OneAPI 管理 API 查询现有渠道列表
#   3. 计算 diff：新增 / 更新 / 删除
#   4. --dry-run 模式：仅显示差异
#   5. --apply 模式：执行同步
#   6. 操作前备份当前渠道配置
#   7. 审计日志记录到 logs/audit.log
#
# 用法：
#   ./scripts/config-sync.sh --dry-run          # 仅显示差异
#   ./scripts/config-sync.sh --apply            # 执行同步
#   ./scripts/config-sync.sh --apply --force    # 强制执行（跳过确认）
#
# 环境变量（从 docker/.env 自动加载）：
#   ONEAPI_URL         — OneAPI 地址（默认 http://localhost:3000）
#   ONEAPI_ROOT_TOKEN  — OneAPI Root Token
# ============================================================

set -euo pipefail

# ---------- 路径 ----------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_DIR/channels/channel-configs.json"
ENV_FILE="$PROJECT_DIR/docker/.env"
LOG_DIR="$PROJECT_DIR/logs"
AUDIT_LOG="$LOG_DIR/audit.log"
BACKUP_DIR="/tmp"

# ---------- 环境变量 ----------
ONEAPI_URL="${ONEAPI_URL:-http://localhost:3000}"
DRY_RUN="false"
APPLY="false"
FORCE="false"

# ---------- 颜色 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

log_info()   { echo -e "${BLUE}[INFO]${NC}   $*"; }
log_ok()     { echo -e "${GREEN}[OK]${NC}     $*"; }
log_warn()   { echo -e "${YELLOW}[WARN]${NC}   $*"; }
log_error()  { echo -e "${RED}[ERROR]${NC}  $*"; }
log_step()   { echo -e "\n${CYAN}━━━${NC} $* ${CYAN}━━━${NC}"; }
log_add()    { echo -e "${GREEN}[+]${NC}     $*"; }
log_update() { echo -e "${YELLOW}[~]${NC}     $*"; }
log_delete() { echo -e "${RED}[-]${NC}     $*"; }
log_skip()   { echo -e "       $*"; }

# ---------- 初始化 ----------
mkdir -p "$LOG_DIR"
touch "$AUDIT_LOG"

# ---------- 加载环境变量 ----------
load_env() {
  if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE" 2>/dev/null || true
    set +a
  fi
}

# ---------- 解析环境变量占位符 ----------
resolve_env_var() {
  local raw="$1"
  if [[ "$raw" =~ ^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$ ]]; then
    local var_name="${BASH_REMATCH[1]}"
    echo "${!var_name:-}"
  else
    echo "$raw"
  fi
}

# ---------- 审计日志 ----------
audit_log() {
  local action="$1" target="$2" detail="$3"
  local timestamp
  timestamp=$(date -Iseconds)
  echo "[$timestamp] action=$action target=$target detail=$detail" >> "$AUDIT_LOG"
  log_info "审计: $action | $target | $detail"
}

# ---------- OneAPI API 调用 ----------
oneapi_api() {
  local method="$1" endpoint="$2" data="${3:-}"

  if [ -z "${ONEAPI_ROOT_TOKEN:-}" ]; then
    log_error "ONEAPI_ROOT_TOKEN 未设置"
    exit 1
  fi

  if [ -n "$data" ]; then
    curl -s -X "$method" "$ONEAPI_URL$endpoint" \
      -H "Authorization: Bearer $ONEAPI_ROOT_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$data"
  else
    curl -s -X "$method" "$ONEAPI_URL$endpoint" \
      -H "Authorization: Bearer $ONEAPI_ROOT_TOKEN"
  fi
}

# ---------- 获取 OneAPI 现有渠道完整列表 ----------
get_remote_channels() {
  oneapi_api "GET" "/api/channel/?p=0&page_size=200" | jq '.' 2>/dev/null || echo "{}"
}

# ---------- 获取 OneAPI 渠道简要信息（用于 diff） ----------
get_remote_channel_summary() {
  oneapi_api "GET" "/api/channel/?p=0&page_size=200" | \
    jq '[.data[]? | {id, name, type, base_url, key: (.key // ""), models, weight, status}]' 2>/dev/null || echo "[]"
}

# ---------- 备份当前渠道配置 ----------
backup_current_config() {
  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)
  local backup_file="$BACKUP_DIR/channel_backup_${timestamp}.json"

  log_info "备份当前 OneAPI 渠道配置..."
  get_remote_channels > "$backup_file"

  local size
  size=$(wc -c < "$backup_file" 2>/dev/null || echo "0")
  if [ "$size" -gt 10 ]; then
    log_ok "渠道配置已备份到: $backup_file ($(du -h "$backup_file" | cut -f1))"
    audit_log "backup" "channels" "backup_file=$backup_file size=$size"
    echo "$backup_file"
  else
    log_warn "备份可能为空，跳过 ($backup_file)"
    echo ""
  fi
}

# ---------- 从本地 config 读取期望的渠道定义 ----------
get_local_channels() {
  if [ ! -f "$CONFIG_FILE" ]; then
    log_error "配置文件不存在: $CONFIG_FILE"
    exit 1
  fi
  jq -c '.channels[]' "$CONFIG_FILE" 2>/dev/null
}

# ---------- 查找远程渠道（按名称） ----------
find_remote_by_name() {
  local name="$1" remote_json="$2"
  echo "$remote_json" | jq -r --arg name "$name" '.[] | select(.name == $name)' 2>/dev/null
}

# ---------- 检查两个渠道是否需要更新 ----------
# 比较 base_url, models, weight, status
channel_needs_update() {
  local local_ch="$1" remote_ch="$2"

  local local_base_url remote_base_url
  local_base_url=$(echo "$local_ch" | jq -r '.base_url')
  remote_base_url=$(echo "$remote_ch" | jq -r '.base_url')

  local local_models remote_models
  local_models=$(echo "$local_ch" | jq -r '.models')
  remote_models=$(echo "$remote_ch" | jq -r '.models')

  local local_weight remote_weight
  local_weight=$(echo "$local_ch" | jq -r '.weight')
  remote_weight=$(echo "$remote_ch" | jq -r '.weight // 0')
  # 确保类型一致
  local_weight=$(echo "$local_weight" | jq -r 'if type == "number" then . else 0 end')
  remote_weight=$(echo "$remote_weight" | jq -r 'if type == "number" then . else 0 end')

  local local_status remote_status
  local_status=$(echo "$local_ch" | jq -r '.status')
  remote_status=$(echo "$remote_ch" | jq -r '.status // 1')

  if [ "$local_base_url" != "$remote_base_url" ]; then return 0; fi
  if [ "$local_models" != "$remote_models" ]; then return 0; fi
  if [ "$local_weight" != "$remote_weight" ]; then return 0; fi
  if [ "$local_status" != "$remote_status" ]; then return 0; fi

  return 1  # 不需要更新
}

# ---------- 创建渠道 ----------
create_remote_channel() {
  local channel_json="$1"

  local name base_url key_value models weight type status
  name=$(echo "$channel_json" | jq -r '.name')
  base_url=$(echo "$channel_json" | jq -r '.base_url')
  key_value=$(echo "$channel_json" | jq -r '.keys[0]')
  key_value=$(resolve_env_var "$key_value")
  models=$(echo "$channel_json" | jq -r '.models')
  weight=$(echo "$channel_json" | jq -r '.weight')
  type=$(echo "$channel_json" | jq -r '.type // 3')
  status=$(echo "$channel_json" | jq -r '.status // 1')

  if [ -z "$key_value" ] || [ "$key_value" = "null" ]; then
    log_error "渠道「$name」Key 解析失败"
    return 1
  fi

  local payload
  payload=$(jq -n \
    --argjson type "$type" \
    --arg name "$name" \
    --arg base_url "$base_url" \
    --arg key "$key_value" \
    --arg models "$models" \
    --argjson weight "$weight" \
    --argjson status "$status" \
    '{
      type: $type,
      name: $name,
      base_url: $base_url,
      key: $key,
      models: $models,
      model_mapping: "",
      groups: ["default"],
      status: $status,
      priority: 1,
      weight: $weight
    }')

  local resp
  resp=$(oneapi_api "POST" "/api/channel/" "$payload")
  local success
  success=$(echo "$resp" | jq -r '.success // false')

  if [ "$success" = "true" ]; then
    local new_id
    new_id=$(echo "$resp" | jq -r '.data.id // .data // ""')
    log_add "创建渠道: $name (ID=$new_id, weight=$weight)"
    audit_log "channel.create" "$name" "id=$new_id weight=$weight base_url=$base_url"
    return 0
  else
    local msg
    msg=$(echo "$resp" | jq -r '.message // "未知错误"')
    log_error "创建渠道「$name」失败: $msg"
    audit_log "channel.create.error" "$name" "error=$msg"
    return 1
  fi
}

# ---------- 更新渠道 ----------
update_remote_channel() {
  local channel_id="$1" channel_json="$2"

  local name base_url key_value models weight status
  name=$(echo "$channel_json" | jq -r '.name')
  base_url=$(echo "$channel_json" | jq -r '.base_url')
  key_value=$(echo "$channel_json" | jq -r '.keys[0]')
  key_value=$(resolve_env_var "$key_value")
  models=$(echo "$channel_json" | jq -r '.models')
  weight=$(echo "$channel_json" | jq -r '.weight')
  status=$(echo "$channel_json" | jq -r '.status // 1')

  local payload
  payload=$(jq -n \
    --argjson id "$channel_id" \
    --argjson type "$(echo "$channel_json" | jq -r '.type // 3')" \
    --arg name "$name" \
    --arg base_url "$base_url" \
    --arg key "$key_value" \
    --arg models "$models" \
    --argjson weight "$weight" \
    --argjson status "$status" \
    '{
      id: $id,
      type: $type,
      name: $name,
      base_url: $base_url,
      key: $key,
      models: $models,
      model_mapping: "",
      groups: ["default"],
      status: $status,
      priority: 1,
      weight: $weight
    }')

  local resp
  resp=$(oneapi_api "PUT" "/api/channel/" "$payload")
  local success
  success=$(echo "$resp" | jq -r '.success // false')

  if [ "$success" = "true" ]; then
    log_update "更新渠道: $name (ID=$channel_id, weight=$weight)"
    audit_log "channel.update" "$name" "id=$channel_id weight=$weight"
    return 0
  else
    local msg
    msg=$(echo "$resp" | jq -r '.message // "未知错误"')
    log_error "更新渠道「$name」失败: $msg"
    audit_log "channel.update.error" "$name" "error=$msg"
    return 1
  fi
}

# ---------- 禁用/删除渠道 ----------
disable_remote_channel() {
  local channel_id="$1" channel_name="$2"

  # OneAPI 没有删除 API，通过设置 status=0 禁用
  local payload
  payload=$(jq -n \
    --argjson id "$channel_id" \
    --argjson status 0 \
    '{id: $id, status: $status}')

  local resp
  resp=$(oneapi_api "PUT" "/api/channel/" "$payload")
  local success
  success=$(echo "$resp" | jq -r '.success // false')

  if [ "$success" = "true" ]; then
    log_delete "禁用渠道: $channel_name (ID=$channel_id)"
    audit_log "channel.disable" "$channel_name" "id=$channel_id reason=not_in_config"
    return 0
  else
    local msg
    msg=$(echo "$resp" | jq -r '.message // "未知错误"')
    log_error "禁用渠道「$channel_name」失败: $msg"
    return 1
  fi
}

# ---------- 计算差异并显示 ----------
compute_diff() {
  local remote_summary="$1"
  shift
  local local_channels=("$@")

  # 收集远程渠道名称
  local remote_names
  remote_names=$(echo "$remote_summary" | jq -r '.[]?.name // ""' 2>/dev/null)

  # 用于统计
  local add_count=0 update_count=0 delete_count=0 skip_count=0

  declare -a add_list update_list delete_list

  # 遍历本地配置中的每个渠道，判断是否需要新增或更新
  for channel_json in "${local_channels[@]}"; do
    local local_name
    local_name=$(echo "$channel_json" | jq -r '.name')

    # 查找远程是否有同名渠道
    local remote_ch
    remote_ch=$(find_remote_by_name "$local_name" "$remote_summary")

    if [ -z "$remote_ch" ] || [ "$remote_ch" = "null" ]; then
      # 远程不存在 → 需新增
      add_count=$((add_count + 1))
      add_list+=("$local_name")
    elif channel_needs_update "$channel_json" "$remote_ch"; then
      # 远程存在但配置不同 → 需更新
      update_count=$((update_count + 1))
      update_list+=("$local_name")
    else
      skip_count=$((skip_count + 1))
    fi
  done

  # 检查远程有但本地没有的渠道 → 需删除
  for remote_name in $remote_names; do
    local found=false
    for channel_json in "${local_channels[@]}"; do
      local local_name
      local_name=$(echo "$channel_json" | jq -r '.name')
      if [ "$local_name" = "$remote_name" ]; then
        found=true
        break
      fi
    done
    if [ "$found" = false ]; then
      delete_count=$((delete_count + 1))
      delete_list+=("$remote_name")
    fi
  done

  # 输出差异汇总
  echo ""
  echo "  ╔══════════════════════════════════════╗"
  echo "  ║   GitOps 配置差异分析                 ║"
  echo "  ╚══════════════════════════════════════╝"
  echo ""
  echo "  新增 (+)  : $add_count 个渠道"
  for ch in "${add_list[@]}"; do
    echo "    + $ch"
  done
  echo ""
  echo "  更新 (~)  : $update_count 个渠道"
  for ch in "${update_list[@]}"; do
    echo "    ~ $ch"
  done
  echo ""
  echo "  删除 (-)  : $delete_count 个渠道"
  for ch in "${delete_list[@]}"; do
    echo "    - $ch"
  done
  echo ""
  echo "  无变化    : $skip_count 个渠道"
  echo ""

  local total_changes=$((add_count + update_count + delete_count))
  if [ "$total_changes" -eq 0 ]; then
    log_ok "配置与 OneAPI 完全一致，无需同步"
  fi
}

# ---------- 执行同步 ----------
apply_sync() {
  local remote_summary="$1"
  shift
  local local_channels=("$@")

  local add_count=0 update_count=0 delete_count=0
  local errors=0

  # 1. 备份
  local backup_file
  backup_file=$(backup_current_config)

  # 2. 收集所有远程渠道（用于后续删除判断）
  local all_remote
  all_remote=$(echo "$remote_summary" | jq -r '[.[]?.name] | join("\n")' 2>/dev/null)

  # 3. 处理本地渠道：新增或更新
  for channel_json in "${local_channels[@]}"; do
    local local_name remote_ch
    local_name=$(echo "$channel_json" | jq -r '.name')
    remote_ch=$(find_remote_by_name "$local_name" "$remote_summary")

    if [ -z "$remote_ch" ] || [ "$remote_ch" = "null" ]; then
      # 新增
      if create_remote_channel "$channel_json"; then
        add_count=$((add_count + 1))
      else
        errors=$((errors + 1))
      fi
    elif channel_needs_update "$channel_json" "$remote_ch"; then
      # 更新
      local remote_id
      remote_id=$(echo "$remote_ch" | jq -r '.id')
      if update_remote_channel "$remote_id" "$channel_json"; then
        update_count=$((update_count + 1))
      else
        errors=$((errors + 1))
      fi
    fi
  done

  # 4. 处理远程多余渠道：禁用
  local local_names
  local_names=$(for ch in "${local_channels[@]}"; do echo "$ch" | jq -r '.name'; done)

  while IFS= read -r remote_name; do
    if [ -z "$remote_name" ]; then continue; fi
    if ! echo "$local_names" | grep -qF "$remote_name"; then
      local remote_id
      remote_id=$(echo "$remote_summary" | jq -r --arg name "$remote_name" '.[] | select(.name == $name) | .id' 2>/dev/null)
      if [ -n "$remote_id" ] && [ "$remote_id" != "null" ]; then
        if disable_remote_channel "$remote_id" "$remote_name"; then
          delete_count=$((delete_count + 1))
        else
          errors=$((errors + 1))
        fi
      fi
    fi
  done <<< "$all_remote"

  # 5. 汇总
  echo ""
  log_step "同步完成"
  echo "  新增: $add_count  |  更新: $update_count  |  禁用: $delete_count  |  失败: $errors"
  audit_log "sync.summary" "channels" "added=$add_count updated=$update_count disabled=$delete_count errors=$errors"

  # 6. 发送通知
  if [ -x "$SCRIPT_DIR/ops-notify.sh" ]; then
    local sync_msg="config-sync 完成: 新增${add_count} 更新${update_count} 禁用${delete_count}"
    if [ "$errors" -gt 0 ]; then
      "$SCRIPT_DIR/ops-notify.sh" --level warning --title "Config Sync 完成（有错误）" \
        --message "${sync_msg}，失败${errors}，详情见审计日志" || true
    else
      "$SCRIPT_DIR/ops-notify.sh" --level info --title "Config Sync 完成" \
        --message "$sync_msg" || true
    fi
  fi

  if [ "$errors" -gt 0 ]; then
    log_warn "同步存在 $errors 个错误，请检查审计日志: $AUDIT_LOG"
  fi
}

# ---------- 使用说明 ----------
usage() {
  cat <<EOF
用法: $0 [选项]

选项:
  --dry-run       仅显示 OneAPI 与本地配置的差异，不执行任何操作
  --apply         执行同步（将本地配置应用到 OneAPI）
  --force         与 --apply 配合，跳过确认提示
  --help, -h      显示此帮助

环境变量:
  ONEAPI_URL             OneAPI 地址（默认 http://localhost:3000）
  ONEAPI_ROOT_TOKEN      OneAPI Root Token（从 docker/.env 自动加载）

示例:
  $0 --dry-run                        # 查看差异
  $0 --apply                          # 执行同步（需确认）
  $0 --apply --force                  # 强制执行同步
EOF
  exit 0
}

# ---------- 主流程 ----------
main() {
  # 解析参数
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) DRY_RUN="true"; shift ;;
      --apply) APPLY="true"; shift ;;
      --force) FORCE="true"; shift ;;
      --help|-h) usage ;;
      *)
        echo "未知参数: $1"
        usage ;;
    esac
  done

  if [ "$DRY_RUN" = "false" ] && [ "$APPLY" = "false" ]; then
    log_error "请指定 --dry-run 或 --apply"
    echo ""
    usage
  fi

  echo ""
  echo "╔══════════════════════════════════════════════════╗"
  echo "║   AI API 聚合平台 — GitOps 配置同步引擎           ║"
  echo "║   模式: $(if [ "$DRY_RUN" = "true" ]; then echo 'DRY-RUN（仅查看）'; else echo 'APPLY（执行同步）'; fi)        ║"
  echo "╚══════════════════════════════════════════════════╝"
  echo ""

  # 加载环境
  load_env

  if [ ! -f "$CONFIG_FILE" ]; then
    log_error "配置文件不存在: $CONFIG_FILE"
    exit 1
  fi

  # 读取本地配置
  log_info "读取本地渠道配置: $CONFIG_FILE"
  local local_channels=()
  while IFS= read -r line; do
    local_channels+=("$line")
  done < <(get_local_channels)
  log_info "本地定义了 ${#local_channels[@]} 个渠道"

  # 获取远程渠道列表
  log_info "获取 OneAPI 现有渠道列表 ($ONEAPI_URL)..."
  local remote_summary
  remote_summary=$(get_remote_channel_summary)
  local remote_count
  remote_count=$(echo "$remote_summary" | jq 'length' 2>/dev/null || echo "0")
  log_info "OneAPI 现有 $remote_count 个渠道"

  # 审计日志：同步开始
  audit_log "sync.start" "config-sync" "mode=$(if [ "$DRY_RUN" = "true" ]; then echo 'dry-run'; else echo 'apply'; fi) local=${#local_channels[@]} remote=$remote_count"

  # DRY-RUN 模式：计算并显示差异
  if [ "$DRY_RUN" = "true" ]; then
    compute_diff "$remote_summary" "${local_channels[@]}"
    audit_log "sync.dry_run" "config-sync" "diff_computed"
    exit 0
  fi

  # APPLY 模式
  if [ "$APPLY" = "true" ]; then
    # 先显示差异
    compute_diff "$remote_summary" "${local_channels[@]}"

    # 确认
    if [ "$FORCE" != "true" ]; then
      echo ""
      read -r -p "确认执行以上同步操作？[y/N]: " confirm
      if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "已取消同步"
        audit_log "sync.cancel" "config-sync" "user_cancelled"
        exit 0
      fi
    fi

    echo ""
    log_step "执行同步"
    apply_sync "$remote_summary" "${local_channels[@]}"
  fi
}

main "$@"
