/** 模型目录数据 — 从 init.sh 生成的 JSON 文件加载 */

import modelsData from "./models-data.json";

export interface ModelInfo {
  id: string;
  name: string;
  provider: string;
  providerLogo: string;
  description: string;
  inputPrice: string; // 每百万 token
  outputPrice: string;
  contextWindow: string;
  maxTokens: string;
  status: "available" | "coming-soon" | "maintenance";
  category: "chat" | "code" | "reasoning" | "multimodal";
  features: string[];
  codeExample: {
    curl: string;
    python: string;
    nodejs: string;
  };
}

export const models: ModelInfo[] = (modelsData as ModelInfo[]) || [];

/** API 文档错误码 */
export const errorCodes = [
  { code: 200, message: "成功", description: "请求已成功处理" },
  { code: 400, message: "请求参数错误", description: "请求体格式不正确或缺少必填参数" },
  { code: 401, message: "认证失败", description: "API Key 无效或已过期" },
  { code: 402, message: "额度不足", description: "账户余额不足以完成本次请求" },
  { code: 429, message: "请求过于频繁", description: "超出速率限制，请稍后重试" },
  { code: 500, message: "服务器内部错误", description: "服务器内部错误，请稍后重试" },
  { code: 503, message: "服务暂不可用", description: "模型服务暂时不可用或正在维护" },
];
