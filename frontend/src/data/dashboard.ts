/** Dashboard 仪表盘 mock 数据 */

// ── 工作组 ──

export interface Workgroup {
  id: string;
  name: string;
  description: string;
  key_count: number;
  created_at: number;
}

export const workgroups: Workgroup[] = [
  { id: "wg-default", name: "默认工作组", description: "系统默认工作组", key_count: 3, created_at: 1700000000 },
  { id: "wg-prod", name: "生产环境", description: "线上生产环境 API 调用", key_count: 2, created_at: 1700100000 },
  { id: "wg-dev", name: "开发测试", description: "开发与测试环境", key_count: 1, created_at: 1700200000 },
];

// ── 按工作组+模型的用量明细 ──

export interface WorkgroupModelUsage {
  workgroupId: string;
  workgroupName: string;
  modelName: string;
  requests: number;
  tokens: number;
  cost: number;
}

export const modelUsageByWorkgroup: WorkgroupModelUsage[] = [
  // 默认工作组
  { workgroupId: "wg-default", workgroupName: "默认工作组", modelName: "deepseek-v4-flash", requests: 3200, tokens: 850000, cost: 2.55 },
  { workgroupId: "wg-default", workgroupName: "默认工作组", modelName: "glm-5.1", requests: 1800, tokens: 620000, cost: 3.10 },
  { workgroupId: "wg-default", workgroupName: "默认工作组", modelName: "gpt-4o-mini", requests: 950, tokens: 280000, cost: 1.12 },
  // 生产环境
  { workgroupId: "wg-prod", workgroupName: "生产环境", modelName: "deepseek-v4-pro", requests: 2100, tokens: 1200000, cost: 11.00 },
  { workgroupId: "wg-prod", workgroupName: "生产环境", modelName: "mimo-v2.5-pro", requests: 1400, tokens: 750000, cost: 6.75 },
  { workgroupId: "wg-prod", workgroupName: "生产环境", modelName: "deepseek-v4-flash", requests: 1800, tokens: 420000, cost: 1.26 },
  // 开发测试
  { workgroupId: "wg-dev", workgroupName: "开发测试", modelName: "deepseek-v4-flash", requests: 1200, tokens: 350000, cost: 1.05 },
  { workgroupId: "wg-dev", workgroupName: "开发测试", modelName: "claude-3.5-sonnet", requests: 320, tokens: 280000, cost: 5.47 },
  { workgroupId: "wg-dev", workgroupName: "开发测试", modelName: "gpt-4o-mini", requests: 77, tokens: 50000, cost: 0.20 },
];

// ── 按时间+工作组的时序用量 ──

export interface DailyWorkgroupUsage {
  date: string;
  workgroupId: string;
  workgroupName: string;
  requests: number;
  tokens: number;
}

/** 生成过去 days 天、按工作组的每日用量 mock 数据 */
export function generateDailyUsageByWorkgroup(days: number): DailyWorkgroupUsage[] {
  const data: DailyWorkgroupUsage[] = [];
  const now = new Date();
  for (let i = days - 1; i >= 0; i--) {
    const date = new Date(now.getTime() - i * 86400000);
    const dateStr = date.toISOString().slice(0, 10);
    for (const wg of workgroups) {
      const baseReq = wg.id === "wg-default" ? 350 : wg.id === "wg-prod" ? 280 : 80;
      const baseTok = wg.id === "wg-default" ? 120000 : wg.id === "wg-prod" ? 180000 : 40000;
      data.push({
        date: dateStr,
        workgroupId: wg.id,
        workgroupName: wg.name,
        requests: Math.floor(baseReq + Math.random() * baseReq * 0.5),
        tokens: Math.floor(baseTok + Math.random() * baseTok * 0.5),
      });
    }
  }
  return data;
}

// ── 模型消耗占比（饼图用，兼容旧引用） ──

export const modelUsageBreakdown = [
  { name: "deepseek-v4-flash", value: 48, color: "#10b981" },
  { name: "deepseek-v4-pro", value: 16, color: "#6366f1" },
  { name: "mimo-v2.5-pro", value: 11, color: "#ec4899" },
  { name: "glm-5.1", value: 14, color: "#f59e0b" },
  { name: "gpt-4o-mini", value: 8, color: "#8b5cf6" },
  { name: "claude-3.5-sonnet", value: 3, color: "#6b7280" },
];

// ── 旧接口兼容（保留原有导出） ──

export interface OverviewStats {
  activeChannels: number;
  todayRequests: number;
  todayRequestsChange: number;
  remainingQuota: number;
  remainingQuotaPercent: number;
  errorRate: number;
  errorRateChange: number;
}

export const overviewStats: OverviewStats = {
  activeChannels: 5,
  todayRequests: 12847,
  todayRequestsChange: 12.5,
  remainingQuota: 8750000,
  remainingQuotaPercent: 87,
  errorRate: 0.8,
  errorRateChange: -0.3,
};

export interface ChannelHealth {
  id: string;
  name: string;
  provider: string;
  status: "healthy" | "degraded" | "down";
  latencyMs: number;
  successRate: number;
  uptime: string;
}

export const channelHealthList: ChannelHealth[] = [
  { id: "ch-1", name: "DeepSeek V4", provider: "DeepSeek", status: "healthy", latencyMs: 320, successRate: 99.7, uptime: "99.9%" },
  { id: "ch-2", name: "GLM-5.1", provider: "智谱 Z.ai", status: "healthy", latencyMs: 450, successRate: 99.5, uptime: "99.8%" },
  { id: "ch-3", name: "MiMo-V2.5", provider: "小米 MiMo", status: "degraded", latencyMs: 1200, successRate: 95.2, uptime: "98.5%" },
  { id: "ch-4", name: "GPT-4o", provider: "OpenAI", status: "healthy", latencyMs: 580, successRate: 99.9, uptime: "99.99%" },
  { id: "ch-5", name: "Claude 3.5 Sonnet", provider: "Anthropic", status: "down", latencyMs: 0, successRate: 0, uptime: "87.2%" },
];

export interface RecentRequest {
  id: string;
  time: string;
  model: string;
  statusCode: number;
  latencyMs: number;
  cost: string;
  tokens: number;
}

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
