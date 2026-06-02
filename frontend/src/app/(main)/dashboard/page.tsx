"use client";

import { useState, useEffect, useCallback, useMemo } from "react";
import { useTranslations } from "next-intl";
import {
  Activity,
  TrendingUp,
  Layers,
  DollarSign,
  Zap,
  Mail,
  LinkIcon,
} from "lucide-react";
import dynamic from "next/dynamic";
import { apiGet } from "@/services/api";
import { Spinner } from "@/components/ui/Loading";
import type { UsageDataPoint } from "@/components/charts/UsageLineChart";
import type { ModelUsageItem } from "@/components/charts/ModelPieChart";
import type { WorkgroupBarData } from "@/components/charts/WorkgroupBarChart";

const SUPPORT_EMAIL = "user@aiflowhub.com";

const UsageLineChart = dynamic(() => import("@/components/charts/UsageLineChart"), {
  ssr: false,
  loading: () => <div className="h-64 bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] animate-pulse" />,
});

const ModelPieChart = dynamic(() => import("@/components/charts/ModelPieChart"), {
  ssr: false,
  loading: () => <div className="h-64 bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] animate-pulse" />,
});

const WorkgroupBarChart = dynamic(() => import("@/components/charts/WorkgroupBarChart"), {
  ssr: false,
  loading: () => <div className="h-72 bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] animate-pulse" />,
});

interface UserInfo {
  id: number;
  email: string;
  role: string;
  quota: number;
  created_at: number;
  updated_at: number;
}

interface ApiKey {
  id: number;
  name: string;
  key_prefix: string;
  status: string;
  last_used_at: number | null;
}

interface KeyUsage {
  total_requests: number;
  total_tokens: number;
}

// ── API response types ──
interface WorkgroupResponse {
  id: number;
  user_id: number;
  name: string;
  description: string;
  key_count: number;
  created_at: number;
}

interface UsageResponse {
  total_requests: number;
  total_tokens: number;
  total_cost: number;
  workgroups: Array<{
    id: number;
    name: string;
    key_count: number;
    requests: number;
    tokens: number;
    cost: number;
  }>;
  models: Array<{
    model_id: string;
    model_name: string;
    workgroup_id: number;
    workgroup_name: string;
    requests: number;
    tokens: number;
    cost: number;
    percentage: number;
  }>;
  daily: Array<{
    date: string;
    workgroup_id: number;
    workgroup_name: string;
    requests: number;
    tokens: number;
  }>;
}

// ── 工作组聚合 ──
interface WorkgroupOverviewRow {
  id: string;
  name: string;
  keyCount: number;
  requests: number;
  tokens: number;
  cost: number;
}

const BAR_COLORS = ["#10b981", "#6366f1", "#f59e0b", "#ec4899", "#8b5cf6"];

export default function DashboardPage() {
  const t = useTranslations("dashboard");
  const tc = useTranslations("chart");
  const ts = useTranslations("status");

  const [user, setUser] = useState<UserInfo | null>(null);
  const [keys, setKeys] = useState<ApiKey[]>([]);
  const [allUsage, setAllUsage] = useState<KeyUsage | null>(null);
  const [usageData, setUsageData] = useState<UsageDataPoint[]>([]);
  const [modelBreakdown, setModelBreakdown] = useState<ModelUsageItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [realWorkgroups, setRealWorkgroups] = useState<WorkgroupResponse[]>([]);
  const [usageResponse, setUsageResponse] = useState<UsageResponse | null>(null);
  const [lineChartWg, setLineChartWg] = useState("all");
  const [detailWg, setDetailWg] = useState("all");
  const [detailPeriod, setDetailPeriod] = useState<"thisMonth" | "lastMonth" | "last3Months">("thisMonth");

  const loadDashboard = useCallback(async () => {
    try {
      setLoading(true);
      const [userInfo, apiKeys, wkgs, usageResp] = await Promise.all([
        apiGet<UserInfo>("/auth/me"),
        apiGet<ApiKey[]>("/api-keys"),
        apiGet<WorkgroupResponse[]>("/workgroups").catch(() => []),
        apiGet<UsageResponse>("/user/usage").catch(() => null),
      ]);

      setUser(userInfo);
      setKeys(apiKeys || []);

      // 使用真实工作组数据，为空则用 mock
      if (wkgs && wkgs.length > 0) {
        setRealWorkgroups(wkgs);
      }

      // 用量数据
      if (usageResp) {
        setUsageResponse(usageResp);
        const pts: UsageDataPoint[] = (usageResp.daily || []).map((d) => ({
          time: d.date,
          requests: d.requests,
          tokens: d.tokens,
        }));
        pts.sort((a, b) => a.time.localeCompare(b.time));
        setUsageData(pts);

        if (usageResp.models && usageResp.models.length > 0) {
          const colors = ["#10b981", "#6366f1", "#f59e0b", "#ec4899", "#8b5cf6", "#6b7280"];
          const items: ModelUsageItem[] = usageResp.models.map((m, i) => ({
            name: m.model_name,
            value: m.percentage || 0,
            color: colors[i % colors.length],
          }));
          setModelBreakdown(items);
        } else {
          setModelBreakdown([]);
        }
      } else {
        setModelBreakdown([]);
        setUsageData([]);
      }
    } catch (err) {
      console.error("Dashboard load failed:", err);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadDashboard();
  }, [loadDashboard]);

  // ── 工作组聚合 ──
  const workgroupOverview = useMemo<WorkgroupOverviewRow[]>(() => {
    if (usageResponse?.workgroups && usageResponse.workgroups.length > 0) {
      return usageResponse.workgroups.map((wg) => ({
        id: String(wg.id),
        name: wg.name,
        keyCount: wg.key_count,
        requests: wg.requests,
        tokens: wg.tokens,
        cost: wg.cost,
      })).sort((a, b) => b.cost - a.cost);
    }
    return [];
  }, [usageResponse]);

  // 总计
  const totals = useMemo(() => {
    let req = 0, tok = 0, cost = 0;
    for (const r of workgroupOverview) { req += r.requests; tok += r.tokens; cost += r.cost; }
    return { req, tok, cost };
  }, [workgroupOverview]);

  const filteredDetail = useMemo(() => {
    if (!usageResponse?.models || usageResponse.models.length === 0) return [];
    let rows = usageResponse.models.map((m) => ({
      workgroupId: String(m.workgroup_id),
      workgroupName: m.workgroup_name,
      modelName: m.model_name,
      requests: m.requests,
      tokens: m.tokens,
      cost: m.cost,
      percentage: m.percentage || 0,
    }));
    if (detailWg !== "all") {
      rows = rows.filter((r) => r.workgroupId === detailWg);
    }
    return rows;
  }, [detailWg, usageResponse]);

  // 按工作组筛选的折线图数据
  const filteredLineChartData = useMemo(() => {
    if (lineChartWg === "all") return usageData;
    // Filter from API daily data by workgroup_id
    const daily = usageResponse?.daily || [];
    const map = new Map<string, { requests: number; tokens: number }>();
    for (const d of daily) {
      if (String(d.workgroup_id) !== lineChartWg) continue;
      const prev = map.get(d.date) || { requests: 0, tokens: 0 };
      map.set(d.date, { requests: prev.requests + d.requests, tokens: prev.tokens + d.tokens });
    }
    const pts: UsageDataPoint[] = Array.from(map.entries()).map(([time, val]) => ({ time, ...val }));
    pts.sort((a, b) => a.time.localeCompare(b.time));
    return pts;
  }, [lineChartWg, usageData, usageResponse]);

  // 柱状图数据
  const barData = useMemo<WorkgroupBarData[]>(() =>
    workgroupOverview.map((wg, i) => ({
      name: wg.name,
      cost: Math.round(wg.cost * 100) / 100,
      tokens: wg.tokens,
      color: BAR_COLORS[i % BAR_COLORS.length],
    })),
  [workgroupOverview]);

  const showWelcomeBanner = !loading && keys.length === 0;
  const activeKeys = keys.filter((k) => k.status === "active").length;

  return (
    <div className="space-y-6">
      {/* 标题行 + 邮箱 */}
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-[var(--body-text)]">{t("title")}</h1>
          <p className="text-[var(--muted-text)] text-sm mt-1">{t("subtitle")}</p>
        </div>
        <a
          href={`mailto:${SUPPORT_EMAIL}`}
          className="flex items-center gap-1.5 text-xs text-[var(--muted-text)] hover:text-brand-400 transition-colors shrink-0 mt-1"
        >
          <Mail className="h-3.5 w-3.5" />
          {SUPPORT_EMAIL}
        </a>
      </div>

      {/* 加载态 */}
      {loading && (
        <div className="flex items-center justify-center py-20">
          <Spinner className="h-8 w-8 text-brand-600" />
        </div>
      )}

      {/* Welcome banner */}
      {!loading && showWelcomeBanner && (
        <div className="flex items-center justify-between p-4 rounded-xl bg-brand-600/10 border border-brand-600/20">
          <p className="text-sm text-[var(--body-text)] font-medium">{t("welcomeBanner")}</p>
          <a
            href="/api-keys"
            className="px-4 py-2 rounded-lg bg-brand-600 hover:bg-brand-700 text-white text-sm font-medium transition-colors"
          >
            {t("createFirstKey")}
          </a>
        </div>
      )}

      {/* 概览卡片 */}
      {!loading && (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          {/* 工作组数 */}
          <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-5">
            <div className="flex items-center justify-between">
              <span className="text-[var(--muted-text)] text-sm">{t("workgroups")}</span>
              <Layers className="h-5 w-5 text-brand-600" />
            </div>
            <p className="text-3xl font-bold text-brand-300 mt-2">{realWorkgroups.length || 1}</p>
            <p className="text-[var(--muted-text)] text-xs mt-1">
              {activeKeys} {t("activeKeys") || "active keys"}
            </p>
          </div>

          {/* 本月请求 */}
          <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-5">
            <div className="flex items-center justify-between">
              <span className="text-[var(--muted-text)] text-sm">{t("monthlyRequests")}</span>
              <Activity className="h-5 w-5 text-brand-600" />
            </div>
            <p className="text-3xl font-bold text-brand-300 mt-2">
              {(totals.req).toLocaleString()}
            </p>
            <p className="text-[var(--muted-text)] text-xs mt-1">
              <span className="text-brand-300">↑ 12%</span>{" "}
              {t("monthlyRequestsChange", { change: "12" })}
            </p>
          </div>

          {/* 本月 Token */}
          <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-5">
            <div className="flex items-center justify-between">
              <span className="text-[var(--muted-text)] text-sm">{t("monthlyTokens")}</span>
              <Zap className="h-5 w-5 text-yellow-500" />
            </div>
            <p className="text-3xl font-bold text-yellow-400 mt-2">
              {totals.tok >= 1_000_000
                ? `${(totals.tok / 1_000_000).toFixed(1)}M`
                : totals.tok.toLocaleString()}
            </p>
            <p className="text-[var(--muted-text)] text-xs mt-1">
              ~{(totals.tok / 1000).toFixed(0)}K avg per request
            </p>
          </div>

          {/* 本月费用 */}
          <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-5">
            <div className="flex items-center justify-between">
              <span className="text-[var(--muted-text)] text-sm">{t("monthlyCost")}</span>
              <DollarSign className="h-5 w-5 text-brand-600" />
            </div>
            <p className="text-3xl font-bold text-brand-300 mt-2">
              ${totals.cost.toFixed(2)}
            </p>
            <p className="text-[var(--muted-text)] text-xs mt-1">
              {t("remainingQuota")}: {user ? (user.quota / 1000000).toFixed(1) : "0"}M
            </p>
          </div>
        </div>
      )}

      {/* 双栏图表: 工作组花费 + 模型分布 */}
      {!loading && (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <WorkgroupBarChart data={barData} loading={false} />
          <ModelPieChart data={modelBreakdown} loading={false} />
        </div>
      )}

      {/* 月度用量趋势 + 工作组筛选 */}
      {!loading && (
        <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-6">
          <UsageLineChartInner
            t={t}
            tc={tc}
            data={filteredLineChartData}
            loading={false}
            workgroupFilter={lineChartWg}
            onWorkgroupChange={setLineChartWg}
            workgroups={realWorkgroups.map(w => ({ id: String(w.id), name: w.name, key_count: w.key_count }))}
          />
        </div>
      )}

      {/* 用量明细表 */}
      {!loading && (
        <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-6">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 mb-4">
            <h3 className="text-lg font-semibold text-[var(--body-text)]">{t("modelUsageDetail")}</h3>
            <div className="flex gap-2 flex-wrap">
              {/* 工作组筛选 */}
              <select
                value={detailWg}
                onChange={(e) => setDetailWg(e.target.value)}
                className="text-xs rounded-lg px-2 py-1.5 bg-[var(--surface-raised)] border border-[var(--border-muted)] text-[var(--body-text)] focus:outline-none focus:border-brand-500/40"
              >
                <option value="all">{t("allWorkgroups")}</option>
                {realWorkgroups.map((wg) => (
                  <option key={wg.id} value={wg.id}>{wg.name}</option>
                ))}
              </select>
              {/* 时间段 */}
              <div className="flex rounded-lg bg-[var(--surface-raised)] p-0.5">
                {(["thisMonth", "lastMonth", "last3Months"] as const).map((p) => (
                  <button
                    key={p}
                    onClick={() => setDetailPeriod(p)}
                    className={`px-3 py-1.5 text-xs rounded-md transition-colors ${
                      detailPeriod === p
                        ? "bg-brand-600 text-white"
                        : "text-[var(--muted-text)] hover:text-[var(--body-text)]"
                    }`}
                  >
                    {t(p)}
                  </button>
                ))}
              </div>
            </div>
          </div>

          {/* 明细表格 */}
          <div className="overflow-x-auto -mx-6 px-6">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-[var(--border-color)] text-left">
                  <th className="pb-3 text-[var(--muted-text)] font-medium">{t("workgroup")}</th>
                  <th className="pb-3 text-[var(--muted-text)] font-medium">{t("model")}</th>
                  <th className="pb-3 text-[var(--muted-text)] font-medium text-right">{t("requests")}</th>
                  <th className="pb-3 text-[var(--muted-text)] font-medium text-right hidden sm:table-cell">{t("tokens")}</th>
                  <th className="pb-3 text-[var(--muted-text)] font-medium text-right">{t("cost")}</th>
                  <th className="pb-3 text-[var(--muted-text)] font-medium text-right hidden sm:table-cell">{t("percentage")}</th>
                </tr>
              </thead>
              <tbody>
                {filteredDetail.length === 0 ? (
                  <tr>
                    <td colSpan={6} className="py-12 text-center text-sm text-[var(--muted-text)]">
                      {t("noDataHint")}
                    </td>
                  </tr>
                ) : (
                  filteredDetail.map((row, i) => (
                    <tr
                      key={`${row.workgroupId}-${row.modelName}-${i}`}
                      className="border-b border-[var(--border-color)]/50 hover:bg-[var(--surface-raised)]/30 transition-colors"
                    >
                      <td className="py-3 text-[var(--body-text)]">{row.workgroupName}</td>
                      <td className="py-3 text-[var(--body-text)] font-mono text-xs">{row.modelName}</td>
                      <td className="py-3 text-[var(--body-text)] text-right font-mono">{row.requests.toLocaleString()}</td>
                      <td className="py-3 text-[var(--body-text)] text-right font-mono hidden sm:table-cell">
                        {row.tokens >= 1_000_000
                          ? `${(row.tokens / 1_000_000).toFixed(1)}M`
                          : row.tokens.toLocaleString()}
                      </td>
                      <td className="py-3 text-[var(--body-text)] text-right font-mono">${row.cost.toFixed(2)}</td>
                      <td className="py-3 text-[var(--body-text)] text-right font-mono hidden sm:table-cell">
                        {row.percentage}%
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
              {/* 合计行 */}
              {filteredDetail.length > 0 && (
                <tfoot>
                  <tr className="border-t-2 border-[var(--border-color)] font-semibold">
                    <td className="py-3 text-[var(--body-text)]" colSpan={2}>{t("totalRow")}</td>
                    <td className="py-3 text-[var(--body-text)] text-right font-mono">
                      {filteredDetail.reduce((s, r) => s + r.requests, 0).toLocaleString()}
                    </td>
                    <td className="py-3 text-[var(--body-text)] text-right font-mono hidden sm:table-cell">
                      {(() => {
                        const t = filteredDetail.reduce((s, r) => s + r.tokens, 0);
                        return t >= 1_000_000 ? `${(t / 1_000_000).toFixed(1)}M` : t.toLocaleString();
                      })()}
                    </td>
                    <td className="py-3 text-brand-300 text-right font-mono">
                      ${filteredDetail.reduce((s, r) => s + r.cost, 0).toFixed(2)}
                    </td>
                    <td className="py-3 text-[var(--body-text)] text-right font-mono hidden sm:table-cell">100%</td>
                  </tr>
                </tfoot>
              )}
            </table>
          </div>
        </div>
      )}

      {/* 工作组资源概览 */}
      {!loading && (
        <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-6">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-lg font-semibold text-[var(--body-text)]">{t("workgroupOverview")}</h3>
            <a
              href="/api-keys"
              className="text-xs text-brand-400 hover:text-brand-300 transition-colors flex items-center gap-1"
            >
              <LinkIcon className="h-3 w-3" />
              {t("manageApiKeys") || "Manage Keys"}
            </a>
          </div>
          <div className="overflow-x-auto -mx-6 px-6">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-[var(--border-color)] text-left">
                  <th className="pb-3 text-[var(--muted-text)] font-medium">{t("workgroup")}</th>
                  <th className="pb-3 text-[var(--muted-text)] font-medium text-right">{t("keyCount")}</th>
                  <th className="pb-3 text-[var(--muted-text)] font-medium text-right">{t("requests")}</th>
                  <th className="pb-3 text-[var(--muted-text)] font-medium text-right hidden sm:table-cell">{t("tokens")}</th>
                  <th className="pb-3 text-[var(--muted-text)] font-medium text-right">{t("cost")}</th>
                </tr>
              </thead>
              <tbody>
                {workgroupOverview.length === 0 ? (
                  <tr>
                    <td colSpan={5} className="py-12 text-center text-sm text-[var(--muted-text)]">
                      {t("noDataHint")}
                    </td>
                  </tr>
                ) : (
                  workgroupOverview.map((wg) => (
                    <tr
                      key={wg.id}
                      className="border-b border-[var(--border-color)]/50 hover:bg-[var(--surface-raised)]/30 transition-colors cursor-pointer"
                      onClick={() => window.location.href = "/api-keys"}
                    >
                      <td className="py-3 text-[var(--body-text)] font-medium">{wg.name}</td>
                      <td className="py-3 text-[var(--body-text)] text-right">{wg.keyCount}</td>
                      <td className="py-3 text-[var(--body-text)] text-right font-mono">{wg.requests.toLocaleString()}</td>
                      <td className="py-3 text-[var(--body-text)] text-right font-mono hidden sm:table-cell">
                        {wg.tokens >= 1_000_000 ? `${(wg.tokens / 1_000_000).toFixed(1)}M` : wg.tokens.toLocaleString()}
                      </td>
                      <td className="py-3 text-brand-300 text-right font-mono">${wg.cost.toFixed(2)}</td>
                    </tr>
                  ))
                )}
              </tbody>
              {workgroupOverview.length > 0 && (
                <tfoot>
                  <tr className="border-t-2 border-[var(--border-color)] font-semibold">
                    <td className="py-3 text-[var(--body-text)]">{t("totalRow")}</td>
                    <td className="py-3 text-[var(--body-text)] text-right">
                      {workgroupOverview.reduce((s, w) => s + w.keyCount, 0)}
                    </td>
                    <td className="py-3 text-[var(--body-text)] text-right font-mono">
                      {totals.req.toLocaleString()}
                    </td>
                    <td className="py-3 text-[var(--body-text)] text-right font-mono hidden sm:table-cell">
                      {totals.tok >= 1_000_000 ? `${(totals.tok / 1_000_000).toFixed(1)}M` : totals.tok.toLocaleString()}
                    </td>
                    <td className="py-3 text-brand-300 text-right font-mono">${totals.cost.toFixed(2)}</td>
                  </tr>
                </tfoot>
              )}
            </table>
          </div>
        </div>
      )}
    </div>
  );
}

// ── 内嵌折线图（复用 UsageLineChart + 工作组筛选） ──

function UsageLineChartInner({
  t,
  tc,
  data,
  loading,
  workgroupFilter,
  onWorkgroupChange,
  workgroups,
}: {
  t: ReturnType<typeof useTranslations<"dashboard">>;
  tc: ReturnType<typeof useTranslations<"chart">>;
  data: UsageDataPoint[];
  loading: boolean;
  workgroupFilter: string;
  onWorkgroupChange: (v: string) => void;
  workgroups: { id: string; name: string }[];
}) {
  const [range, setRange] = useState<"today" | "7d" | "30d">("7d");
  const [metric, setMetric] = useState<"requests" | "tokens">("requests");

  const rangeMap: Record<string, { label: string; days: number }> = {
    today: { label: tc("today"), days: 1 },
    "7d": { label: tc("last7d"), days: 7 },
    "30d": { label: tc("last30d"), days: 30 },
  };

  const filtered = useMemo(() => {
    if (data.length === 0) return [];
    const days = rangeMap[range].days;
    const now = new Date();
    const cutoff = new Date(now.getTime() - days * 86400000);
    return data.filter((d) => new Date(d.time).getTime() >= cutoff.getTime());
  }, [data, range, rangeMap]);

  const aggregated = useMemo(() => {
    if (filtered.length === 0) return [];
    if (range === "today") return filtered;
    const dayMap = new Map<string, { requests: number; tokens: number }>();
    for (const d of filtered) {
      const day = d.time.slice(0, 10);
      const prev = dayMap.get(day) || { requests: 0, tokens: 0 };
      dayMap.set(day, { requests: prev.requests + d.requests, tokens: prev.tokens + d.tokens });
    }
    return Array.from(dayMap.entries()).map(([time, val]) => ({ time, ...val }));
  }, [filtered, range]);

  const formattedData = useMemo(() =>
    aggregated.map((d) => ({
      ...d,
      displayTime: range === "today" ? d.time.slice(11, 16) : d.time.slice(5, 10),
    })),
  [aggregated, range]);

  return (
    <>
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 mb-6">
        <h3 className="text-lg font-semibold text-[var(--body-text)]">
          {metric === "requests" ? tc("requestCount") : tc("tokenConsumption")} {tc("time")}
        </h3>
        <div className="flex gap-2 flex-wrap">
          {/* 工作组筛选 */}
          <select
            value={workgroupFilter}
            onChange={(e) => onWorkgroupChange(e.target.value)}
            className="text-xs rounded-lg px-2 py-1.5 bg-[var(--surface-raised)] border border-[var(--border-muted)] text-[var(--body-text)] focus:outline-none focus:border-brand-500/40"
          >
            <option value="all">{t("allWorkgroups")}</option>
            {workgroups.map((wg) => (
              <option key={wg.id} value={wg.id}>{wg.name}</option>
            ))}
          </select>
          {/* 指标切换 */}
          <div className="flex rounded-lg bg-[var(--surface-raised)] p-0.5">
            <button
              onClick={() => setMetric("requests")}
              className={`px-3 py-1.5 text-xs rounded-md transition-colors ${
                metric === "requests" ? "bg-brand-600 text-white" : "text-[var(--muted-text)] hover:text-[var(--body-text)]"
              }`}
            >
              {tc("requests")}
            </button>
            <button
              onClick={() => setMetric("tokens")}
              className={`px-3 py-1.5 text-xs rounded-md transition-colors ${
                metric === "tokens" ? "bg-brand-600 text-white" : "text-[var(--muted-text)] hover:text-[var(--body-text)]"
              }`}
            >
              {tc("tokens")}
            </button>
          </div>
          {/* 时间范围 */}
          <div className="flex rounded-lg bg-[var(--surface-raised)] p-0.5">
            {Object.entries(rangeMap).map(([key, val]) => (
              <button
                key={key}
                onClick={() => setRange(key as typeof range)}
                className={`px-3 py-1.5 text-xs rounded-md transition-colors ${
                  range === key ? "bg-brand-600 text-white" : "text-[var(--muted-text)] hover:text-[var(--body-text)]"
                }`}
              >
                {val.label}
              </button>
            ))}
          </div>
        </div>
      </div>

      <div className="h-72">
        {loading ? (
          <div className="flex items-center justify-center h-full">
            <div className="w-8 h-8 border-2 border-brand-600 border-t-transparent rounded-full animate-spin" />
          </div>
        ) : formattedData.length === 0 ? (
          <div className="relative h-full w-full">
            <div className="h-full w-full bg-[var(--surface-raised)]/30 rounded-lg" />
            <div className="absolute inset-0 flex items-center justify-center">
              <span className="text-sm text-[var(--muted-text)]">{t("noDataHint")}</span>
            </div>
          </div>
        ) : (
          <UsageLineChart data={data} loading={false} />
        )}
      </div>
    </>
  );
}
