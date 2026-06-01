/** API Key 管理 mock 数据 */

export interface ApiKey {
  id: string;
  name: string;
  prefix: string;
  fullKey?: string; // 仅在创建时返回
  status: "active" | "disabled";
  createdAt: string;
  lastUsed: string;
  requestCount: number;
  tokenUsage: number;
}

export const mockApiKeys: ApiKey[] = [];

/** 生成新的 mock Key */
export function generateNewKey(name: string): ApiKey {
  const random = Math.random().toString(36).substring(2, 10);
  const fullKey = `sk-${random}${Math.random().toString(36).substring(2, 14)}`;
  return {
    id: `key-${Date.now()}`,
    name,
    prefix: fullKey.slice(0, 10) + "...",
    fullKey,
    status: "active",
    createdAt: new Date().toISOString().slice(0, 16).replace("T", " "),
    lastUsed: "-",
    requestCount: 0,
    tokenUsage: 0,
  };
}
