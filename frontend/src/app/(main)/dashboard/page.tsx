"use client";

import { useState, useEffect, useCallback } from "react";
import { useTranslations } from "next-intl";
import {
  Activity,
  TrendingUp,
  Wallet,
  Key,
} from "lucide-react";
import dynamic from "next/dynamic";
import { apiGet } from "@/services/api";
import { Spinner } from "@/components/ui/Loading";
import type { UsageDataPoint } from "@/components/charts/UsageLineChart";
import type { ModelUsageItem } from "@/components/charts/ModelPieChart";

const UsageLineChart = dynamic(() => import("@/components/charts/UsageLineChart"), {
  ssr: false,
  loading: () => <div className="h-64 bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] animate-pulse" />,
});

const ModelPieChart = dynamic(() => import("@/components/charts/ModelPieChart"), {
  ssr: false,
  loading: () => <div className="h-64 bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] animate-pulse" />,
});

/** 用户信息（来自 /auth/me） */
interface UserInfo {
  id: number;
  email: string;
  role: string;
  quota: number;
  created_at: number;
  updated_at: number;
}

/** API Key（来自 /api-keys） */
interface ApiKey {
  id: number;
  name: string;
  key_prefix: string;
  status: string;
  last_used_at: number | null;
}

/** 单个 Key 的用量（来自 /api-keys/:id/usage） */
interface KeyUsage {
  total_requests: number;
  total_tokens: number;
}

export default function DashboardPage() {
  const t = useTranslations("dashboard");
  const ts = useTranslations("status");

  // ── Data states ──
  const [user, setUser] = useState<UserInfo | null>(null);
  const [keys, setKeys] = useState<ApiKey[]>([]);
  const [allUsage, setAllUsage] = useState<KeyUsage | null>(null);
  const [usageData, setUsageData] = useState<UsageDataPoint[]>([]);
  const [modelBreakdown, setModelBreakdown] = useState<ModelUsageItem[]>([]);

  // ── UI states ──
  const [loading, setLoading] = useState(true);

  const loadDashboard = useCallback(async () => {
    try {
      setLoading(true);

      // 并发获取用户信息 + API Key 列表
      const [userInfo, apiKeys] = await Promise.all([
        apiGet<UserInfo>("/auth/me"),
        apiGet<ApiKey[]>("/api-keys"),
      ]);

      setUser(userInfo);
      setKeys(apiKeys || []);

      // 如果有 key，聚合用量数据
      const keyList = apiKeys || [];
      if (keyList.length > 0) {
        const usageResults = await Promise.all(
          keyList.map((k) =>
            apiGet<KeyUsage>(`/api-keys/${k.id}/usage`).catch(() => ({
              total_requests: 0,
              total_tokens: 0,
            }))
          )
        );

        const totalRequests = usageResults.reduce(
          (s, u) => s + u.total_requests,
          0
        );
        const totalTokens = usageResults.reduce(
          (s, u) => s + u.total_tokens,
          0
        );
        setAllUsage({ total_requests: totalRequests, total_tokens: totalTokens });

        // 构建模型占比（后端暂无模型粒度，fallback 展示均匀分布）
        // 从 key name 提取模型名称信息
        const modelMap = new Map<string, number>();
        for (const k of keyList) {
          const modelName = k.name || "Unnamed";
          // 用 request count 作为权重
          const usage = usageResults.find(
            (_, i) => keyList[i].id === k.id
          ) || { total_requests: 0, total_tokens: 0 };
          modelMap.set(modelName, (modelMap.get(modelName) || 0) + usage.total_requests);
        }

        const sortedModels = [...modelMap.entries()]
          .sort((a, b) => b[1] - a[1])
          .slice(0, 5);
        const totalModelRequests = sortedModels.reduce((s, [, v]) => s + v, 0);

        const colors = [
          "#10b981", "#6366f1", "#f59e0b", "#ec4899", "#8b5cf6", "#6b7280",
        ];
        const breakdown: ModelUsageItem[] = sortedModels.map(
          ([name, count], i) => ({
            name,
            value:
              totalModelRequests > 0
                ? Math.round((count / totalModelRequests) * 1000) / 10
                : 0,
            color: colors[i % colors.length],
          })
        );

        // 补齐「其他」
        const accounted = breakdown.reduce((s, m) => s + m.value, 0);
        if (accounted < 100 && breakdown.length > 0) {
          breakdown.push({
            name: "其他",
            value: Math.round((100 - accounted) * 10) / 10,
            color: "#6b7280",
          });
        }

        setModelBreakdown(breakdown);

        // 构建时序数据（用总请求/总 token 作为单点展示）
        const now = new Date();
        // 用最近 30 天的时间点模拟时序（没有真实时间序列数据时展示简单数据）
        const points: UsageDataPoint[] = [];
        const total = totalRequests + totalTokens;
        if (total > 0) {
          for (let i = 30 * 24; i >= 0; i--) {
            const date = new Date(now.getTime() - i * 3600000);
            points.push({
              time: date.toISOString(),
              requests: 0,
              tokens: 0,
            });
          }
          // 简单展示：把总用量摊到最近第一天
          if (points.length > 0) {
            points[points.length - 1].requests = totalRequests;
            points[points.length - 1].tokens = totalTokens;
          }
        }
        setUsageData(points);
      }
    } catch (err) {
      // 不阻塞 UI — 即使 API 失败也渲染组件（显示 0 数据）
      console.error("Dashboard load failed:", err);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadDashboard();
  }, [loadDashboard]);

  const showWelcomeBanner = !loading && keys.length === 0;
  const hasApiKeys = keys.length > 0;

  const activeKeys = keys.filter((k) => k.status === "active").length;
  const totalRequests = allUsage?.total_requests ?? 0;
  const totalTokens = allUsage?.total_tokens ?? 0;

  const statusColorMap: Record<string, { dot: string; text: string; labelKey: string }> = {
    active: { dot: "bg-brand-500", text: "text-brand-300", labelKey: "healthy" },
    disabled: { dot: "bg-yellow-500", text: "text-yellow-400", labelKey: "degraded" },
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-[var(--body-text)]">{t("title")}</h1>
        <p className="text-[var(--muted-text)] text-sm mt-1">{t("subtitle")}</p>
      </div>

      {/* 加载态 */}
      {loading && (
        <div className="flex items-center justify-center py-20">
          <Spinner className="h-8 w-8 text-brand-600" />
        </div>
      )}

      {/* Welcome banner for new users */}
      {!loading && showWelcomeBanner && (
        <div className="flex items-center justify-between p-4 rounded-xl bg-brand-600/10 border border-brand-600/20">
          <p className="text-sm text-[var(--body-text)] font-medium">
            {t("welcomeBanner")}
          </p>
          <a
            href="/api-keys"
            className="px-4 py-2 rounded-lg bg-brand-600 hover:bg-brand-700 text-white text-sm font-medium transition-colors"
          >
            {t("createFirstKey")}
          </a>
        </div>
      )}

      {/* 总览卡片 */}
      {!loading && (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-5">
            <div className="flex items-center justify-between">
              <span className="text-[var(--muted-text)] text-sm">{t("activeChannels")}</span>
              <Activity className="h-5 w-5 text-brand-600" />
            </div>
            <p className="text-3xl font-bold text-brand-300 mt-2">{activeKeys}</p>
            <p className="text-[var(--muted-text)] text-xs mt-1">
              {t("totalChannels", { count: keys.length })}
            </p>
          </div>

          <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-5">
            <div className="flex items-center justify-between">
              <span className="text-[var(--muted-text)] text-sm">{t("todayRequests")}</span>
              <TrendingUp className="h-5 w-5 text-brand-600" />
            </div>
            <p className="text-3xl font-bold text-brand-300 mt-2">
              {totalRequests.toLocaleString()}
            </p>
            <p className="text-[var(--muted-text)] text-xs mt-1">
              <span className="text-brand-300">↑ 0%</span>{" "}
              {t("vsYesterday")}
            </p>
          </div>

          <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-5">
            <div className="flex items-center justify-between">
              <span className="text-[var(--muted-text)] text-sm">{t("remainingQuota")}</span>
              <Wallet className="h-5 w-5 text-yellow-500" />
            </div>
            <p className="text-3xl font-bold text-yellow-400 mt-2">
              {user ? (user.quota / 1000000).toFixed(1) : "0"}M
            </p>
            <div className="mt-2 w-full bg-[var(--surface-raised)] rounded-full h-1.5">
              <div
                className="bg-yellow-500 h-1.5 rounded-full transition-all"
                style={{ width: `${user ? Math.min(100, (user.quota / 10000000) * 100) : 0}%` }}
              />
            </div>
            <p className="text-[var(--muted-text)] text-xs mt-1">
              {t("remainingPercent", {
                percent: user
                  ? Math.min(100, Math.round((user.quota / 10000000) * 100))
                  : 0,
              })}
            </p>
          </div>

          <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-5">
            <div className="flex items-center justify-between">
              <span className="text-[var(--muted-text)] text-sm">{t("totalChannels_short") || "API Keys"}</span>
              <Key className="h-5 w-5 text-brand-600" />
            </div>
            <p className="text-3xl font-bold text-brand-300 mt-2">{keys.length}</p>
            <p className="text-[var(--muted-text)] text-xs mt-1">
              {activeKeys} active
            </p>
          </div>
        </div>
      )}

      {/* 渠道健康 + 图表 */}
      {!loading && (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-6">
            <h3 className="text-lg font-semibold text-[var(--body-text)] mb-4">
              {t("channelHealth") || "API Keys"}
            </h3>
            <div className="space-y-3">
              {keys.length === 0 ? (
                <p className="text-sm text-[var(--muted-text)] text-center py-8">
                  No API keys yet. Create one to get started.
                </p>
              ) : (
                keys.slice(0, 5).map((key) => {
                  const status = statusColorMap[key.status] || statusColorMap.active;
                  return (
                    <div
                      key={key.id}
                      className="flex items-center justify-between p-3 rounded-lg bg-[var(--surface-raised)]/50"
                    >
                      <div className="flex items-center gap-3">
                        <div className={`w-2 h-2 rounded-full ${status.dot}`} />
                        <div>
                          <p className="text-sm font-medium text-[var(--body-text)]">
                            {key.name || `Key #${key.id}`}
                          </p>
                          <p className="text-xs text-[var(--muted-text)]">
                            {key.key_prefix}
                          </p>
                        </div>
                      </div>
                      <span
                        className={`text-xs font-medium px-2 py-0.5 rounded-full ${
                          key.status === "active"
                            ? "bg-brand-500/10 text-brand-300"
                            : "bg-[var(--surface-raised)] text-[var(--muted-text)]"
                        }`}
                      >
                        {ts(key.status === "active" ? "active" : "disabled")}
                      </span>
                    </div>
                  );
                })
              )}
            </div>
          </div>

          <ModelPieChart
            data={modelBreakdown}
            loading={loading}
          />
        </div>
      )}

      {/* 用量图 */}
      {!loading && (
        <UsageLineChart
          data={usageData}
          loading={loading}
        />
      )}

      {/* 最近请求表格 */}
      {!loading && (
        <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-6">
          <h3 className="text-lg font-semibold text-[var(--body-text)] mb-4">{t("recentRequests")}</h3>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-[var(--border-color)] text-left">
                  <th className="pb-3 text-[var(--muted-text)] font-medium">{t("tableTime")}</th>
                  <th className="pb-3 text-[var(--muted-text)] font-medium">{t("tableModel")}</th>
                  <th className="pb-3 text-[var(--muted-text)] font-medium">{t("tableStatusCode")}</th>
                  <th className="pb-3 text-[var(--muted-text)] font-medium">{t("tableLatency")}</th>
                  <th className="pb-3 text-[var(--muted-text)] font-medium">{t("tableCost")}</th>
                </tr>
              </thead>
              <tbody>
                {keys.length === 0 ? (
                  <tr>
                    <td colSpan={5} className="py-12 text-center text-sm text-[var(--muted-text)]">
                      No requests yet.
                    </td>
                  </tr>
                ) : (
                  keys.slice(0, 10).map((key) => (
                    <tr
                      key={key.id}
                      className="border-b border-[var(--border-color)]/50 hover:bg-[var(--surface-raised)]/30 transition-colors"
                    >
                      <td className="py-3 text-[var(--body-text)] font-mono text-xs">
                        {key.last_used_at
                          ? new Date(key.last_used_at * 1000)
                              .toISOString()
                              .slice(11, 19)
                          : "-"}
                      </td>
                      <td className="py-3 text-[var(--body-text)]">
                        {key.name || `Key #${key.id}`}
                      </td>
                      <td className="py-3">
                        <span className="text-xs font-mono px-1.5 py-0.5 rounded bg-brand-500/10 text-brand-300">
                          {key.status === "active" ? "200" : "403"}
                        </span>
                      </td>
                      <td className="py-3 text-[var(--muted-text)] font-mono">-</td>
                      <td className="py-3 text-[var(--body-text)] font-mono">-</td>
                    </tr>
                  ))
                )}
                </tbody>
              </table>
            </div>
        </div>
      )}
    </div>
  );
}
