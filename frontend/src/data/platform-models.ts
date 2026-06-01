/**
 * 平台上线模型配置
 * 与 OneAPI 渠道同步：DeepSeek ×4, Zhipu ×2, MiMo ×2（6 渠道，12 子渠道）
 * 模型 ID 使用平台实际 API 调用的模型名，非 OpenRouter 格式
 */

export interface PlatformModelMeta {
  /** 显示名称（从富化数据获取，fallback 用） */
  displayName: string;
  /** 厂商 */
  provider: string;
  /** 富化数据中的 ID（OpenRouter 格式），用于 lookup 描述等 */
  enrichedId: string | null;
  /** 分类 */
  category: "chat" | "code" | "reasoning" | "multimodal";
}

/** 平台上线模型 → 元数据映射 */
export const PLATFORM_MODELS: Record<string, PlatformModelMeta> = {
  // ── DeepSeek ──────────────────────────────
  "deepseek-chat": {
    displayName: "DeepSeek V3",
    provider: "DeepSeek",
    enrichedId: "deepseek/deepseek-chat",
    category: "chat",
  },
  "deepseek-reasoner": {
    displayName: "DeepSeek R1",
    provider: "DeepSeek",
    enrichedId: "deepseek/deepseek-r1",
    category: "reasoning",
  },
  "deepseek-v4-flash": {
    displayName: "DeepSeek V4 Flash",
    provider: "DeepSeek",
    enrichedId: "deepseek/deepseek-v4-flash",
    category: "code",
  },
  "deepseek-v4-pro": {
    displayName: "DeepSeek V4 Pro",
    provider: "DeepSeek",
    enrichedId: "deepseek/deepseek-v4-pro",
    category: "code",
  },

  // ── Zhipu (BigModel) ─────────────────────
  "glm-4": {
    displayName: "GLM-4",
    provider: "Zhipu",
    enrichedId: "z-ai/glm-4-32b",
    category: "chat",
  },
  "glm-4-flash": {
    displayName: "GLM-4 Flash",
    provider: "Zhipu",
    enrichedId: null, // 待补
    category: "chat",
  },
  "glm-4v": {
    displayName: "GLM-4V",
    provider: "Zhipu",
    enrichedId: null, // 待补
    category: "multimodal",
  },
  "glm-4.5": {
    displayName: "GLM-4.5",
    provider: "Zhipu",
    enrichedId: "z-ai/glm-4.5",
    category: "chat",
  },
  "glm-4.5-air": {
    displayName: "GLM-4.5 AIR",
    provider: "Zhipu",
    enrichedId: "z-ai/glm-4.5-air",
    category: "chat",
  },
  "glm-4.6": {
    displayName: "GLM-4.6",
    provider: "Zhipu",
    enrichedId: "z-ai/glm-4.6",
    category: "chat",
  },
  "glm-4.7": {
    displayName: "GLM-4.7",
    provider: "Zhipu",
    enrichedId: "z-ai/glm-4.7",
    category: "chat",
  },
  "glm-5": {
    displayName: "GLM-5",
    provider: "Zhipu",
    enrichedId: "z-ai/glm-5",
    category: "chat",
  },
  "glm-5-turbo": {
    displayName: "GLM-5 Turbo",
    provider: "Zhipu",
    enrichedId: "z-ai/glm-5-turbo",
    category: "chat",
  },
  "glm-5.1": {
    displayName: "GLM-5.1",
    provider: "Zhipu",
    enrichedId: "z-ai/glm-5.1",
    category: "chat",
  },

  // ── MiniMax (旧 API) ──────────────────────
  "abab6.5s-chat": {
    displayName: "ABAB 6.5s",
    provider: "MiniMax",
    enrichedId: null, // 待补
    category: "chat",
  },
  "abab7-chat": {
    displayName: "ABAB 7",
    provider: "MiniMax",
    enrichedId: null, // 待补
    category: "chat",
  },

  // ── Xiaomi MiMo ──────────────────────────
  "mimo-v2-flash": {
    displayName: "MiMo V2 Flash",
    provider: "Xiaomi MiMo",
    enrichedId: "xiaomi/mimo-v2-flash",
    category: "chat",
  },
  "mimo-v2-omni": {
    displayName: "MiMo V2 Omni",
    provider: "Xiaomi MiMo",
    enrichedId: "mimo-v2-omni",
    category: "multimodal",
  },
  "mimo-v2-pro": {
    displayName: "MiMo V2 Pro",
    provider: "Xiaomi MiMo",
    enrichedId: "mimo-v2-pro",
    category: "chat",
  },
  "mimo-v2.5": {
    displayName: "MiMo V2.5",
    provider: "Xiaomi MiMo",
    enrichedId: "xiaomi/mimo-v2.5",
    category: "chat",
  },
  "mimo-v2.5-pro": {
    displayName: "MiMo V2.5 Pro",
    provider: "Xiaomi MiMo",
    enrichedId: "xiaomi/mimo-v2.5-pro",
    category: "chat",
  },
};

/** 平台模型 ID 列表 */
export const PLATFORM_MODEL_IDS = Object.keys(PLATFORM_MODELS);

/** 判断模型是否已上线 */
export function isPlatformModel(id: string): boolean {
  return id in PLATFORM_MODELS;
}

/** 获取平台模型元数据 */
export function getPlatformMeta(id: string): PlatformModelMeta | undefined {
  return PLATFORM_MODELS[id];
}
