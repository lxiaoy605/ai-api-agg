#!/usr/bin/python3 -u
"""
enrich-models.py — 为平台上线的模型生成多语言介绍 + 下载厂商 logo

输入: 内嵌的 PLATFORM_MODELS 列表（与 OneAPI 渠道同步）
输出: frontend/src/data/models/page-*.json + frontend/public/logos/

特性:
  - --skip-enriched: 跳过已有完整富化数据的模型（默认开）
  - --force-all: 强制全量重新生成
  - --model N: 只处理指定模型
  - --download-logos: 下载厂商 logo
  - --dry-run: 预览模式

用法:
  python3 scripts/enrich-models.py --download-logos     # 常规增量
  python3 scripts/enrich-models.py --force-all           # 全量重跑
  python3 scripts/enrich-models.py --model deepseek-v4-flash  # 只跑一个
"""

import json
import os
import sys
import time
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
PAGES_DIR = PROJECT_ROOT / "frontend" / "src" / "data" / "models"
LOGOS_DIR = PROJECT_ROOT / "frontend" / "public" / "logos"

DEFAULT_API_BASE = os.environ.get("ENRICH_API_BASE", "https://api.deepseek.com/v1")
DEFAULT_API_KEY = os.environ.get("ENRICH_API_KEY") or os.environ.get("DEEPSEEK_API_KEY", "")
DEFAULT_MODEL = os.environ.get("ENRICH_MODEL", "deepseek-chat")

PAGE_SIZE = 15

# ──────────────────────────────────────────────────────────────────────
#  平台上线模型列表（与 OneAPI 渠道同步）
#  新增模型时只需在这里加一行即可
# ──────────────────────────────────────────────────────────────────────
PLATFORM_MODELS = [
    # DeepSeek
    {"id": "deepseek-chat",      "name": "DeepSeek V3",     "provider": "DeepSeek",     "category": "chat"},
    {"id": "deepseek-reasoner",  "name": "DeepSeek R1",     "provider": "DeepSeek",     "category": "reasoning"},
    {"id": "deepseek-v4-flash",  "name": "DeepSeek V4 Flash","provider": "DeepSeek",     "category": "chat"},
    {"id": "deepseek-v4-pro",    "name": "DeepSeek V4 Pro",  "provider": "DeepSeek",     "category": "chat"},
    # Zhipu GLM
    {"id": "glm-4",              "name": "GLM-4",           "provider": "Zhipu",        "category": "chat"},
    {"id": "glm-4-flash",        "name": "GLM-4 Flash",     "provider": "Zhipu",        "category": "chat"},
    {"id": "glm-4v",             "name": "GLM-4V",          "provider": "Zhipu",        "category": "multimodal"},
    {"id": "glm-4.5",            "name": "GLM-4.5",         "provider": "Zhipu",        "category": "chat"},
    {"id": "glm-4.5-air",        "name": "GLM-4.5 Air",     "provider": "Zhipu",        "category": "chat"},
    {"id": "glm-4.6",            "name": "GLM-4.6",         "provider": "Zhipu",        "category": "chat"},
    {"id": "glm-4.7",            "name": "GLM-4.7",         "provider": "Zhipu",        "category": "chat"},
    {"id": "glm-5",              "name": "GLM-5",           "provider": "Zhipu",        "category": "chat"},
    {"id": "glm-5-turbo",        "name": "GLM-5 Turbo",     "provider": "Zhipu",        "category": "chat"},
    {"id": "glm-5.1",            "name": "GLM-5.1",         "provider": "Zhipu",        "category": "chat"},
    # MiniMax
    {"id": "abab6.5s-chat",      "name": "ABAB 6.5s",       "provider": "MiniMax",      "category": "chat"},
    {"id": "abab7-chat",         "name": "ABAB 7",          "provider": "MiniMax",      "category": "chat"},
    # Xiaomi MiMo
    {"id": "mimo-v2-flash",      "name": "MiMo V2 Flash",   "provider": "Xiaomi MiMo",  "category": "chat"},
    {"id": "mimo-v2-omni",       "name": "MiMo V2 Omni",    "provider": "Xiaomi MiMo",  "category": "multimodal"},
    {"id": "mimo-v2-pro",        "name": "MiMo V2 Pro",     "provider": "Xiaomi MiMo",  "category": "chat"},
    {"id": "mimo-v2.5",          "name": "MiMo V2.5",       "provider": "Xiaomi MiMo",  "category": "chat"},
    {"id": "mimo-v2.5-pro",      "name": "MiMo V2.5 Pro",   "provider": "Xiaomi MiMo",  "category": "chat"},
]

# 厂商 logo URL
PROVIDER_LOGOS = {
    "DeepSeek": [
        "https://cdn.deepseek.com/logo.png",
        "https://deepseek.com/favicon.ico",
    ],
    "Zhipu": [
        "https://open.bigmodel.cn/favicon.ico",
        "https://zhipuai.cn/favicon.ico",
    ],
    "MiniMax": [
        "https://minimax.chat/favicon.ico",
    ],
    "Xiaomi MiMo": [
        "https://xiaomimimo.com/favicon.ico",
    ],
}

# ──────────────────────────────────────────────────────────────────────

def load_json(path: Path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def save_json(path: Path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def load_existing():
    """读取已有分页文件，返回 {model_id: model_data}"""
    existing = {}
    if PAGES_DIR.exists():
        for f in sorted(PAGES_DIR.glob("page-*.json")):
            try:
                models = load_json(f)
                for m in models:
                    if m.get("enriched"):
                        existing[m["id"]] = m
            except Exception:
                pass
    return existing


def is_complete(model_data: dict) -> bool:
    """检查模型是否已有完整的四语言富化数据"""
    desc = model_data.get("descriptions", {})
    langs = ["zh", "en", "ru", "tr"]
    for lang in langs:
        if not desc.get(lang) or len(desc.get(lang, "")) < 40:
            return False
    # Also check i18n fields now
    for field in ["featuresI18n", "strengthsI18n", "useCasesI18n"]:
        i18n = model_data.get(field, {})
        if not i18n or not i18n.get("zh") or not i18n.get("en"):
            return False
    return True


def build_prompt(model: dict, existing_ids: list) -> str:
    model_id = model["id"]
    provider = model["provider"]
    model_name = model["name"]
    category = model["category"]
    provider_models = [m["id"] for m in PLATFORM_MODELS if m["provider"] == provider]

    return f"""你是 AI 模型领域的产品专家。请为以下模型生成产品级多语言介绍文案。

## 模型信息
- 模型 ID: {model_id}
- 显示名: {model_name}
- 厂商: {provider}
- 分类: {category}
- 同厂商其他模型: {', '.join([m for m in provider_models if m != model_id])}

## 对用户的定位
这是一个面向东欧、中亚和高加索地区开发者的 AI 模型聚合平台 (AiFlowHub)。用户通过单一 API 即可调用多家中国 AI 厂商的模型，按量付费，无需分别注册。

## 你了解的信息
请根据你对 {model_name} ({model_id}) 的已知信息，包括：
- 上下文窗口大小
- 最大输出 token 数
- 定价
- 支持的特性（JSON Mode, Function Calling, Vision, Streaming 等）
- 适用场景

生成以下内容。

## 输出要求
返回纯 JSON（不要 markdown 代码块，不要 ```json 包裹）：

```json
{{
  "descriptions": {{
    "zh": "中文产品介绍。80-180字。像产品落地页文案——说清楚这模型是什么、为什么好、适合谁用。不要列参数。",
    "en": "English product intro. 80-180 words. Write like a SaaS landing page — what this model is, why it matters, who it's for. Don't list specs. Target: developers in Armenia, Georgia, Kazakhstan.",
    "ru": "Описание на русском. 80-180 слов. В стиле страницы продукта. Целевая аудитория: разработчики из СНГ.",
    "tr": "Türkçe ürün tanıtımı. 80-180 kelime. SaaS ürün sayfası tarzında. Hedef kitle: Türkiye'deki geliştiriciler."
  }},
  "contextWindow": "128K",
  "maxTokens": "16K",
  "inputPrice": "$0.14/1M",
  "outputPrice": "$0.28/1M",
  "features": ["Function Calling", "JSON Mode", "Streaming"],
  "featuresI18n": {{
    "en": ["Function Calling", "JSON Mode", "Streaming"],
    "zh": ["函数调用", "JSON 模式", "流式输出"],
    "ru": ["Вызов функций", "Режим JSON", "Потоковая передача"],
    "tr": ["Fonksiyon Çağrısı", "JSON Modu", "Akış"]
  }},
  "strengthsI18n": {{
    "zh": ["优势1", "优势2", "优势3"],
    "en": ["Strength 1", "Strength 2", "Strength 3"],
    "ru": ["Сильная сторона 1", "Сильная сторона 2", "Сильная сторона 3"],
    "tr": ["Güçlü yön 1", "Güçlü yön 2", "Güçlü yön 3"]
  }},
  "useCasesI18n": {{
    "zh": ["场景1", "场景2", "场景3"],
    "en": ["Use case 1", "Use case 2", "Use case 3"],
    "ru": ["Сценарий 1", "Сценарий 2", "Сценарий 3"],
    "tr": ["Kullanım 1", "Kullanım 2", "Kullanım 3"]
  }},
  "strengths": ["优势1(中文)", "优势2", "优势3"],
  "useCases": ["推荐场景1(中文)", "推荐场景2", "推荐场景3"],
  "whyChoose": {{
    "en": "One sentence — why this model. 10-20 words.",
    "ru": "Одно предложение — почему эту модель. 10-20 слов.",
    "tr": "Tek cümle — neden bu model. 10-20 kelime."
  }}
}}
```

重要：
1. contextWindow/maxTokens/inputPrice/outputPrice 请填写你已知的最新数据（价格按每百万 token）。如果不知道，填 "—"
2. features: 技术特性英文标签，featuresI18n: 四语言翻译，zh 保持中文技术术语
3. strengthsI18n / useCasesI18n: 每项 3-4 条，zh/en/ru/tr 四语言，zh 要自然、en 要 native
4. 中文文案要自然，不要机翻腔
5. 英文要 native SaaS 风格

只返回 JSON，不要额外文字。"""


def call_llm(prompt: str, api_base: str, api_key: str, model: str) -> dict:
    try:
        import requests
        resp = requests.post(
            f"{api_base}/chat/completions",
            json={
                "model": model,
                "messages": [
                    {"role": "system", "content": "你是一个精确的 JSON 生成器。只输出合法 JSON 对象，不输出任何其他内容。"},
                    {"role": "user", "content": prompt}
                ],
                "temperature": 0.7,
                "max_tokens": 2048,
                "response_format": {"type": "json_object"},
            },
            headers={"Authorization": f"Bearer {api_key}"},
            timeout=90,
        )
        resp.raise_for_status()
        result = resp.json()
        content = result["choices"][0]["message"]["content"].strip()
        if content.startswith("```"):
            content = content.split("\n", 1)[-1]
            if content.endswith("```"):
                content = content[:-3]
        return json.loads(content)
    except json.JSONDecodeError:
        print(f"   ⚠️ JSON 解析失败，原始内容: {content[:300]}")
        raise
    except Exception as e:
        print(f"   ❌ API 调用失败: {e}")
        raise


def build_code_example(model_id: str) -> dict:
    return {
        "curl": f'curl https://api.aiflowhub.ai/v1/chat/completions \\\n  -H "Content-Type: application/json" \\\n  -H "Authorization: Bearer $AIFLOWHUB_API_KEY" \\\n  -d \'{{"model":"{model_id}","messages":[{{"role":"user","content":"Hello"}}]}}\'',
        "python": f'import requests\n\nresponse = requests.post(\n    "https://api.aiflowhub.ai/v1/chat/completions",\n    headers={{"Authorization": f"Bearer AIFLOWHUB_API_KEY"}},\n    json={{"model": "{model_id}", "messages": [{{"role": "user", "content": "Hello"}}]}}\n)',
        "nodejs": f'const response = await fetch("https://api.aiflowhub.ai/v1/chat/completions", {{\n  method: "POST",\n  headers: {{ "Authorization": "Bearer " + process.env.AIFLOWHUB_API_KEY }},\n  body: JSON.stringify({{ model: "{model_id}", messages: [{{ role: "user", content: "Hello" }}] }})\n}});',
    }


def merge_model(platform: dict, llm_result: dict) -> dict:
    desc = llm_result.get("descriptions", {})
    return {
        "id": platform["id"],
        "name": platform["name"],
        "provider": platform["provider"],
        "providerLogo": f"/logos/{_provider_slug(platform['provider'])}.png",
        "description": desc.get("zh", ""),
        "descriptions": {
            "zh": desc.get("zh", ""),
            "en": desc.get("en", ""),
            "ru": desc.get("ru", ""),
            "tr": desc.get("tr", ""),
        },
        "inputPrice": llm_result.get("inputPrice", "—"),
        "outputPrice": llm_result.get("outputPrice", "—"),
        "contextWindow": llm_result.get("contextWindow", "—"),
        "maxTokens": llm_result.get("maxTokens", "—"),
        "status": "available",
        "category": platform.get("category", llm_result.get("category", "chat")),
        "features": llm_result.get("features", []),
        "featuresI18n": llm_result.get("featuresI18n", {}),
        "useCases": llm_result.get("useCases", []),
        "useCasesI18n": llm_result.get("useCasesI18n", {}),
        "strengths": llm_result.get("strengths", []),
        "strengthsI18n": llm_result.get("strengthsI18n", {}),
        "whyChoose": llm_result.get("whyChoose", {"en": "", "ru": "", "tr": ""}),
        "codeExample": build_code_example(platform["id"]),
        "enriched": True,
    }


def _provider_slug(provider: str) -> str:
    return provider.lower().replace(" ", "-").replace(".", "")


def download_logos():
    """下载所有厂商 logo 到 public/logos/"""
    import requests
    LOGOS_DIR.mkdir(parents=True, exist_ok=True)
    for provider, urls in PROVIDER_LOGOS.items():
        slug = _provider_slug(provider)
        dest = LOGOS_DIR / f"{slug}.png"
        if dest.exists():
            print(f"  ✅ {provider}: 已存在 → {dest}")
            continue
        downloaded = False
        for url in urls:
            try:
                resp = requests.get(url, headers={"User-Agent": "AiFlowHub/1.0"}, timeout=10)
                resp.raise_for_status()
                data = resp.content
                with open(dest, "wb") as f:
                    f.write(data)
                print(f"  ✅ {provider}: {url} → {dest} ({len(data)} bytes)")
                downloaded = True
                break
            except Exception as e:
                print(f"  ⚠️ {provider}: {url} 失败 ({e})")
        if not downloaded:
            print(f"  ❌ {provider}: 所有 URL 均下载失败")


def write_pages(all_models: list):
    """写入分页 JSON 文件"""
    if PAGES_DIR.exists():
        for f in PAGES_DIR.glob("page-*.json"):
            f.unlink()

    # 排序
    all_models.sort(key=lambda x: (x["provider"], x["name"]))

    total = len(all_models)
    num_pages = (total + PAGE_SIZE - 1) // PAGE_SIZE
    for i in range(num_pages):
        start = i * PAGE_SIZE
        end = min(start + PAGE_SIZE, total)
        page = all_models[start:end]
        save_json(PAGES_DIR / f"page-{i + 1}.json", page)

    save_json(PAGES_DIR / "index.json", {
        "total": total,
        "pageSize": PAGE_SIZE,
        "pages": num_pages,
        "updatedAt": int(time.time()),
    })

    print(f"\n📄 已写入 {num_pages} 个分页文件 → {PAGES_DIR}")
    print(f"   每页 {PAGE_SIZE} 个模型，共 {total} 个")


def main():
    import argparse
    parser = argparse.ArgumentParser(description="为平台上线的模型生成多语言介绍")
    parser.add_argument("--api-base", type=str, default=DEFAULT_API_BASE)
    parser.add_argument("--api-key", type=str, default=DEFAULT_API_KEY)
    parser.add_argument("--model", type=str, default=DEFAULT_MODEL)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--force-all", action="store_true", help="强制全量重新生成")
    parser.add_argument("--skip-enriched", action="store_true", default=True, help="跳过已有完整数据的模型（默认开）")
    parser.add_argument("--no-skip", action="store_true", help="不跳过已有模型")
    parser.add_argument("--only", type=str, help="只处理指定模型 ID（逗号分隔）")
    parser.add_argument("--download-logos", action="store_true", help="下载厂商 logo")
    parser.add_argument("--delay", type=float, default=1.0)
    args = parser.parse_args()

    # 先下载 logo
    if args.download_logos:
        print("🖼️  下载厂商 logo...")
        download_logos()
        print()

    existing = load_existing()
    print(f"📂 已有富化数据: {len(existing)} 个模型")

    # 确定哪些模型需要处理
    skip = args.skip_enriched and not args.no_skip and not args.force_all
    to_process = []
    skipped = []

    for pm in PLATFORM_MODELS:
        mid = pm["id"]
        if args.only:
            only_ids = [x.strip() for x in args.only.split(",")]
            if mid not in only_ids:
                continue
        existing_data = existing.get(mid)
        if skip and existing_data and is_complete(existing_data):
            skipped.append(mid)
        else:
            to_process.append(pm)

    if skipped:
        print(f"⏭️  跳过 {len(skipped)} 个（已有完整数据）: {', '.join(skipped)}")
    print(f"🎯 待处理: {len(to_process)} 个模型")
    if to_process:
        print(f"   {', '.join(m['id'] for m in to_process)}")

    if args.dry_run:
        if to_process:
            sample = to_process[0]
            print(f"\n{'='*60}")
            print(f"示例 prompt (模型: {sample['name']})")
            print(f"{'='*60}")
            print(build_prompt(sample, []))
        return

    if not to_process:
        print("\n✅ 所有模型已是最新")
        # 仍然写入分页（用已有数据）
        all_models = list(existing.values())
        write_pages(all_models)
        return

    if not args.api_key:
        print("❌ 未设置 API Key（设置 ENRICH_API_KEY 或 DEEPSEEK_API_KEY 环境变量）")
        sys.exit(1)

    print(f"\n🚀 开始 LLM 富化 (模型: {args.model})")
    success = 0

    for i, pm in enumerate(to_process):
        name = pm["name"]
        mid = pm["id"]
        print(f"\n[{i + 1}/{len(to_process)}] {name} ({mid})")

        try:
            existing_ids = list(existing.keys())
            prompt = build_prompt(pm, existing_ids)
            llm_result = call_llm(prompt, args.api_base, args.api_key, args.model)
            final = merge_model(pm, llm_result)
            existing[mid] = final
            success += 1
            desc_preview = final["descriptions"]["zh"][:70]
            print(f"   ✅ {desc_preview}...")
        except Exception as e:
            print(f"   ❌ 失败: {e}")
            all_current = list(existing.values())
            write_pages(all_current)
            if i < len(to_process) - 1:
                print(f"   等待 5 秒继续...")
                time.sleep(5)
        time.sleep(args.delay)

    # 写入分页
    all_models = list(existing.values())
    print(f"\n{'='*60}")
    print(f"✅ 完成! {success}/{len(to_process)} 成功, 共 {len(all_models)} 个模型")
    write_pages(all_models)


if __name__ == "__main__":
    main()
