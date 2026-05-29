"use client";

import { useTranslations } from "next-intl";
import {
  Activity,
  TrendingUp,
  TrendingDown,
  Wallet,
  AlertTriangle,
} from "lucide-react";
import { overviewStats, channelHealthList, recentRequests } from "@/data/dashboard";
import UsageLineChart from "@/components/charts/UsageLineChart";
import ModelPieChart from "@/components/charts/ModelPieChart";

export default function DashboardPage() {
  const t = useTranslations("dashboard");
  const ts = useTranslations("status");
  const stats = overviewStats;

  const statusColorMap: Record<string, { dot: string; text: string; labelKey: string }> = {
    healthy: { dot: "bg-brand-500", text: "text-brand-300", labelKey: "healthy" },
    degraded: { dot: "bg-yellow-500", text: "text-yellow-400", labelKey: "degraded" },
    down: { dot: "bg-red-500", text: "text-red-400", labelKey: "down" },
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-[var(--body-text)]">{t("title")}</h1>
        <p className="text-[var(--muted-text)] text-sm mt-1">{t("subtitle")}</p>
      </div>

      {/* 总览卡片 */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-5">
          <div className="flex items-center justify-between">
            <span className="text-[var(--muted-text)] text-sm">{t("activeChannels")}</span>
            <Activity className="h-5 w-5 text-brand-600" />
          </div>
          <p className="text-3xl font-bold text-brand-300 mt-2">
            {stats.activeChannels}
          </p>
          <p className="text-[var(--muted-text)] text-xs mt-1">
            {t("totalChannels", { count: 8 })}
          </p>
        </div>

        <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-5">
          <div className="flex items-center justify-between">
            <span className="text-[var(--muted-text)] text-sm">{t("todayRequests")}</span>
            <TrendingUp className="h-5 w-5 text-brand-600" />
          </div>
          <p className="text-3xl font-bold text-brand-300 mt-2">
            {stats.todayRequests.toLocaleString()}
          </p>
          <p className="text-[var(--muted-text)] text-xs mt-1">
            <span className="text-brand-300">↑ {stats.todayRequestsChange}%</span>{" "}
            {t("vsYesterday")}
          </p>
        </div>

        <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-5">
          <div className="flex items-center justify-between">
            <span className="text-[var(--muted-text)] text-sm">{t("remainingQuota")}</span>
            <Wallet className="h-5 w-5 text-yellow-500" />
          </div>
          <p className="text-3xl font-bold text-yellow-400 mt-2">
            {(stats.remainingQuota / 1000000).toFixed(1)}M
          </p>
          <div className="mt-2 w-full bg-[var(--surface-raised)] rounded-full h-1.5">
            <div
              className="bg-yellow-500 h-1.5 rounded-full transition-all"
              style={{ width: `${stats.remainingQuotaPercent}%` }}
            />
          </div>
          <p className="text-[var(--muted-text)] text-xs mt-1">
            {t("remainingPercent", { percent: stats.remainingQuotaPercent })}
          </p>
        </div>

        <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-5">
          <div className="flex items-center justify-between">
            <span className="text-[var(--muted-text)] text-sm">{t("errorRate")}</span>
            <AlertTriangle className="h-5 w-5 text-red-500" />
          </div>
          <p className="text-3xl font-bold text-red-400 mt-2">
            {stats.errorRate}%
          </p>
          <p className="text-[var(--muted-text)] text-xs mt-1">
            <span className="text-brand-300">
              <TrendingDown className="inline h-3 w-3" />{" "}
              {Math.abs(stats.errorRateChange)}%
            </span>{" "}
            {t("vsYesterday")}
          </p>
        </div>
      </div>

      {/* 渠道健康 + 图表 */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-6">
          <h3 className="text-lg font-semibold text-[var(--body-text)] mb-4">{t("channelHealth")}</h3>
          <div className="space-y-3">
            {channelHealthList.map((ch) => {
              const status = statusColorMap[ch.status];
              return (
                <div
                  key={ch.id}
                  className="flex items-center justify-between p-3 rounded-lg bg-[var(--surface-raised)]/50"
                >
                  <div className="flex items-center gap-3">
                    <div className={`w-2 h-2 rounded-full ${status.dot}`} />
                    <div>
                      <p className="text-sm font-medium text-[var(--body-text)]">
                        {ch.name}
                      </p>
                      <p className="text-xs text-[var(--muted-text)]">{ch.provider}</p>
                    </div>
                  </div>
                  <div className="flex items-center gap-6">
                    <div className="text-right">
                      <p className="text-sm text-[var(--body-text)]">
                        {ch.status === "down" ? "-" : `${ch.latencyMs}ms`}
                      </p>
                      <p className="text-xs text-[var(--muted-text)]">{t("latency")}</p>
                    </div>
                    <div className="text-right">
                      <p className="text-sm text-[var(--body-text)]">
                        {ch.successRate}%
                      </p>
                      <p className="text-xs text-[var(--muted-text)]">{t("successRate")}</p>
                    </div>
                    <span
                      className={`text-xs font-medium px-2 py-0.5 rounded-full ${
                        ch.status === "healthy"
                          ? "bg-brand-500/10 text-brand-300"
                          : ch.status === "degraded"
                          ? "bg-yellow-500/10 text-yellow-400"
                          : "bg-red-500/10 text-red-400"
                      }`}
                    >
                      {ts(status.labelKey)}
                    </span>
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        <ModelPieChart />
      </div>

      <UsageLineChart />

      {/* 最近请求表格 */}
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
              {recentRequests.map((req) => (
                <tr
                  key={req.id}
                  className="border-b border-[var(--border-color)]/50 hover:bg-[var(--surface-raised)]/30 transition-colors"
                >
                  <td className="py-3 text-[var(--body-text)] font-mono text-xs">
                    {req.time}
                  </td>
                  <td className="py-3 text-[var(--body-text)]">{req.model}</td>
                  <td className="py-3">
                    <span
                      className={`text-xs font-mono px-1.5 py-0.5 rounded ${
                        req.statusCode === 200
                          ? "bg-brand-500/10 text-brand-300"
                          : req.statusCode === 429
                          ? "bg-yellow-500/10 text-yellow-400"
                          : "bg-red-500/10 text-red-400"
                      }`}
                    >
                      {req.statusCode}
                    </span>
                  </td>
                  <td className="py-3 text-[var(--muted-text)] font-mono">
                    {req.latencyMs > 0 ? `${req.latencyMs}ms` : "-"}
                  </td>
                  <td className="py-3 text-[var(--body-text)] font-mono">{req.cost}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
