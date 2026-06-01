/** 模型目录数据 — 分页加载，自动聚合 */

import page1 from "./models/page-1.json";
import page2 from "./models/page-2.json";
import page3 from "./models/page-3.json";
import page4 from "./models/page-4.json";
import page5 from "./models/page-5.json";
import page6 from "./models/page-6.json";
import page7 from "./models/page-7.json";
import page8 from "./models/page-8.json";

/** 多语言模型介绍 — 对应平台 UI 语言 (en/ru/tr) */
export interface ModelDescriptions {
  zh: string;
  en: string;
  ru: string;
  tr: string;
}

export interface ModelInfo {
  id: string;
  name: string;
  provider: string;
  providerLogo: string;
  /** @deprecated 保留兼容，新代码请用 descriptions */
  description: string;
  descriptions: ModelDescriptions;
  inputPrice: string;
  outputPrice: string;
  contextWindow: string;
  maxTokens: string;
  status: "available" | "coming-soon" | "maintenance";
  category: "chat" | "code" | "reasoning" | "multimodal";
  features: string[];
  useCases: string[];
  strengths: string[];
  whyChoose: {
    en: string;
    ru: string;
    tr: string;
  };
  codeExample: {
    curl: string;
    python: string;
    nodejs: string;
  };
}

/** 所有模型（自动聚合全部页面） */
export const models: ModelInfo[] = [
  ...(page1 as ModelInfo[]),
  ...(page2 as ModelInfo[]),
  ...(page3 as ModelInfo[]),
  ...(page4 as ModelInfo[]),
  ...(page5 as ModelInfo[]),
  ...(page6 as ModelInfo[]),
  ...(page7 as ModelInfo[]),
  ...(page8 as ModelInfo[]),
];

/**
 * 模糊搜索模型 — 匹配名称、厂商、分类、功能标签
 * 使用 locale 感知的描述字段
 */
export function searchModels(
  query: string,
  locale: "en" | "ru" | "tr" | "zh" = "en"
): ModelInfo[] {
  const q = query.toLowerCase().trim();
  if (!q) return models;

  return models.filter((m) => {
    // 名称精确匹配加权
    if (m.name.toLowerCase().includes(q)) return true;
    // 厂商名
    if (m.provider.toLowerCase().includes(q)) return true;
    // 多语言描述
    const desc = locale === "zh" ? (m.descriptions?.zh || m.description) : (m.descriptions?.[locale] || "");
    if (desc.toLowerCase().includes(q)) return true;
    // 其他语言补充搜索
    if (locale !== "en" && m.descriptions?.en?.toLowerCase().includes(q)) return true;
    // 功能标签
    if (m.features.some((f) => f.toLowerCase().includes(q))) return true;
    // 使用场景
    if (m.useCases?.some((u) => u.toLowerCase().includes(q))) return true;
    // 分类
    if (m.category.toLowerCase().includes(q)) return true;

    return false;
  });
}

export const errorCodes = [
  { code: 200, message: "成功", description: "请求已成功处理" },
  { code: 400, message: "请求参数错误", description: "请求体格式不正确或缺少必填参数" },
  { code: 401, message: "认证失败", description: "API Key 无效或已过期" },
  { code: 402, message: "额度不足", description: "账户余额不足以完成本次请求" },
  { code: 429, message: "请求过于频繁", description: "超出速率限制，请稍后重试" },
  { code: 500, message: "服务器内部错误", description: "服务器内部错误，请稍后重试" },
  { code: 503, message: "服务暂不可用", description: "模型服务暂时不可用或正在维护" },
];
