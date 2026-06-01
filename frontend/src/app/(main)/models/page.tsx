"use client";

import { useState, useMemo } from "react";
import { useTranslations, useLocale } from "next-intl";
import { models as allModels, searchModels } from "@/data/models";
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
  "Zhipu Z.ai": "bg-purple-500/10 text-purple-400",
  "Xiaomi MiMo": "bg-orange-500/10 text-orange-400",
  OpenAI: "bg-emerald-500/10 text-emerald-400",
  Anthropic: "bg-amber-500/10 text-amber-400",
};

export default function ModelsPage() {
  const t = useTranslations("models");
  const tc = useTranslations("common");
  const ts = useTranslations("status");
  const locale = useLocale();
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [codeLang, setCodeLang] = useState<"curl" | "python" | "nodejs">("curl");
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState("");
  const [filterCategory, setFilterCategory] = useState<string>("all");

  const filtered = useMemo(() => {
    let result = searchQuery
      ? searchModels(searchQuery, locale as "en" | "ru" | "tr")
      : allModels;
    if (filterCategory !== "all") {
      result = result.filter((m) => m.category === filterCategory);
    }
    return result;
  }, [searchQuery, filterCategory, locale]);

  const handleCopy = (text: string, id: string) => {
    navigator.clipboard.writeText(text);
    setCopiedId(id);
    setTimeout(() => setCopiedId(null), 2000);
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-[var(--body-text)]">{t("title")}</h1>
        <p className="text-[var(--muted-text)] text-sm mt-1">{t("subtitle")}</p>
      </div>

      {/* 搜索 + 分类筛选 */}
      <div className="flex gap-2 flex-wrap items-center">
        <div className="relative flex-1 min-w-[200px] max-w-[360px]">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-[var(--muted-text)]" />
          <input
            type="text"
            placeholder={t("searchPlaceholder") || "Search models..."}
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full pl-9 pr-8 py-1.5 text-sm rounded-lg bg-[var(--surface-raised)]/50 border border-[var(--border-muted)] text-[var(--body-text)] placeholder:text-[var(--muted-text)] focus:outline-none focus:border-brand-500/40"
          />
          {searchQuery && (
            <button
              onClick={() => setSearchQuery("")}
              className="absolute right-2 top-1/2 -translate-y-1/2 h-5 w-5 flex items-center justify-center text-[var(--muted-text)] hover:text-[var(--body-text)]"
            >
              <X className="h-3.5 w-3.5" />
            </button>
          )}
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

      {/* 搜索结果计数 */}
      {searchQuery && (
        <p className="text-xs text-[var(--muted-text)] -mt-4">
          Found {filtered.length} of {allModels.length} models
        </p>
      )}

      {/* 模型列表 — 单列行布局 */}
      <div className="space-y-3">
        {filtered.map((model) => {
          const isExpanded = expandedId === model.id;
          const ProviderIcon = providerIcons[model.provider];
          const colorClass = providerColors[model.provider] || "bg-[var(--surface-raised)] text-[var(--muted-text)]";
          return (
            <div
              key={model.id}
              className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] overflow-hidden transition-all hover:border-[var(--border-color)]"
            >
              {/* 卡片头部 — 单行布局 */}
              <div
                className="p-4 sm:p-5 cursor-pointer select-none"
                onClick={() => setExpandedId(isExpanded ? null : model.id)}
              >
                <div className="flex items-center gap-4">
                  {/* 模型图标 */}
                  <div
                    className={`w-10 h-10 rounded-xl flex items-center justify-center shrink-0 ${colorClass}`}
                  >
                    {ProviderIcon ? (
                      <ProviderIcon className="h-5 w-5" />
                    ) : (
                      <Brain className="h-5 w-5" />
                    )}
                  </div>

                  {/* 模型信息 */}
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-3 flex-wrap">
                      <h3 className="text-sm font-semibold text-[var(--body-text)]">
                        {model.name}
                      </h3>
                      <span className="text-[11px] px-2 py-0.5 rounded-full bg-[var(--surface-raised)] text-[var(--muted-text)]">
                        {model.provider}
                      </span>
                      <span
                        className={`text-[11px] px-2 py-0.5 rounded-full ${
                          model.status === "available"
                            ? "bg-brand-500/10 text-brand-300"
                            : "bg-yellow-500/10 text-yellow-400"
                        }`}
                      >
                        {ts(model.status)}
                      </span>
                    </div>
                    <p className="text-xs text-[var(--muted-text)] leading-relaxed mt-1.5 line-clamp-1">
                      {model.descriptions?.[locale as "en" | "ru" | "tr"] || model.description}
                    </p>
                    <div className="flex items-center gap-4 mt-2 text-xs text-[var(--muted-text)]">
                      <span className="flex items-center gap-1">
                        <DollarSign className="h-3 w-3" />
                        {t("inputPrice", { price: model.inputPrice })}
                        <span className="text-[var(--muted-text)]/60">/ 1M</span>
                      </span>
                      <span className="flex items-center gap-1">
                        <DollarSign className="h-3 w-3" />
                        {t("outputPrice", { price: model.outputPrice })}
                        <span className="text-[var(--muted-text)]/60">/ 1M</span>
                      </span>
                      <span className="flex items-center gap-1">
                        <Cpu className="h-3 w-3" />
                        {model.contextWindow}
                      </span>
                      <span className="hidden sm:inline-flex items-center gap-1">
                        <Zap className="h-3 w-3" />
                        {model.maxTokens} max
                      </span>
                    </div>
                  </div>

                  {/* 展开按钮 */}
                  <button className="text-[var(--muted-text)] hover:text-[var(--body-text)] transition-colors shrink-0">
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
                    {model.features.slice(0, 4).map((f) => (
                      <span
                        key={f}
                        className="text-[10px] px-2 py-0.5 rounded bg-brand-500/10 text-brand-300"
                      >
                        {f}
                      </span>
                    ))}
                  </div>
                )}
              </div>

              {/* 展开详情 */}
              {isExpanded && (
                <div className="border-t border-[var(--border-color)] px-5 py-4 space-y-4 bg-[var(--card-bg)]/50">
                  {/* 规格网格 */}
                  <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 text-xs">
                    <div className="bg-[var(--surface-raised)] rounded-lg p-3">
                      <p className="text-[var(--muted-text)]">{t("contextWindow")}</p>
                      <p className="text-[var(--body-text)] font-medium mt-0.5">{model.contextWindow}</p>
                    </div>
                    <div className="bg-[var(--surface-raised)] rounded-lg p-3">
                      <p className="text-[var(--muted-text)]">{t("maxOutput")}</p>
                      <p className="text-[var(--body-text)] font-medium mt-0.5">{model.maxTokens}</p>
                    </div>
                    <div className="bg-[var(--surface-raised)] rounded-lg p-3">
                      <p className="text-[var(--muted-text)]">{t("inputPriceLabel")}</p>
                      <p className="text-[var(--body-text)] font-medium mt-0.5">{model.inputPrice}/1M tokens</p>
                    </div>
                    <div className="bg-[var(--surface-raised)] rounded-lg p-3">
                      <p className="text-[var(--muted-text)]">{t("outputPriceLabel")}</p>
                      <p className="text-[var(--body-text)] font-medium mt-0.5">{model.outputPrice}/1M tokens</p>
                    </div>
                  </div>

                  {/* 所有特性 */}
                  <div>
                    <h4 className="text-xs font-medium text-[var(--muted-text)] mb-2 flex items-center gap-1">
                      <Tag className="h-3 w-3" />
                      {t("supportedFeatures")}
                    </h4>
                    <div className="flex gap-1.5 flex-wrap">
                      {model.features.map((f) => (
                        <span
                          key={f}
                          className="text-xs px-2 py-1 rounded-full bg-brand-500/10 text-brand-300"
                        >
                          {f}
                        </span>
                      ))}
                    </div>
                  </div>

                  {/* 使用场景 + 优势 */}
                  {(model.useCases?.length > 0 || model.strengths?.length > 0) && (
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                      {model.useCases?.length > 0 && (
                        <div>
                          <h4 className="text-xs font-medium text-[var(--muted-text)] mb-2">
                            {t("useCases")}
                          </h4>
                          <ul className="space-y-1">
                            {model.useCases.map((u, i) => (
                              <li key={i} className="text-xs text-[var(--body-text)] pl-3 relative before:content-['·'] before:absolute before:left-0 before:text-brand-400">
                                {u}
                              </li>
                            ))}
                          </ul>
                        </div>
                      )}
                      {model.strengths?.length > 0 && (
                        <div>
                          <h4 className="text-xs font-medium text-[var(--muted-text)] mb-2">
                            {t("strengths")}
                          </h4>
                          <ul className="space-y-1">
                            {model.strengths.map((s, i) => (
                              <li key={i} className="text-xs text-[var(--body-text)] pl-3 relative before:content-['·'] before:absolute before:left-0 before:text-brand-400">
                                {s}
                              </li>
                            ))}
                          </ul>
                        </div>
                      )}
                    </div>
                  )}

                  {/* 代码示例 */}
                  <div>
                    <div className="flex items-center justify-between mb-2">
                      <h4 className="text-xs font-medium text-[var(--muted-text)] flex items-center gap-1">
                        <Zap className="h-3 w-3" />
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
                              className={`px-2 py-1 text-xs rounded-md transition-colors ${
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
                      <pre className="bg-[var(--page-bg)] rounded-lg p-4 text-xs text-[var(--body-text)] overflow-x-auto font-mono leading-relaxed">
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
                          <Check className="h-3.5 w-3.5 text-brand-300" />
                        ) : (
                          <Copy className="h-3.5 w-3.5" />
                        )}
                      </button>
                    </div>
                  </div>
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
