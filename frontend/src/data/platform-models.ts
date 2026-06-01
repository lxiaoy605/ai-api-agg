/**
 * 平台上线模型配置
 * 仅在此列表中的模型才在前端展示（其余 113 个富化数据仅作参考目录）
 * 与 OneAPI 渠道配置同步：DeepSeek×2, Z.ai×2, MiMo×2
 */

export const PLATFORM_MODEL_IDS = new Set([
  // DeepSeek 渠道
  "deepseek/deepseek-chat",
  "deepseek/deepseek-chat-v3-0324",
  "deepseek/deepseek-chat-v3.1",
  "deepseek/deepseek-r1",
  "deepseek/deepseek-r1-0528",

  // 智谱 Z.ai 渠道
  "z-ai/glm-4.5",
  "z-ai/glm-4.5-air",
  "z-ai/glm-4.6",
  "z-ai/glm-4.7",
  "z-ai/glm-4.7-flash",

  // 小米 MiMo 渠道
  "xiaomi/mimo-v2.5",
  "xiaomi/mimo-v2.5-pro",
  "mimo-v2-pro",
  "mimo-v2-omni",
]);

export function isPlatformModel(id: string): boolean {
  return PLATFORM_MODEL_IDS.has(id);
}
