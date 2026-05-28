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

export const mockApiKeys: ApiKey[] = [
  {
    id: "key-001",
    name: "生产环境 Key",
    prefix: "sk-a1b2c3...",
    status: "active",
    createdAt: "2026-05-15 10:30",
    lastUsed: "2026-05-28 14:32",
    requestCount: 12580,
    tokenUsage: 4520000,
  },
  {
    id: "key-002",
    name: "开发测试 Key",
    prefix: "sk-d4e5f6...",
    status: "active",
    createdAt: "2026-05-20 09:15",
    lastUsed: "2026-05-28 12:10",
    requestCount: 3420,
    tokenUsage: 890000,
  },
  {
    id: "key-003",
    name: "移动端 Key",
    prefix: "sk-g7h8i9...",
    status: "disabled",
    createdAt: "2026-05-10 14:00",
    lastUsed: "2026-05-22 08:45",
    requestCount: 5600,
    tokenUsage: 1200000,
  },
  {
    id: "key-004",
    name: "内部管理 Key",
    prefix: "sk-j0k1l2...",
    status: "active",
    createdAt: "2026-05-01 11:00",
    lastUsed: "2026-05-28 14:35",
    requestCount: 45100,
    tokenUsage: 15800000,
  },
];

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
