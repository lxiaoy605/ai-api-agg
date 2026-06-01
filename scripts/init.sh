#!/bin/bash
# =============================================
# AI API 聚合平台 — 一键初始化脚本 v3.0
# =============================================
# 改进：
#   1. API Key 先验证，再建渠道（避免过期 Key 创建死渠道）
#   2. 自动发现模型（调各厂商 /v1/models，不硬编码模型名）
#   3. Provider 级配置，不逐个指定模型
#   4. 过期/欠费/异常的 Key 跳过并清楚提示
#   5. 幂等安全 — 已存在渠道不重复创建
#
# 用法：
#   bash scripts/init.sh                # 完整初始化
#   bash scripts/init.sh --dry-run      # 仅验证 Key，不创建渠道
#   bash scripts/init.sh --force        # 删除旧渠道后重新创建
# =============================================

set -euo pipefail

# ---- 颜色 ----
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ok()    { echo -e "  ${GREEN}✅${NC} $*"; }
fail()  { echo -e "  ${RED}❌${NC} $*"; }
warn()  { echo -e "  ${YELLOW}⚠️${NC}  $*"; }
info()  { echo -e "  ${BLUE}ℹ️${NC}  $*"; }
step()  { echo -e "\n${BOLD}${CYAN}━━━ $* ━━━${NC}"; }

# ---- 参数 ----
DRY_RUN=false; FORCE=false
for arg in "$@"; do
  case "$arg" in --dry-run) DRY_RUN=true ;; --force) FORCE=true ;; esac
done

# ---- 路径 ----
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/stack/.env"
ONEAPI_URL="${ONEAPI_URL:-http://localhost:3001}"
ADMIN_KEY="${ADMIN_KEY:-94686403648a4ae7b069ffcd9383332e}"

# ---- Provider 注册表 ----
# 格式: "渠道名|环境变量名|BaseURL|OneAPI类型"
# 模型名不硬编码，运行时通过 /v1/models 自动发现
PROVIDERS=(
  "DeepSeek-1|DEEPSEEK_API_KEY|https://api.deepseek.com/v1|3"
  "DeepSeek-2|DEEPSEEK_API_KEY_2|https://api.deepseek.com/v1|3"
  "Zhipu-1|ZHIPU_API_KEY|https://open.bigmodel.cn/api/paas/v4|3"
  "Zhipu-2|ZHIPU_API_KEY_2|https://open.bigmodel.cn/api/paas/v4|3"
  "MiMo-1|MIMO_API_KEY|https://api.xiaomimimo.com/v1|3"
  "MiMo-2|MIMO_API_KEY_2|https://api.xiaomimimo.com/v1|3"
)

# =============================================
# 阶段 0: 环境准备
# =============================================
load_env() {
  if [ -f "$ENV_FILE" ]; then
    set -a; source "$ENV_FILE" 2>/dev/null || true; set +a
  else
    echo -e "${RED}找不到 .env: $ENV_FILE${NC}"; exit 1
  fi
}

check_oneapi() {
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
    -H "Authorization: Bearer $ADMIN_KEY" "$ONEAPI_URL/api/status" 2>/dev/null || echo "000")
  if [ "$code" = "200" ]; then
    ok "OneAPI 连接正常 ($ONEAPI_URL)"
  else
    fail "OneAPI 不可达 (HTTP $code)"
    echo "  请确认 OneAPI 已启动: docker compose -f docker-compose.yml ps"
    exit 1
  fi
}

# =============================================
# 阶段 1: API Key 验证 + 模型发现
# =============================================
# 调各厂商 /v1/models，验证 Key 是否有效 + 获取可用模型列表
# 返回: "模型列表字符串"（逗号分隔），失败返回空
validate_and_discover() {
  local name="$1" base_url="$2" api_key="$3"

  # 调 /v1/models（OpenAI 兼容接口）
  local resp code
  resp=$(curl -s --max-time 15 -w "\n%{http_code}" \
    -H "Authorization: Bearer $api_key" \
    "$base_url/models" 2>/dev/null)
  code=$(echo "$resp" | tail -1)
  local body=$(echo "$resp" | head -n -1)

  if [ "$code" != "200" ]; then
    # 提取错误信息
    local err_msg
    err_msg=$(echo "$body" | python3 -c "
import json,sys
try:
  d=json.load(sys.stdin)
  print(d.get('error',{}).get('message','') or d.get('message','') or d.get('msg','') or 'HTTP $code')
except: print('HTTP $code')
" 2>/dev/null || echo "HTTP $code")
    # stderr: 用户可见；stdout: 被调用者捕获
    fail "$name → Key 无效: $err_msg" >&2
    return 1
  fi

  # 提取模型 ID 列表
  local models
  models=$(echo "$body" | python3 -c "
import json,sys
d=json.load(sys.stdin)
ids=[m['id'] for m in d.get('data',[]) if m.get('id')]
# 过滤掉 embedding/rerank/moderation 等非对话模型
exclude=('embedding','rerank','moderation','whisper','tts','dall-e','bge-','text-embedding')
filtered=[m for m in ids if not any(e in m.lower() for e in exclude)]
print(','.join(filtered))
" 2>/dev/null)

  if [ -z "$models" ]; then
    warn "$name → Key 有效，但未返回模型列表（可能 API 结构不同）" >&2
    return 1
  fi

  local count=$(echo "$models" | tr ',' '\n' | wc -l)
  ok "$name → Key 有效，发现 $count 个模型: $models" >&2
  echo "$models"
  return 0
}

# =============================================
# 阶段 2: 渠道创建
# =============================================
create_channel() {
  local name="$1" base_url="$2" api_key="$3" models="$4" otype="$5"
  local payload resp

  payload=$(python3 -c "
import json
print(json.dumps({
  'type': $otype,
  'name': '$name',
  'base_url': '$base_url',
  'key': '$api_key',
  'models': '$models',
  'model_mapping': '',
  'groups': ['default'],
  'status': 1,
  'priority': 1,
  'weight': 1
}))
")

  resp=$(curl -s --max-time 10 -X POST \
    -H "Authorization: Bearer $ADMIN_KEY" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "$ONEAPI_URL/api/channel/")

  local success
  success=$(echo "$resp" | python3 -c "import json,sys; print(json.load(sys.stdin).get('success',False))" 2>/dev/null || echo "false")

  if [ "$success" = "True" ]; then
    local cid
    cid=$(echo "$resp" | python3 -c "import json,sys; print(json.load(sys.stdin)['data'])" 2>/dev/null)
    ok "渠道「$name」创建成功 (ID=$cid)"
    return 0
  else
    local err
    err=$(echo "$resp" | python3 -c "import json,sys; print(json.load(sys.stdin).get('message','unknown'))" 2>/dev/null || echo "unknown")
    fail "渠道「$name」创建失败: $err"
    return 1
  fi
}

# =============================================
# 阶段 1.5: 生成前端模型展示数据
# =============================================
# 从 model-metadata.json 模板匹配发现的有效模型 ID，
# 生成 frontend/src/data/models-data.json
generate_model_data() {
  local metadata_file="$PROJECT_DIR/channels/model-metadata.json"
  local output_dir="$PROJECT_DIR/frontend/src/data"
  local output_file="$output_dir/models-data.json"

  if [ ! -f "$metadata_file" ]; then
    warn "模型元数据模板不存在: $metadata_file"
    warn "请先创建 channels/model-metadata.json"
    return 1
  fi

  if [ ${#VALID_PROVIDERS[@]} -eq 0 ]; then
    warn "没有已验证的 Provider，跳过模型数据生成"
    return 1
  fi

  python3 << 'PYEOF'
import json, sys, os

metadata_file = os.environ.get('METADATA_FILE', '')
output_file = os.environ.get('OUTPUT_FILE', '')

# 收集所有发现的有效模型 ID 及其 provider/渠道类型
# 从环境变量传递（序列化 JSON）
models_input = os.environ.get('DISCOVERED_MODELS', '{}')

try:
  with open(metadata_file) as f:
    metadata = json.load(f)
except (FileNotFoundError, json.JSONDecodeError) as e:
  print(f"failed_to_read_metadata:{e}")
  sys.exit(1)

try:
  discovered = json.loads(models_input)
except json.JSONDecodeError as e:
  print(f"failed_to_parse_models:{e}")
  sys.exit(1)

# discovered 格式: { "model_id": "provider_channel" }
# 例如: { "deepseek-v4-flash": "DeepSeek" }

models_array = []
for model_id, provider_name in discovered.items():
  if model_id in metadata:
    tmpl = metadata[model_id]
    models_array.append({
      "id": model_id,
      "name": tmpl.get("name", model_id),
      "provider": tmpl.get("provider", provider_name),
      "providerLogo": tmpl.get("providerLogo", ""),
      "description": tmpl.get("description", ""),
      "inputPrice": tmpl.get("inputPrice", ""),
      "outputPrice": tmpl.get("outputPrice", ""),
      "contextWindow": tmpl.get("contextWindow", ""),
      "maxTokens": tmpl.get("maxTokens", ""),
      "status": "available",
      "category": tmpl.get("category", "chat"),
      "features": tmpl.get("features", []),
      "codeExample": tmpl.get("codeExample", {})
    })
  else:
    # 未在模板中找到，自动生成基本元数据
    # 推导 name：将 ID 中的 - 替换为空格，首字母大写
    derived_name = " ".join(w.capitalize() if w[0].islower() else w for w in model_id.replace("-", " ").replace(".", " ").split())
    sys.stderr.write(f"  ⚠️  模型「{model_id}」不在元数据模板中，已自动生成基础信息（厂商: {provider_name}）\n")
    models_array.append({
      "id": model_id,
      "name": derived_name,
      "provider": provider_name,
      "providerLogo": provider_name[:2].upper() if provider_name else "",
      "description": f"{provider_name} 模型 {model_id}",
      "inputPrice": "",
      "outputPrice": "",
      "contextWindow": "",
      "maxTokens": "",
      "status": "available",
      "category": "chat",
      "features": [],
      "codeExample": {
        "curl": f"curl {{API_BASE}}/chat/completions \\n  -H \"Content-Type: application/json\" \\n  -H \"Authorization: Bearer \$API_KEY\" \\n  -d '{{\\n    \"model\": \"{model_id}\",\\\n    \"messages\": [{{\"role\": \"user\", \"content\": \"你好\"}}]\\\n  }}'",
        "python": f"import openai\n\nclient = openai.OpenAI(\n    base_url=\"{{API_BASE}}\",\n    api_key=\"your-api-key\"\n)\n\nresponse = client.chat.completions.create(\n    model=\"{model_id}\",\n    messages=[{{\"role\": \"user\", \"content\": \"你好\"}}]\n)\nprint(response.choices[0].message.content)",
        "nodejs": f"import OpenAI from \"openai\";\n\nconst client = new OpenAI({{\n  baseURL: \"{{API_BASE}}\",\n  apiKey: \"your-api-key\",\n}});\n\nconst response = await client.chat.completions.create({{\n  model: \"{model_id}\",\n  messages: [{{ role: \"user\", content: \"你好\" }}],\n}});\nconsole.log(response.choices[0].message.content);"
      }
    })

# 写文件
os.makedirs(os.path.dirname(output_file), exist_ok=True)
with open(output_file, 'w', encoding='utf-8') as f:
  json.dump(models_array, f, ensure_ascii=False, indent=2)

print(f"written:{len(models_array)}")
PYEOF

  local py_exit=$?
  if [ "$py_exit" -ne 0 ]; then
    fail "模型数据生成失败"
    return 1
  fi

  ok "模型数据已写入: $output_file"
  return 0
}

# 从 VALID_PROVIDERS 中提取模型列表，构建 {model_id: provider_name} 映射
collect_discovered_models() {
  local result="{}"
  local sep=""
  for entry in "${VALID_PROVIDERS[@]}"; do
    IFS='|' read -r name base_url api_key models otype <<< "$entry"
    # 提取 provider 简称（渠道名去掉 - 及后缀）
    local provider_name="${name%%-*}"
    case "$provider_name" in
      DeepSeek) provider_name="DeepSeek" ;;
      Zhipu) provider_name="智谱 Z.ai" ;;
      MiMo) provider_name="小米 MiMo" ;;
    esac
    IFS=',' read -ra model_list <<< "$models"
    for m in "${model_list[@]}"; do
      m="$(echo "$m" | xargs | tr '[:upper:]' '[:lower:]')"
      if [ -n "$m" ]; then
        # Check if this model already in result
        if ! echo "$result" | python3 -c "import json,sys; d=json.load(sys.stdin); print('$m' in d)" 2>/dev/null | grep -q True; then
          # Use python to add to dict
          result=$(python3 -c "
import json
d = json.loads('''$result''')
d['$m'] = '$provider_name'
print(json.dumps(d))
" 2>/dev/null)
        fi
      fi
    done
  done
  echo "$result"
}

# 检查渠道是否已存在（幂等）
channel_exists() {
  local name="$1"
  local count
  count=$(curl -s --max-time 5 -H "Authorization: Bearer $ADMIN_KEY" \
    "$ONEAPI_URL/api/channel/?p=0&page_size=100" | \
    python3 -c "
import json,sys
data=json.load(sys.stdin).get('data',[])
matches=[c for c in data if c.get('name')=='$name']
print(len(matches))
" 2>/dev/null || echo "0")
  [ "$count" -gt 0 ]
}

delete_channel_by_name() {
  local name="$1"
  local cid
  cid=$(curl -s --max-time 5 -H "Authorization: Bearer $ADMIN_KEY" \
    "$ONEAPI_URL/api/channel/?p=0&page_size=100" | \
    python3 -c "
import json,sys
data=json.load(sys.stdin).get('data',[])
matches=[c for c in data if c.get('name')=='$name']
print(matches[0]['id'] if matches else '')
" 2>/dev/null)
  if [ -n "$cid" ]; then
    curl -s --max-time 5 -X DELETE -H "Authorization: Bearer $ADMIN_KEY" \
      "$ONEAPI_URL/api/channel/$cid" > /dev/null 2>&1
    info "已删除旧渠道「$name」(ID=$cid)"
  fi
}

# =============================================
# 阶段 3: 系统设置
# =============================================
update_system_options() {
  step "系统设置"

  update_option() {
    local key="$1" value="$2" desc="$3"
    echo -n "  $desc... "
    local resp
    resp=$(curl -s --max-time 5 -X PUT \
      -H "Authorization: Bearer $ADMIN_KEY" \
      -H "Content-Type: application/json" \
      -d "{\"key\":\"$key\",\"value\":\"$value\"}" \
      "$ONEAPI_URL/api/option/")
    local success
    success=$(echo "$resp" | python3 -c "import json,sys; print(json.load(sys.stdin).get('success',False))" 2>/dev/null || echo "false")
    if [ "$success" = "True" ]; then echo "✅"; else echo "❌"; fi
  }

  update_option "SystemName" "API Hub"              "系统名称"
  update_option "Logo" ""                           "Logo"
  update_option "Footer" "© 2026 API Hub"           "页脚"
  update_option "Notice" "Welcome to API Hub. $5 free credit for new users." "公告"
  update_option "QuotaPerUnit" "500000"             "每美元配额"
  ok "系统设置完成"
}

# =============================================
# 主流程
# =============================================
main() {
  echo ""
  echo "╔══════════════════════════════════════════════════════╗"
  echo "║        AI API 聚合平台 — 初始化脚本 v3.0              ║"
  echo "║        Key 验证 → 模型发现 → 渠道创建                  ║"
  echo "╚══════════════════════════════════════════════════════╝"
  echo ""

  load_env

  # --- 阶段 0: 环境检查 ---
  step "阶段 0: 环境检查"
  if [ "$DRY_RUN" = true ]; then
    warn "DRY-RUN 模式：仅验证 Key，不创建渠道"
  fi
  if [ "$FORCE" = true ]; then
    warn "FORCE 模式：将删除所有旧渠道后重建"
  fi
  if [ "$DRY_RUN" != true ]; then
    check_oneapi
  else
    info "DRY-RUN: 跳过 OneAPI 连接检查"
  fi

  # --- 阶段 1: Key 验证 + 模型发现 ---
  step "阶段 1: API Key 验证 & 模型发现"

  # 数组存有效的 provider 信息: "name|base_url|api_key|models|otype"
  VALID_PROVIDERS=()

  for provider in "${PROVIDERS[@]}"; do
    IFS='|' read -r name env_var base_url otype <<< "$provider"
    api_key="${!env_var:-}"

    echo ""
    echo "  [${CYAN}$name${NC}] base=$base_url"
    if [ -z "$api_key" ]; then
      fail "环境变量 $env_var 未设置，跳过"
      continue
    fi

    # 验证 + 发现模型
    models=$(validate_and_discover "$name" "$base_url" "$api_key") || continue

    VALID_PROVIDERS+=("$name|$base_url|$api_key|$models|$otype")
  done

  # --- 汇总阶段 1 ---
  echo ""
  echo "  ┌──────────────────────────────────────────────────┐"
  printf  "  │  有效 Key: %-2d / %-2d                              │\n" ${#VALID_PROVIDERS[@]} ${#PROVIDERS[@]}
  echo "  └──────────────────────────────────────────────────┘"

  if [ ${#VALID_PROVIDERS[@]} -eq 0 ]; then
    echo ""
    fail "没有可用的 API Key，无法继续。请更新 $ENV_FILE 中的 Key 后重试。"
    exit 1
  fi

  # --- 提前退出 (dry-run) ---
  if [ "$DRY_RUN" = true ]; then
    echo ""
    ok "DRY-RUN 完成。以上为验证结果，未实际创建任何渠道。"
    exit 0
  fi

  # --- 阶段 1.5: 生成前端模型数据 ---
  step "阶段 1.5: 生成模型展示数据"

  # 使用 Python 内置函数，更方便处理复杂数据
  # 导出环境变量给 Python 子进程
  export METADATA_FILE="$PROJECT_DIR/channels/model-metadata.json"
  export OUTPUT_FILE="$PROJECT_DIR/frontend/src/data/models-data.json"

  # 收集所有发现的模型
  DISCOVERED_JSON=$(collect_discovered_models)
  if [ -n "$DISCOVERED_JSON" ] && [ "$DISCOVERED_JSON" != "{}" ]; then
    export DISCOVERED_MODELS="$DISCOVERED_JSON"
    generate_model_data || warn "模型数据生成失败（前端将会使用空数组后备）"
  else
    warn "没有发现任何模型，跳过模型数据生成"
  fi

  # --- 阶段 2: 创建渠道 ---
  step "阶段 2: 渠道创建"

  CREATED=0; SKIPPED=0; FAILED=0

  for entry in "${VALID_PROVIDERS[@]}"; do
    IFS='|' read -r name base_url api_key models otype <<< "$entry"

    if [ "$FORCE" = true ]; then
      delete_channel_by_name "$name"
    fi

    if channel_exists "$name"; then
      info "渠道「$name」已存在，跳过"
      SKIPPED=$((SKIPPED + 1))
      continue
    fi

    echo ""
    if create_channel "$name" "$base_url" "$api_key" "$models" "$otype"; then
      CREATED=$((CREATED + 1))
    else
      FAILED=$((FAILED + 1))
    fi
  done

  # --- 阶段 2.5: 同步 abilities（渠道→模型映射）---
  step "阶段 2.5: 同步 abilities（渠道→模型映射）"
  info "同步中..."
  ABL_ADDED=0; ABL_SKIPPED=0
  for entry in "${VALID_PROVIDERS[@]}"; do
    IFS='|' read -r name base_url api_key models otype <<< "$entry"
    # 获取渠道 ID
    cid=$(curl -s --max-time 5 -H "Authorization: Bearer $ADMIN_KEY" \
      "$ONEAPI_URL/api/channel/?p=0&page_size=100" | \
      python3 -c "
import json,sys
data=json.load(sys.stdin).get('data',[])
matches=[c for c in data if c.get('name')=='$name']
print(matches[0]['id'] if matches else '')
" 2>/dev/null)
    if [ -z "$cid" ]; then continue; fi

    # 获取已有 abilities
    existing_models=$(curl -s --max-time 5 -H "Authorization: Bearer $ADMIN_KEY" \
      "$ONEAPI_URL/api/channel/ability/?p=0&page_size=500" | \
      python3 -c "
import json,sys
data=json.load(sys.stdin).get('data',[])
print('\\n'.join([a['model'] for a in data if a.get('channel_id')==$cid]))
" 2>/dev/null || echo "")

    IFS=',' read -ra model_arr <<< "$models"
    for m in "${model_arr[@]}"; do
      m="$(echo "$m" | xargs | tr '[:upper:]' '[:lower:]')"
      if echo "$existing_models" | grep -qFx "$m"; then
        ABL_SKIPPED=$((ABL_SKIPPED + 1))
        continue
      fi
      curl -s --max-time 5 -X POST \
        -H "Authorization: Bearer $ADMIN_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"group\":\"default\",\"model\":\"$m\",\"channel_id\":$cid,\"enabled\":true,\"priority\":0}" \
        "$ONEAPI_URL/api/channel/ability/" > /dev/null 2>&1 && \
        { info "  $m → $name"; ABL_ADDED=$((ABL_ADDED + 1)); }
      sleep 0.2
    done
  done
  ok "abilities 同步完成：新增 $ABL_ADDED，已存在 $ABL_SKIPPED"

  # --- 阶段 2.6: 创建系统令牌（后端→OneAPI 通信用）---
  step "阶段 2.6: 系统令牌"
  SYSTEM_TOKEN_NAME="system-api"
  existing_token=$(curl -s --max-time 5 -H "Authorization: Bearer $ADMIN_KEY" \
    "$ONEAPI_URL/api/token/?p=0&page_size=100" | \
    python3 -c "
import json,sys
data=json.load(sys.stdin).get('data',[])
matches=[t for t in data if t.get('name')=='$SYSTEM_TOKEN_NAME']
print(matches[0]['key'] if matches else '')
" 2>/dev/null)

  if [ -n "$existing_token" ]; then
    ok "系统令牌已存在: ${existing_token:0:12}****"
    echo "  ONEAPI_API_KEY=$existing_token" >> "$ENV_FILE.tmp" 2>/dev/null || true
  else
    token_resp=$(curl -s --max-time 5 -X POST \
      -H "Authorization: Bearer $ADMIN_KEY" \
      -H "Content-Type: application/json" \
      -d '{"name":"system-api","remain_quota":999999999,"unlimited_quota":true}' \
      "$ONEAPI_URL/api/token/")
    new_token=$(echo "$token_resp" | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('key',''))" 2>/dev/null)
    if [ -n "$new_token" ]; then
      ok "系统令牌已创建（无限配额）: ${new_token:0:12}****"
    else
      warn "系统令牌创建失败，请手动在 OneAPI 后台创建"
    fi
  fi

  # --- 阶段 3: 系统设置 ---
  if [ "$FAILED" -eq 0 ]; then
    update_system_options
  fi

  # --- 汇总 ---
  echo ""
  echo "╔══════════════════════════════════════════════════════╗"
  echo "║                    初始化完成                         ║"
  echo "╠══════════════════════════════════════════════════════╣"
  printf "║  新建: %-2d  已存在: %-2d  失败: %-2d  过期Key: %-2d           ║\n" \
    "$CREATED" "$SKIPPED" "$FAILED" "$((${#PROVIDERS[@]} - ${#VALID_PROVIDERS[@]}))"
  echo "╚══════════════════════════════════════════════════════╝"
  echo ""
  info "管理后台: http://localhost:3001  (root / 123456)"
  info "API 端点:  http://localhost/v1/chat/completions"
  echo ""
}

main "$@"
