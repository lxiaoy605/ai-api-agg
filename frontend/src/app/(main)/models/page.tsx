"use client";

import { useState, useMemo, useCallback } from "react";
import { useTranslations, useLocale } from "next-intl";
import { models as enrichedModels } from "@/data/models";
import { PLATFORM_MODEL_IDS, getPlatformMeta } from "@/data/platform-models";
import {
  ChevronDown,
  ChevronUp,
  Copy,
  Check,
  Zap,
  Cpu,
  DollarSign,
  Tag,
  Brain,
  Sparkles,
  Layers,
  Globe,
  Code,
  Search,
  X,
} from "lucide-react";

const categoryKeys = ["chat", "code", "reasoning", "multimodal"] as const;

const providerIcons: Record<string, React.ComponentType<{ className?: string }>> = {
  DeepSeek: Brain,
  "Zhipu Z.ai": Sparkles,
  "Xiaomi MiMo": Layers,
  OpenAI: Globe,
  Anthropic: Code,
};

const providerColors: Record<string, string> = {
  DeepSeek: "bg-[#4A90D9]/10 text-[#4A90D9]",
  Zhipu: "bg-purple-500/10 text-purple-400",
  ZhipuGLM: "bg-purple-500/10 text-purple-400",
  MiniMax: "bg-blue-500/10 text-blue-400",
  "Xiaomi MiMo": "bg-orange-500/10 text-orange-400",
};

/** 平台模型视图（合并富化数据） */
interface ModelView {
  /** 平台模型 ID */
  id: string;
  /** 显示名 */
  name: string;
  /** 分类 */
  category: string;
  /** 厂商 */
  provider: string;
  /** Logo 路径 */
  providerLogo?: string;
  /** 上下文窗口 */
  contextWindow: string;
  /** 最大输出 */
  maxTokens: string;
  /** 输入价格 */
  inputPrice: string;
  /** 输出价格 */
  outputPrice: string;
  /** 特性标签 */
  features: string[];
  /** 多语言描述 */
  description: string;
  descriptions: Record<string, string>;
  /** 优势（当前语言） */
  strengths: string[];
  /** 场景（当前语言） */
  useCases: string[];
  /** 代码示例 */
  codeExample: Record<string, string>;
  /** 是否有富化数据 */
  enriched: boolean;
}

function buildModelViews(locale: string): ModelView[] {
  const lang = locale as "en" | "ru" | "tr";
  return PLATFORM_MODEL_IDS.map((mid) => {
    const meta = getPlatformMeta(mid)!;
    // 查找富化数据（现已统一使用平台模型 ID）
    const enriched = enrichedModels.find((m) => m.id === mid);

    if (enriched) {
      return {
        id: mid,
        name: enriched.name || meta.displayName,
        category: meta.category || enriched.category,
        provider: meta.provider,
        contextWindow: enriched.contextWindow,
        maxTokens: enriched.maxTokens,
        inputPrice: enriched.inputPrice,
        outputPrice: enriched.outputPrice,
        features: (enriched.featuresI18n as Record<string, string[]>)?.[lang] || enriched.features || [],
        description: enriched.descriptions?.[lang] || enriched.descriptions?.zh || enriched.description || "",
        descriptions: { ...enriched.descriptions } as unknown as Record<string, string>,
        strengths: (enriched.strengthsI18n as Record<string, string[]>)?.[lang] || enriched.strengths || [],
        useCases: (enriched.useCasesI18n as Record<string, string[]>)?.[lang] || enriched.useCases || [],
        codeExample: enriched.codeExample,
        providerLogo: enriched.providerLogo,
        enriched: true,
      };
    }

    // Fallback: 无富化数据，用基本信息
    const fallbackCode = {
      curl: `curl https://api.aiflowhub.ai/v1/chat/completions \\
  -H "Content-Type: application/json" \\
  -H "Authorization: Bearer $AIFLOWHUB_API_KEY" \\
  -d '{"model":"${mid}","messages":[{"role":"user","content":"Hello"}]}'`,
      python: `import requests\n\nresponse = requests.post(\n    "https://api.aiflowhub.ai/v1/chat/completions",\n    headers={"Authorization": f"Bearer {AIFLOWHUB_API_KEY}"},\n    json={"model": "${mid}", "messages": [{"role": "user", "content": "Hello"}]}\n)`,
      nodejs: `const response = await fetch("https://api.aiflowhub.ai/v1/chat/completions", {\n  method: "POST",\n  headers: { "Authorization": "Bearer " + AIFLOWHUB_API_KEY },\n  body: JSON.stringify({ model: "${mid}", messages: [{ role: "user", content: "Hello" }] })\n});`,
    };
    return {
      id: mid,
      name: meta.displayName,
      category: meta.category,
      provider: meta.provider,
      contextWindow: "—",
      maxTokens: "—",
      inputPrice: "—",
      outputPrice: "—",
      features: [],
      description: `${meta.displayName} by ${meta.provider}`,
      descriptions: { en: `${meta.displayName} by ${meta.provider}` },
      strengths: [],
      useCases: [],
      codeExample: fallbackCode,
      enriched: false,
    };
  });
}

function searchModelViews(models: ModelView[], query: string): ModelView[] {
  const q = query.toLowerCase().trim();
  if (!q) return models;
  return models.filter(
    (m) =>
      m.id.toLowerCase().includes(q) ||
      m.name.toLowerCase().includes(q)
  );
}

export default function ModelsPage() {
  const t = useTranslations("models");
  const tc = useTranslations("common");
  const ts = useTranslations("status");
  const locale = useLocale();
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [codeLang, setCodeLang] = useState<"curl" | "python" | "nodejs">("curl");
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState("");
  const [committedQuery, setCommittedQuery] = useState("");
  const [filterCategory, setFilterCategory] = useState<string>("all");

  const allViews = useMemo(() => buildModelViews(locale), [locale]);

  const filtered = useMemo(() => {
    const q = committedQuery || searchQuery;
    let result = q ? searchModelViews(allViews, q) : allViews;
    if (filterCategory !== "all") {
      result = result.filter((m) => m.category === filterCategory);
    }
    return result;
  }, [searchQuery, committedQuery, filterCategory, allViews]);

  const handleSearch = useCallback(() => {
    setCommittedQuery(searchQuery);
  }, [searchQuery]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === "Enter") handleSearch();
    },
    [handleSearch]
  );

  const handleCopy = (text: string, id: string) => {
    navigator.clipboard.writeText(text);
    setCopiedId(id);
    setTimeout(() => setCopiedId(null), 2000);
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-[var(--body-text)]">{t("title")}</h1>
        <p className="text-[var(--muted-text)] text-sm mt-1">
          {t("subtitle")}
        </p>
      </div>

      {/* 搜索 + 分类筛选 */}
      <div className="flex gap-2 flex-wrap items-center">
        <div className="relative flex-1 min-w-[200px] max-w-[360px]">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-[var(--muted-text)]" />
          <input
            type="text" maxLength={50}
            placeholder={t("searchPlaceholder") || "Search models by name or ID..."}
            value={searchQuery}
            onChange={(e) => {
              setSearchQuery(e.target.value);
              if (!e.target.value) setCommittedQuery("");
            }}
            onKeyDown={handleKeyDown}
            className="w-full pl-9 pr-8 py-1.5 text-sm rounded-lg bg-[var(--surface-raised)]/50 border border-[var(--border-muted)] text-[var(--body-text)] placeholder:text-[var(--muted-text)] focus:outline-none focus:border-brand-500/40"
          />
          {searchQuery && (
            <button
              onClick={() => {
                setSearchQuery("");
                setCommittedQuery("");
              }}
              className="absolute right-10 top-1/2 -translate-y-1/2 h-5 w-5 flex items-center justify-center text-[var(--muted-text)] hover:text-[var(--body-text)]"
            >
              <X className="h-3.5 w-3.5" />
            </button>
          )}
          <button
            onClick={handleSearch}
            className="absolute right-2 top-1/2 -translate-y-1/2 h-6 w-6 flex items-center justify-center rounded text-brand-400 hover:text-brand-300 hover:bg-brand-500/10 transition-colors"
            title="Search"
          >
            <Search className="h-3.5 w-3.5" />
          </button>
        </div>
        <button
          onClick={() => setFilterCategory("all")}
          className={`px-3 py-1.5 text-xs rounded-lg transition-colors ${
            filterCategory === "all"
              ? "bg-brand-500/10 text-brand-300 border border-brand-500/20"
              : "text-[var(--muted-text)] hover:text-[var(--body-text)] bg-[var(--surface-raised)]/50"
          }`}
        >
          {tc("all")}
        </button>
        {categoryKeys.map((key) => (
          <button
            key={key}
            onClick={() => setFilterCategory(key)}
            className={`px-3 py-1.5 text-xs rounded-lg transition-colors ${
              filterCategory === key
                ? "bg-brand-500/10 text-brand-300 border border-brand-500/20"
                : "text-[var(--muted-text)] hover:text-[var(--body-text)] bg-[var(--surface-raised)]/50"
            }`}
          >
            {t(`category.${key}`)}
          </button>
        ))}
      </div>

      {/* 结果计数 */}
      {committedQuery && (
        <p className="text-sm text-[var(--muted-text)] -mt-4">
          Found {filtered.length} results for "{committedQuery}"
        </p>
      )}

      {/* 模型列表 */}
      <div className="space-y-3">
        {filtered.map((model) => {
          const isExpanded = expandedId === model.id;
          const iconKey = Object.keys(providerIcons).find(
            (k) => model.provider.toLowerCase().includes(k.toLowerCase())
          );
          const ProviderIcon = iconKey ? providerIcons[iconKey] : Brain;
          const colorClass =
            Object.entries(providerColors).find(([k]) =>
              model.provider.toLowerCase().includes(k.toLowerCase())
            )?.[1] || "bg-[var(--surface-raised)] text-[var(--muted-text)]";

          return (
            <div
              key={model.id}
              className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] overflow-hidden transition-all hover:border-[var(--border-color)]"
            >
              {/* 卡片头部 */}
              <div
                className="p-4 sm:p-5 cursor-pointer select-none"
                onClick={() => setExpandedId(isExpanded ? null : model.id)}
              >
                <div className="flex items-start gap-4">
                  {/* 模型图标 — 优先用真实 logo，加载失败回退到图标 */}
                  <div
                    className={`w-10 h-10 rounded-xl flex items-center justify-center shrink-0 mt-0.5 ${colorClass} overflow-hidden`}
                  >
                    {model.providerLogo ? (
                      <img
                        src={model.providerLogo}
                        alt={model.provider}
                        className="w-7 h-7 object-contain"
                        onError={(e) => {
                          (e.target as HTMLImageElement).style.display = "none";
                          (e.target as HTMLImageElement).nextElementSibling?.classList.remove("hidden");
                        }}
                      />
                    ) : null}
                    <ProviderIcon className={`h-5 w-5 ${model.providerLogo ? "hidden" : ""}`} />
                  </div>

                  {/* 模型信息 */}
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-3 flex-wrap">
                      <h3 className="text-sm font-semibold text-[var(--body-text)]">
                        {model.name}
                      </h3>
                      <code className="text-xs px-2 py-0.5 rounded-full bg-[var(--surface-raised)] text-[var(--muted-text)] font-mono">
                        {model.id}
                      </code>
                      <span className={`text-xs px-2 py-0.5 rounded-full ${
                        model.enriched ? "bg-brand-500/10 text-brand-300" : "bg-yellow-500/10 text-yellow-400"
                      }`}>
                        {model.enriched ? "Available" : "Beta"}
                      </span>
                    </div>
                    <p
                      className="text-sm text-[var(--muted-text)] leading-relaxed mt-1.5"
                      style={{
                        maxWidth: "95%",
                        display: "-webkit-box",
                        WebkitLineClamp: isExpanded ? undefined : 2,
                        WebkitBoxOrient: "vertical",
                        overflow: isExpanded ? "visible" : "hidden",
                      }}
                    >
                      {model.description}
                    </p>
                    <div className="flex items-center gap-4 mt-2 text-sm text-[var(--muted-text)]">
                      <span className="flex items-center gap-1">
                        <DollarSign className="h-3.5 w-3.5" />
                        {model.inputPrice}
                        <span className="text-[var(--muted-text)]/60">/ 1M in</span>
                      </span>
                      <span className="flex items-center gap-1">
                        <DollarSign className="h-3.5 w-3.5" />
                        {model.outputPrice}
                        <span className="text-[var(--muted-text)]/60">/ 1M out</span>
                      </span>
                      <span className="flex items-center gap-1">
                        <Cpu className="h-3.5 w-3.5" />
                        {model.contextWindow}
                      </span>
                      <span className="hidden sm:inline-flex items-center gap-1">
                        <Zap className="h-3.5 w-3.5" />
                        {model.maxTokens} max
                      </span>
                    </div>
                  </div>

                  <button className="text-[var(--muted-text)] hover:text-[var(--body-text)] transition-colors shrink-0 mt-1">
                    {isExpanded ? (
                      <ChevronUp className="h-4 w-4" />
                    ) : (
                      <ChevronDown className="h-4 w-4" />
                    )}
                  </button>
                </div>

                {/* 特性标签 */}
                {(model.features || []).length > 0 && (
                  <div className="flex gap-1.5 mt-3 ml-14 flex-wrap">
                    {model.features.slice(0, 5).map((f) => (
                      <span
                        key={f}
                        className="text-xs px-2 py-0.5 rounded bg-brand-500/10 text-brand-300"
                      >
                        {f}
                      </span>
                    ))}
                  </div>
                )}
              </div>

              {/* 展开详情 */}
              {isExpanded && (
                <div className="border-t border-[var(--border-color)] pl-[4.5rem] sm:pl-[4.75rem] pr-5 py-4 space-y-4 bg-[var(--card-bg)]/50">
                  {/* 规格网格 */}
                  <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                    <div className="bg-[var(--surface-raised)] rounded-lg p-3">
                      <p className="text-sm text-[var(--muted-text)]">
                        {t("contextWindow")}
                      </p>
                      <p className="text-sm text-[var(--body-text)] font-medium mt-0.5">
                        {model.contextWindow}
                      </p>
                    </div>
                    <div className="bg-[var(--surface-raised)] rounded-lg p-3">
                      <p className="text-sm text-[var(--muted-text)]">
                        {t("maxOutput")}
                      </p>
                      <p className="text-sm text-[var(--body-text)] font-medium mt-0.5">
                        {model.maxTokens}
                      </p>
                    </div>
                    <div className="bg-[var(--surface-raised)] rounded-lg p-3">
                      <p className="text-sm text-[var(--muted-text)]">
                        {t("inputPriceLabel")}
                      </p>
                      <p className="text-sm text-[var(--body-text)] font-medium mt-0.5">
                        {model.inputPrice}/1M tokens
                      </p>
                    </div>
                    <div className="bg-[var(--surface-raised)] rounded-lg p-3">
                      <p className="text-sm text-[var(--muted-text)]">
                        {t("outputPriceLabel")}
                      </p>
                      <p className="text-sm text-[var(--body-text)] font-medium mt-0.5">
                        {model.outputPrice}/1M tokens
                      </p>
                    </div>
                  </div>

                  {/* 所有特性 */}
                  {(model.features || []).length > 0 && (
                    <div>
                      <h4 className="text-sm font-medium text-[var(--muted-text)] mb-2 flex items-center gap-1">
                        <Tag className="h-3.5 w-3.5" />
                        {t("supportedFeatures")}
                      </h4>
                      <div className="flex gap-1.5 flex-wrap">
                        {model.features.map((f) => (
                          <span
                            key={f}
                            className="text-sm px-2.5 py-1 rounded-full bg-brand-500/10 text-brand-300"
                          >
                            {f}
                          </span>
                        ))}
                      </div>
                    </div>
                  )}

                  {/* 使用场景 + 优势 */}
                  {((model.useCases?.length ?? 0) > 0 ||
                    (model.strengths?.length ?? 0) > 0) && (
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                      {(model.useCases?.length ?? 0) > 0 && (
                        <div>
                          <h4 className="text-sm font-medium text-[var(--muted-text)] mb-2">
                            {t("useCases")}
                          </h4>
                          <ul className="space-y-1">
                            {model.useCases!.map((u, i) => (
                              <li
                                key={i}
                                className="text-sm text-[var(--body-text)] pl-3 relative before:content-['·'] before:absolute before:left-0 before:text-brand-400"
                              >
                                {u}
                              </li>
                            ))}
                          </ul>
                        </div>
                      )}
                      {(model.strengths?.length ?? 0) > 0 && (
                        <div>
                          <h4 className="text-sm font-medium text-[var(--muted-text)] mb-2">
                            {t("strengths")}
                          </h4>
                          <ul className="space-y-1">
                            {model.strengths!.map((s, i) => (
                              <li
                                key={i}
                                className="text-sm text-[var(--body-text)] pl-3 relative before:content-['·'] before:absolute before:left-0 before:text-brand-400"
                              >
                                {s}
                              </li>
                            ))}
                          </ul>
                        </div>
                      )}
                    </div>
                  )}

                  {/* 代码示例 */}
                  {model.enriched && (
                    <div>
                      <div className="flex items-center justify-between mb-2">
                        <h4 className="text-sm font-medium text-[var(--muted-text)] flex items-center gap-1">
                          <Zap className="h-3.5 w-3.5" />
                          {t("codeExample")}
                        </h4>
                        <div className="flex rounded-lg bg-[var(--surface-raised)] p-0.5">
                          {(["curl", "python", "nodejs"] as const).map(
                            (lang) => (
                              <button
                                key={lang}
                                onClick={(e) => {
                                  e.stopPropagation();
                                  setCodeLang(lang);
                                }}
                                className={`px-2 py-1 text-sm rounded-md transition-colors ${
                                  codeLang === lang
                                    ? "bg-brand-600 text-white"
                                    : "text-[var(--muted-text)] hover:text-[var(--body-text)]"
                                }`}
                              >
                                {lang === "nodejs" ? "Node.js" : lang}
                              </button>
                            )
                          )}
                        </div>
                      </div>
                      <div className="relative">
                        <pre className="bg-[var(--page-bg)] rounded-lg p-4 text-sm text-[var(--body-text)] overflow-x-auto font-mono leading-relaxed">
                          {model.codeExample[codeLang]}
                        </pre>
                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            handleCopy(model.codeExample[codeLang], model.id);
                          }}
                          className="absolute top-2 right-2 p-1.5 rounded bg-[var(--surface-raised)] hover:bg-[var(--border-color)] text-[var(--muted-text)] hover:text-[var(--body-text)] transition-colors"
                        >
                          {copiedId === model.id ? (
                            <Check className="h-4 w-4 text-brand-300" />
                          ) : (
                            <Copy className="h-4 w-4" />
                          )}
                        </button>
                      </div>
                    </div>
                  )}
                </div>
              )}
            </div>
          );
        })}

        {filtered.length === 0 && (
          <div className="py-12 text-center text-sm text-[var(--muted-text)]">
            No models match this filter.
          </div>
        )}
      </div>
    </div>
  );
}
