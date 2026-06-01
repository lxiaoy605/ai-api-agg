#!/usr/bin/env python3
"""
fetch-models.py — 从 OpenRouter API 拉取中国模型元数据

输出: scripts/model-raw.json
  - 结构化元数据（价格、上下文、模态、参数支持等）
  - 保留已有 codeExample、features 等本地数据
  - 仅过滤中国厂商模型

用法:
  python3 scripts/fetch-models.py              # 拉取全部中国模型
  python3 scripts/fetch-models.py --all        # 包含国际主流模型
  python3 scripts/fetch-models.py --providers deepseek,qwen  # 仅指定厂商
"""

import json
import os
import sys
import time
import urllib.request
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
RAW_OUTPUT = PROJECT_ROOT / "scripts" / "model-raw.json"
EXISTING_DATA = PROJECT_ROOT / "frontend" / "src" / "data" / "models-data.json"

OPENROUTER_API = "https://openrouter.ai/api/v1/models"

# 中国模型厂商 → 厂商显示名 / Logo / 来源
CHINESE_PROVIDERS = {
    "deepseek":    {"name": "DeepSeek",          "logo": "DS", "country": "中国"},
    "z-ai":        {"name": "智谱 Z.ai",          "logo": "ZP", "country": "中国"},
    "qwen":        {"name": "阿里通义千问",        "logo": "QW", "country": "中国"},
    "moonshotai":  {"name": "月之暗面 Moonshot",    "logo": "MK", "country": "中国"},
    "minimax":     {"name": "MiniMax",           "logo": "MM", "country": "中国"},
    "stepfun":     {"name": "阶跃星辰 StepFun",     "logo": "SF", "country": "中国"},
    "01-ai":       {"name": "零一万物 Yi",           "logo": "YA", "country": "中国"},
    "bytedance":   {"name": "字节跳动豆包",        "logo": "DB", "country": "中国"},
    "baidu":       {"name": "百度文心",           "logo": "BD", "country": "中国"},
    "xiaomi":      {"name": "小米 MiMo",           "logo": "MI", "country": "中国"},
    "tencent":     {"name": "腾讯混元",           "logo": "HY", "country": "中国"},
    "nvidia":      {"name": "NVIDIA (DeepSeek)",  "logo": "NV", "country": "美国/中国"},
}

# 如果 --all，额外包含的主流国际模型
INTERNATIONAL_INCLUDE = [
    "openai/gpt-4o", "openai/gpt-4.1", "openai/o3-mini",
    "anthropic/claude-sonnet-4.6", "anthropic/claude-opus-4.8",
    "google/gemini-2.5-flash", "google/gemini-3.1-flash",
    "meta-llama/llama-4-maverick",
]


def fetch_openrouter_models() -> list[dict]:
    """从 OpenRouter API 拉取全部模型列表"""
    req = urllib.request.Request(OPENROUTER_API, headers={
        "User-Agent": "AiflowHub/1.0 (model-catalog-sync)",
    })
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = json.loads(resp.read().decode())
            return body.get("data", [])
    except Exception as e:
        print(f"❌ 拉取 OpenRouter API 失败: {e}")
        sys.exit(1)


def load_existing() -> dict[str, dict]:
    """加载已有模型数据（保留 codeExample 等）"""
    if not EXISTING_DATA.exists():
        return {}
    with open(EXISTING_DATA) as f:
        models = json.load(f)
    return {m["id"]: m for m in models}


def is_chinese_model(model_id: str) -> str | None:
    """判断模型是否为中国厂商，返回厂商前缀"""
    for prefix in CHINESE_PROVIDERS:
        if model_id.startswith(prefix) or model_id.startswith(f"{prefix}/"):
            return prefix
    return None


def fmt_tokens(val) -> str:
    """安全格式化 token 数"""
    if val is None or val == 0:
        return "—"
    return f"{int(val) // 1000}K"


def price_to_str(price_per_token: str) -> str:
    """OpenRouter 价格（$/token）→ $X.XX/1M tokens"""
    try:
        p = float(price_per_token) * 1_000_000
        if p == 0:
            return "免费"
        return f"${p:.2f}"
    except (ValueError, TypeError):
        return "—"


def transform_model(raw: dict, prefix: str, existing: dict[str, dict]) -> dict:
    """将 OpenRouter 原始数据转为 AiflowHub 格式"""
    model_id = raw["id"]
    provider_info = CHINESE_PROVIDERS[prefix]
    pricing = raw.get("pricing", {})
    arch = raw.get("architecture", {})

    # 基础字段
    entry = {
        "id": model_id,
        "name": raw.get("name", model_id),
        "provider": provider_info["name"],
        "providerLogo": provider_info["logo"],
        "contextWindow": fmt_tokens(raw.get('context_length')),
        "maxTokens": fmt_tokens(raw.get('top_provider', {}).get('max_completion_tokens')),
        "inputPrice": price_to_str(pricing.get("prompt", "0")),
        "outputPrice": price_to_str(pricing.get("completion", "0")),
        "inputCachePrice": price_to_str(pricing.get("input_cache_read", "0")),
        "modality": arch.get("modality", "text->text"),
        "inputModalities": arch.get("input_modalities", ["text"]),
        "outputModalities": arch.get("output_modalities", ["text"]),
        "supportedParameters": raw.get("supported_parameters", []),
        "status": "available",
        "category": categorize(model_id, raw),
        "orDescription": raw.get("description", ""),
        "orCreated": raw.get("created", 0),
    }

    # 合并已有本地数据（codeExample, features 等）
    existing_id_matches = [
        k for k in existing
        if k == model_id or k in model_id or model_id in k
    ]
    if existing_id_matches:
        old = existing[existing_id_matches[0]]
        entry["codeExample"] = old.get("codeExample", {})
        entry["features"] = old.get("features", [])
    else:
        entry["codeExample"] = generate_code_example(model_id)
        entry["features"] = infer_features(raw)

    return entry


def categorize(model_id: str, raw: dict) -> str:
    """推断模型分类"""
    lid = model_id.lower()
    name = raw.get("name", "").lower()
    if "image" in name or "video" in name or "vision" in lid:
        return "multimodal"
    if any(kw in lid for kw in ["reasoner", "reasoning", "r1", "deep-think", "opus", "pro"]):
        return "reasoning"
    if any(kw in lid for kw in ["coder", "code"]):
        return "code"
    return "chat"


def infer_features(raw: dict) -> list[str]:
    """从 supported_parameters 推断功能标签"""
    params = raw.get("supported_parameters", [])
    features = []
    mapping = {
        "tools": "函数调用",
        "response_format": "JSON 模式",
        "structured_outputs": "结构化输出",
        "include_reasoning": "深度思考",
    }
    for param, label in mapping.items():
        if param in params:
            features.append(label)
    if "stream" not in [p for p in params if "stream" in str(p).lower()]:
        features.append("流式输出")
    return features


def generate_code_example(model_id: str) -> dict:
    """生成基础代码示例"""
    return {
        "curl": f'curl {{API_BASE}}/chat/completions \\\n  -H "Content-Type: application/json" \\\n  -H "Authorization: Bearer $API_KEY" \\\n  -d \'{{\n    "model": "{model_id}",\n    "messages": [{{"role": "user", "content": "你好"}}]\n  }}\'',
        "python": f'import openai\n\nclient = openai.OpenAI(\n    base_url="{{API_BASE}}",\n    api_key="your-api-key"\n)\n\nresponse = client.chat.completions.create(\n    model="{model_id}",\n    messages=[{{"role": "user", "content": "你好"}}]\n)\nprint(response.choices[0].message.content)',
        "nodejs": f'import OpenAI from "openai";\n\nconst client = new OpenAI({{\n  baseURL: "{{API_BASE}}",\n  apiKey: "your-api-key",\n}});\n\nconst response = await client.chat.completions.create({{\n  model: "{model_id}",\n  messages: [{{ role: "user", content: "你好" }}],\n}});\nconsole.log(response.choices[0].message.content);',
    }


def main():
    import argparse
    parser = argparse.ArgumentParser(description="从 OpenRouter 拉取模型元数据")
    parser.add_argument("--all", action="store_true", help="包含国际主流模型")
    parser.add_argument("--providers", type=str, help="仅指定厂商（逗号分隔），如 deepseek,qwen")
    parser.add_argument("--dry-run", action="store_true", help="不写文件，仅打印")
    args = parser.parse_args()

    # 拉取全部模型
    print("📡 正在从 OpenRouter 拉取模型列表...")
    all_models = fetch_openrouter_models()
    print(f"   OpenRouter 共 {len(all_models)} 个模型")

    # 加载已有数据
    existing = load_existing()
    print(f"   已有本地数据 {len(existing)} 个模型")

    # 过滤
    if args.providers:
        wanted = set(args.providers.split(","))
    else:
        wanted = set(CHINESE_PROVIDERS.keys())

    selected = []
    for raw in all_models:
        model_id = raw.get("id", "")
        prefix = is_chinese_model(model_id)
        if prefix and prefix in wanted:
            selected.append((prefix, raw))
        elif args.all and model_id in INTERNATIONAL_INCLUDE:
            # 国际模型：取 provider 第一段
            pfx = model_id.split("/")[0]
            selected.append((pfx, raw))

    print(f"   筛选出 {len(selected)} 个目标模型")

    # 转换
    result = []
    for prefix, raw in selected:
        try:
            entry = transform_model(raw, prefix, existing)
            result.append(entry)
        except Exception as e:
            print(f"   ⚠️ 转换失败 {raw.get('id')}: {e}")

    # 按厂商排列
    result.sort(key=lambda x: (x["provider"], x["name"]))

    # 输出
    if args.dry_run:
        for m in result:
            print(f"   {m['id']:45s} | {m['provider']:20s} | "
                  f"in:{m['inputPrice']:>8s} out:{m['outputPrice']:>8s} "
                  f"ctx:{m['contextWindow']:>6s}")
        return

    RAW_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with open(RAW_OUTPUT, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
    print(f"\n✅ 已写入 {len(result)} 个模型 → {RAW_OUTPUT}")
    print(f"   下一步: python3 scripts/enrich-models.py")


if __name__ == "__main__":
    main()
