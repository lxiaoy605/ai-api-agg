/** Dashboard 仪表盘 mock 数据 */

export interface OverviewStats {
  activeChannels: number;
  todayRequests: number;
  todayRequestsChange: number; // 百分比变化
  remainingQuota: number;
  remainingQuotaPercent: number;
  errorRate: number;
  errorRateChange: number; // 正数=恶化, 负数=改善
}

export interface ChannelHealth {
  id: string;
  name: string;
  provider: string;
  status: "healthy" | "degraded" | "down";
  latencyMs: number;
  successRate: number;
  uptime: string;
}

export interface RecentRequest {
  id: string;
  time: string;
  model: string;
  statusCode: number;
  latencyMs: number;
  cost: string;
  tokens: number;
}

// 总览统计
export const overviewStats: OverviewStats = {
  activeChannels: 5,
  todayRequests: 12847,
  todayRequestsChange: 12.5,
  remainingQuota: 8750000,
  remainingQuotaPercent: 87,
  errorRate: 0.8,
  errorRateChange: -0.3,
};

// 渠道健康列表
export const channelHealthList: ChannelHealth[] = [
  {
    id: "ch-1",
    name: "DeepSeek V4",
    provider: "DeepSeek",
    status: "healthy",
    latencyMs: 320,
    successRate: 99.7,
    uptime: "99.9%",
  },
  {
    id: "ch-2",
    name: "GLM-5.1",
    provider: "智谱 Z.ai",
    status: "healthy",
    latencyMs: 450,
    successRate: 99.5,
    uptime: "99.8%",
  },
  {
    id: "ch-3",
    name: "MiMo-V2.5",
    provider: "小米 MiMo",
    status: "degraded",
    latencyMs: 1200,
    successRate: 95.2,
    uptime: "98.5%",
  },
  {
    id: "ch-4",
    name: "GPT-4o",
    provider: "OpenAI",
    status: "healthy",
    latencyMs: 580,
    successRate: 99.9,
    uptime: "99.99%",
  },
  {
    id: "ch-5",
    name: "Claude 3.5 Sonnet",
    provider: "Anthropic",
    status: "down",
    latencyMs: 0,
    successRate: 0,
    uptime: "87.2%",
  },
];

// 最近请求列表
export const recentRequests: RecentRequest[] = [
  { id: "req-001", time: "14:32:01", model: "deepseek-v4-flash", statusCode: 200, latencyMs: 245, cost: "$0.0032", tokens: 1250 },
  { id: "req-002", time: "14:31:58", model: "glm-5.1", statusCode: 200, latencyMs: 412, cost: "$0.0041", tokens: 2100 },
  { id: "req-003", time: "14:31:55", model: "gpt-4o-mini", statusCode: 200, latencyMs: 189, cost: "$0.0012", tokens: 800 },
  { id: "req-004", time: "14:31:52", model: "mimo-v2.5-pro", statusCode: 429, latencyMs: 102, cost: "$0.0000", tokens: 0 },
  { id: "req-005", time: "14:31:49", model: "deepseek-v4-pro", statusCode: 200, latencyMs: 1520, cost: "$0.0120", tokens: 3500 },
  { id: "req-006", time: "14:31:45", model: "claude-3.5-sonnet", statusCode: 503, latencyMs: 0, cost: "$0.0000", tokens: 0 },
  { id: "req-007", time: "14:31:42", model: "gpt-4o", statusCode: 200, latencyMs: 890, cost: "$0.0250", tokens: 1800 },
  { id: "req-008", time: "14:31:38", model: "deepseek-v4-flash", statusCode: 200, latencyMs: 210, cost: "$0.0028", tokens: 1100 },
  { id: "req-009", time: "14:31:35", model: "glm-5.1", statusCode: 200, latencyMs: 350, cost: "$0.0035", tokens: 1600 },
  { id: "req-010", time: "14:31:30", model: "gpt-4o-mini", statusCode: 200, latencyMs: 165, cost: "$0.0010", tokens: 700 },
];

// 用量图表数据 (按小时)
export function generateHourlyUsage(days: number) {
  const data = [];
  const now = new Date();
  const points = days * 24;
  for (let i = points; i >= 0; i--) {
    const date = new Date(now.getTime() - i * 3600000);
    const hour = date.toISOString().slice(0, 13).replace("T", " ");
    data.push({
      time: hour,
      requests: Math.floor(200 + Math.random() * 600),
      tokens: Math.floor(50000 + Math.random() * 150000),
    });
  }
  return data;
}

// 模型消耗占比
export const modelUsageBreakdown = [
  { name: "DeepSeek V4", value: 35, color: "#10b981" },
  { name: "GLM-5.1", value: 25, color: "#6366f1" },
  { name: "GPT-4o Mini", value: 18, color: "#f59e0b" },
  { name: "MiMo V2.5", value: 12, color: "#ec4899" },
  { name: "Claude 3.5", value: 7, color: "#8b5cf6" },
  { name: "其他", value: 3, color: "#6b7280" },
];
