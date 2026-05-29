"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";
import { models as allModels } from "@/data/models";
import type { ModelInfo } from "@/data/models";
import {
  ChevronDown,
  ChevronUp,
  Copy,
  Check,
  Zap,
  Cpu,
  DollarSign,
  Tag,
} from "lucide-react";

const categoryKeys = ["chat", "code", "reasoning", "multimodal"] as const;

const providerColors: Record<string, string> = {
  DeepSeek: "bg-blue-500/10 text-blue-400",
  "Zhipu Z.ai": "bg-purple-500/10 text-purple-400",
  "Xiaomi MiMo": "bg-orange-500/10 text-orange-400",
  OpenAI: "bg-blue-500/10 text-blue-400",
  Anthropic: "bg-amber-500/10 text-amber-400",
};

export default function ModelsPage() {
  const t = useTranslations("models");
  const tc = useTranslations("common");
  const ts = useTranslations("status");
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [codeLang, setCodeLang] = useState<"curl" | "python" | "nodejs">("curl");
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [filterCategory, setFilterCategory] = useState<string>("all");

  const filtered =
    filterCategory === "all"
      ? allModels
      : allModels.filter((m) => m.category === filterCategory);

  const handleCopy = (text: string, id: string) => {
    navigator.clipboard.writeText(text);
    setCopiedId(id);
    setTimeout(() => setCopiedId(null), 2000);
  };

  const getModelDetail = (id: string) => {
    const model = allModels.find((m) => m.id === id);
    return {
      description: model?.description || "",
      features: model?.features || [],
    };
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-[#e2e8f0]">{t("title")}</h1>
        <p className="text-[#94a3b8] text-sm mt-1">{t("subtitle")}</p>
      </div>

      {/* 分类筛选 */}
      <div className="flex gap-2 flex-wrap">
        <button
          onClick={() => setFilterCategory("all")}
          className={`px-3 py-1.5 text-xs rounded-lg transition-colors ${
            filterCategory === "all"
              ? "bg-blue-500/10 text-blue-400 border border-blue-500/20"
              : "text-[#94a3b8] hover:text-[#e2e8f0] bg-[#1a1d2e]/50"
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
                ? "bg-blue-500/10 text-blue-400 border border-blue-500/20"
                : "text-[#94a3b8] hover:text-[#e2e8f0] bg-[#1a1d2e]/50"
            }`}
          >
            {t(`category.${key}`)}
          </button>
        ))}
      </div>

      {/* 模型卡片网格 */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {filtered.map((model) => {
          const isExpanded = expandedId === model.id;
          const detail = getModelDetail(model.id);
          return (
            <div
              key={model.id}
              className="bg-[#141620] rounded-xl border border-[#1e2030] overflow-hidden transition-all hover:border-[#2a2d3e]"
            >
              {/* 卡片头部 */}
              <div
                className="p-5 cursor-pointer"
                onClick={() => setExpandedId(isExpanded ? null : model.id)}
              >
                <div className="flex items-start justify-between mb-3">
                  <div className="flex items-center gap-3">
                    <div
                      className={`w-9 h-9 rounded-lg flex items-center justify-center text-sm font-bold ${
                        providerColors[model.provider] ||
                        "bg-[#1a1d2e] text-[#94a3b8]"
                      }`}
                    >
                      {model.providerLogo}
                    </div>
                    <div>
                      <h3 className="text-sm font-semibold text-[#e2e8f0]">
                        {model.name}
                      </h3>
                      <p className="text-xs text-[#64748b]">{model.provider}</p>
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    <span
                      className={`text-xs px-2 py-0.5 rounded-full ${
                        model.status === "available"
                          ? "bg-blue-500/10 text-blue-400"
                          : model.status === "coming-soon"
                          ? "bg-blue-500/10 text-blue-400"
                          : "bg-yellow-500/10 text-yellow-400"
                      }`}
                    >
                      {ts(model.status)}
                    </span>
                    <span className="text-xs px-2 py-0.5 rounded-full bg-[#1a1d2e] text-[#94a3b8]">
                      {t(`category.${model.category}`)}
                    </span>
                  </div>
                </div>
                <p className="text-xs text-[#94a3b8] leading-relaxed line-clamp-2">
                  {detail.description}
                </p>
                <div className="flex items-center gap-4 mt-3 text-xs text-[#64748b]">
                  <span className="flex items-center gap-1">
                    <DollarSign className="h-3 w-3" />
                    {t("inputPrice", { price: model.inputPrice })}
                  </span>
                  <span className="flex items-center gap-1">
                    <DollarSign className="h-3 w-3" />
                    {t("outputPrice", { price: model.outputPrice })}
                  </span>
                  <span className="flex items-center gap-1">
                    <Cpu className="h-3 w-3" />
                    {model.contextWindow}
                  </span>
                </div>
                <div className="flex items-center justify-between mt-4 pt-3 border-t border-[#1e2030]">
                  <div className="flex gap-1.5">
                    {(Array.isArray(detail.features) ? detail.features : []).slice(0, 3).map((f: string) => (
                      <span
                        key={f}
                        className="text-xs px-1.5 py-0.5 rounded bg-[#1a1d2e] text-[#64748b]"
                      >
                        {f}
                      </span>
                    ))}
                  </div>
                  <button className="text-[#64748b] hover:text-[#e2e8f0] transition-colors">
                    {isExpanded ? (
                      <ChevronUp className="h-4 w-4" />
                    ) : (
                      <ChevronDown className="h-4 w-4" />
                    )}
                  </button>
                </div>
              </div>

              {/* 展开详情 */}
              {isExpanded && (
                <div className="border-t border-[#1e2030] px-5 py-4 space-y-4 bg-[#141620]/50">
                  <div>
                    <h4 className="text-xs font-medium text-[#94a3b8] mb-2 flex items-center gap-1">
                      <Tag className="h-3 w-3" />
                      {t("supportedFeatures")}
                    </h4>
                    <div className="flex gap-1.5 flex-wrap">
                      {(Array.isArray(detail.features) ? detail.features : []).map((f: string) => (
                        <span
                          key={f}
                          className="text-xs px-2 py-1 rounded-full bg-blue-500/10 text-blue-400"
                        >
                          {f}
                        </span>
                      ))}
                    </div>
                  </div>

                  <div className="grid grid-cols-2 gap-3 text-xs">
                    <div className="bg-[#1a1d2e] rounded-lg p-3">
                      <p className="text-[#64748b]">{t("contextWindow")}</p>
                      <p className="text-[#e2e8f0] font-medium">
                        {model.contextWindow}
                      </p>
                    </div>
                    <div className="bg-[#1a1d2e] rounded-lg p-3">
                      <p className="text-[#64748b]">{t("maxOutput")}</p>
                      <p className="text-[#e2e8f0] font-medium">
                        {model.maxTokens}
                      </p>
                    </div>
                    <div className="bg-[#1a1d2e] rounded-lg p-3">
                      <p className="text-[#64748b]">{t("inputPriceLabel")}</p>
                      <p className="text-[#e2e8f0] font-medium">
                        {model.inputPrice}/1M tokens
                      </p>
                    </div>
                    <div className="bg-[#1a1d2e] rounded-lg p-3">
                      <p className="text-[#64748b]">{t("outputPriceLabel")}</p>
                      <p className="text-[#e2e8f0] font-medium">
                        {model.outputPrice}/1M tokens
                      </p>
                    </div>
                  </div>

                  <div>
                    <div className="flex items-center justify-between mb-2">
                      <h4 className="text-xs font-medium text-[#94a3b8] flex items-center gap-1">
                        <Zap className="h-3 w-3" />
                        {t("codeExample")}
                      </h4>
                      <div className="flex rounded-lg bg-[#1a1d2e] p-0.5">
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
                                  ? "bg-[#2a2d3e] text-[#e2e8f0]"
                                  : "text-[#64748b] hover:text-[#e2e8f0]"
                              }`}
                            >
                              {lang === "nodejs" ? "Node.js" : lang}
                            </button>
                          )
                        )}
                      </div>
                    </div>
                    <div className="relative">
                      <pre className="bg-[#050510] rounded-lg p-4 text-xs text-[#e2e8f0] overflow-x-auto font-mono leading-relaxed">
                        {model.codeExample[codeLang]}
                      </pre>
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          handleCopy(model.codeExample[codeLang], model.id);
                        }}
                        className="absolute top-2 right-2 p-1.5 rounded bg-[#1a1d2e] hover:bg-[#2a2d3e] text-[#94a3b8] hover:text-[#e2e8f0] transition-colors"
                      >
                        {copiedId === model.id ? (
                          <Check className="h-3.5 w-3.5 text-blue-400" />
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
      </div>
    </div>
  );
}
