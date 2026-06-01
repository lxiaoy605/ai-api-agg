#!/usr/bin/python3 -u
"""
enrich-models.py — 用 LLM 批量生成模型多语言介绍（增量 + 分页输出）

输入: scripts/model-raw.json (fetch-models.py 产出)
输出: frontend/src/data/models/page-{1..N}.json (每页 --pages 个模型)

增量逻辑:
  - 读取已有分页文件，识别已富化的模型
  - 只对新模型调用 LLM
  - 已有模型直接复用

用法:
  python3 scripts/enrich-models.py                     # 增量处理，不分页
  python3 scripts/enrich-models.py --pages 15          # 每页 15 个模型（推荐）
  python3 scripts/enrich-models.py --dry-run           # 预览模式
  python3 scripts/enrich-models.py --force-all         # 强制全量重新处理
"""

import json
import os
import sys
import time
import urllib.request
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
RAW_INPUT = PROJECT_ROOT / "scripts" / "model-raw.json"
PAGES_DIR = PROJECT_ROOT / "frontend" / "src" / "data" / "models"

DEFAULT_API_BASE = os.environ.get("ENRICH_API_BASE", "https://api.deepseek.com/v1")
DEFAULT_API_KEY = os.environ.get("ENRICH_API_KEY") or os.environ.get("DEEPSEEK_API_KEY", "")
DEFAULT_MODEL = os.environ.get("ENRICH_MODEL", "deepseek-chat")


def load_json(path: Path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def save_json(path: Path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def load_existing_enriched():
    """读取已有分页文件，返回 {model_id: model_data}"""
    existing = {}
    if PAGES_DIR.exists():
        for f in sorted(PAGES_DIR.glob("page-*.json")):
            try:
                models = load_json(f)
                for m in models:
                    existing[m["id"]] = m
            except Exception:
                pass
    return existing


def find_raw_for_existing(raw_models: list, existing: dict) -> list:
    """在 raw 中找到已有模型对应的条目（供补缺失字段用）"""
    result = []
    for eid in existing:
        for r in raw_models:
            if r["id"] == eid:
                result.append(r)
                break
    return result


def build_prompt(model: dict) -> str:
    model_id = model["id"]
    provider = model["provider"]
    ctx = model.get("contextWindow", "?")
    price_in = model.get("inputPrice", "?")
    price_out = model.get("outputPrice", "?")
    or_desc = model.get("orDescription", "")
    features = ", ".join(model.get("features", []))
    params = ", ".join(model.get("supportedParameters", [])[:8])

    return f"""你是一个 AI 模型聚合平台的产品文案专家。你的用户是新兴市场（东欧、中亚、高加索地区）的开发者。

请为以下模型生成产品级介绍文案，必须同时提供中文、英文、俄语、土耳其语四个版本。

## 模型基本信息
- 模型 ID: {model_id}
- 厂商: {provider}
- 上下文窗口: {ctx}
- 输入价格 (每百万 token): {price_in}
- 输出价格 (每百万 token): {price_out}
- 功能: {features}
- 参数支持: {params}

## OpenRouter 原始描述（仅供参考）
{or_desc[:600]}

## 输出要求
返回纯 JSON（不要 markdown 代码块），字段如下：

```json
{{
  "descriptions": {{
    "zh": "中文产品介绍。80-150字。像产品落地页文案——说清楚这模型是什么、为什么好、适合谁用。不要列参数。（内部参考用）",
    "en": "English product intro. 60-120 words. Write like a SaaS landing page — what this model is, why it matters, who it's for. Don't list specs. Target audience: developers in Armenia, Georgia, and Central Asia.",
    "ru": "Описание на русском. 60-120 слов. В стиле страницы продукта — что это за модель, чем хороша, для кого. Без перечисления характеристик. Целевая аудитория: разработчики из Казахстана и Центральной Азии.",
    "tr": "Türkçe ürün tanıtımı. 60-120 kelime. Bir SaaS ürün sayfası gibi yazın — bu model nedir, neden önemli, kimler için. Özellikleri listelemeyin. Hedef kitle: Türkiye'deki geliştiriciler."
  }},
  "strengths": ["优势1(中文)", "优势2", "优势3"],
  "useCases": ["推荐场景1(中文)", "推荐场景2", "推荐场景3"],
  "whyChoose": {{
    "en": "One sentence why choose this model (English, 10-20 words)",
    "ru": "Одно предложение почему выбрать эту модель (русский, 10-20 слов)",
    "tr": "Bu model neden seçilmeli — tek cümle (Türkçe, 10-20 kelime)"
  }},
  "category": "chat | code | reasoning | multimodal",
  "features": ["功能标签1", "功能标签2", ...]
}}
```

重要规则：
1. 中文文案要自然，有产品感，不要机翻腔
2. 英文文案要 native，能打动海外开发者
3. 俄语文案要通顺，适合俄语区开发者阅读
4. 土耳其语文案要地道，适合土耳其开发者
5. strengths/useCases 用中文
6. category 从 chat/code/reasoning/multimodal 四选一
7. features 保留 3-5 个关键功能标签（中文）

只返回 JSON，不要任何额外文字。"""


def call_llm(prompt: str, api_base: str, api_key: str, model: str) -> dict:
    body = json.dumps({
        "model": model,
        "messages": [
            {"role": "system", "content": "你是一个精确的 JSON 生成器。只输出合法 JSON，不输出任何其他内容。"},
            {"role": "user", "content": prompt}
        ],
        "temperature": 0.7,
        "max_tokens": 2048,
        "response_format": {"type": "json_object"},
    }).encode()

    req = urllib.request.Request(f"{api_base}/chat/completions", data=body, headers={
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}",
    })

    try:
        with urllib.request.urlopen(req, timeout=90) as resp:
            result = json.loads(resp.read().decode())
            content = result["choices"][0]["message"]["content"].strip()
            if content.startswith("```"):
                content = content.split("\n", 1)[-1]
                if content.endswith("```"):
                    content = content[:-3]
            return json.loads(content)
    except json.JSONDecodeError:
        print(f"   ⚠️ JSON 解析失败: {content[:200]}")
        raise
    except Exception as e:
        body_str = e.read().decode() if hasattr(e, "read") else str(e)
        print(f"   ❌ API 调用失败: {body_str[:300]}")
        raise


def merge_model(raw: dict, enriched: dict) -> dict:
    desc_enriched = enriched.get("descriptions", {})
    return {
        "id": raw["id"],
        "name": raw["name"],
        "provider": raw["provider"],
        "providerLogo": raw["providerLogo"],
        "description": desc_enriched.get("zh", raw.get("orDescription", "")),
        "descriptions": {
            "zh": desc_enriched.get("zh", ""),
            "en": desc_enriched.get("en", ""),
            "ru": desc_enriched.get("ru", ""),
            "tr": desc_enriched.get("tr", ""),
        },
        "inputPrice": raw.get("inputPrice", "—"),
        "outputPrice": raw.get("outputPrice", "—"),
        "contextWindow": raw.get("contextWindow", "—"),
        "maxTokens": raw.get("maxTokens", "—"),
        "status": raw.get("status", "available"),
        "category": enriched.get("category", raw.get("category", "chat")),
        "features": enriched.get("features", raw.get("features", [])),
        "useCases": enriched.get("useCases", []),
        "strengths": enriched.get("strengths", []),
        "whyChoose": enriched.get("whyChoose", {"en": "", "ru": "", "tr": ""}),
        "codeExample": raw.get("codeExample", {}),
    }


def write_pages(all_models: list, page_size: int):
    """写入分页 JSON 文件，同时保留单文件兼容"""
    # 清理旧分页文件
    if PAGES_DIR.exists():
        for f in PAGES_DIR.glob("page-*.json"):
            f.unlink()

    # 排序
    all_models.sort(key=lambda x: (x["provider"], x["name"]))

    # 写入分页
    total = len(all_models)
    num_pages = (total + page_size - 1) // page_size
    for i in range(num_pages):
        start = i * page_size
        end = min(start + page_size, total)
        page = all_models[start:end]
        save_json(PAGES_DIR / f"page-{i+1}.json", page)

    # 也写入一个 index.json (元信息)
    save_json(PAGES_DIR / "index.json", {
        "total": total,
        "pageSize": page_size,
        "pages": num_pages,
        "updatedAt": int(time.time()),
    })

    print(f"\n📄 已写入 {num_pages} 个分页文件 ({PAGES_DIR / 'page-*.json'})")
    print(f"   每页 {page_size} 个模型，共 {total} 个")


def main():
    import argparse
    parser = argparse.ArgumentParser(description="用 LLM 增量生成模型多语言介绍")
    parser.add_argument("-i", "--input", type=str, help="输入 raw JSON")
    parser.add_argument("--pages", type=int, default=0, help="分页大小（如 15）")
    parser.add_argument("--api-base", type=str, default=DEFAULT_API_BASE)
    parser.add_argument("--api-key", type=str, default=DEFAULT_API_KEY)
    parser.add_argument("--model", type=str, default=DEFAULT_MODEL)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--force-all", action="store_true", help="强制全量重新生成")
    parser.add_argument("--delay", type=float, default=1.0)
    parser.add_argument("--limit", type=int, default=0)
    args = parser.parse_args()

    input_path = Path(args.input) if args.input else RAW_INPUT

    if not input_path.exists():
        print(f"❌ 输入文件不存在: {input_path}")
        sys.exit(1)

    raw_models = load_json(input_path)
    raw_by_id = {m["id"]: m for m in raw_models}
    print(f"📋 raw 数据: {len(raw_models)} 个模型")

    # 加载已有富化数据
    existing = load_existing_enriched()
    if existing:
        print(f"📂 已有富化: {len(existing)} 个模型（{PAGES_DIR}/）")

    # 确定需处理的模型
    if args.force_all:
        to_process = raw_models
        print("🔄 强制全量重新生成")
    else:
        to_process = [m for m in raw_models if m["id"] not in existing]
        if existing:
            print(f"📌 增量处理: {len(to_process)} 个新模型（跳过 {len(existing)} 个已有）")

    if args.limit:
        to_process = to_process[:args.limit]

    # dry-run
    if args.dry_run:
        sample = to_process[0] if to_process else raw_models[0]
        print(f"\n{'='*60}")
        print(f"示例 prompt (模型: {sample['name']})")
        print(f"{'='*60}")
        print(build_prompt(sample))
        print(f"\n📊 需处理 {len(to_process)} 个 / 已有 {len(existing)} 个")
        return

    if not to_process:
        print("\n✅ 所有模型已是最新，无需处理")
        # 仍写入分页
        all_models = list(existing.values())
        if args.pages:
            write_pages(all_models, args.pages)
        return

    if not args.api_key:
        print("❌ 未设置 API Key")
        sys.exit(1)

    # 开始处理新模型
    print(f"\n🚀 开始处理 {len(to_process)} 个新模型 (模型: {args.model})")
    enriched_new = {}
    success = 0

    for i, raw in enumerate(to_process):
        name = raw["name"]
        model_id = raw["id"]
        print(f"\n[{i+1}/{len(to_process)}] {name} ({model_id})")

        try:
            prompt = build_prompt(raw)
            llm_result = call_llm(prompt, args.api_base, args.api_key, args.model)
            final = merge_model(raw, llm_result)
            enriched_new[model_id] = final
            success += 1

            desc_preview = final["descriptions"]["zh"][:60]
            print(f"   ✅ {desc_preview}...")

        except Exception as e:
            print(f"   ❌ 失败: {e}")
            # 保存中间结果
            all_partial = {**existing, **enriched_new}
            if args.pages:
                write_pages(list(all_partial.values()), args.pages)
            if i < len(to_process) - 1:
                print(f"   等待 5 秒...")
                time.sleep(5)

        time.sleep(args.delay)

    # 合并 + 写入分页
    all_models = {**existing, **enriched_new}
    final_list = list(all_models.values())
    print(f"\n{'='*60}")
    print(f"✅ 完成! {success}/{len(to_process)} 新增成功, 共 {len(final_list)} 个模型")

    if args.pages:
        write_pages(final_list, args.pages)


if __name__ == "__main__":
    main()
