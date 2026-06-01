"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  Legend,
} from "recharts";

export interface UsageDataPoint {
  time: string;
  requests: number;
  tokens: number;
}

interface Props {
  /** 用法数据（按时间排序） */
  data?: UsageDataPoint[];
  /** 数据加载中 */
  loading?: boolean;
}

type Range = "today" | "7d" | "30d";

export default function UsageLineChart({ data = [], loading = false }: Props) {
  const tc = useTranslations("chart");
  const [range, setRange] = useState<Range>("7d");
  const [metric, setMetric] = useState<"requests" | "tokens">("requests");

  const rangeMap: Record<Range, { label: string; days: number }> = {
    today: { label: tc("today"), days: 1 },
    "7d": { label: tc("last7d"), days: 7 },
    "30d": { label: tc("last30d"), days: 30 },
  };

  // 过滤根据 range（简单过滤：按天匹配）
  const filtered = (() => {
    if (data.length === 0) return [];
    const days = rangeMap[range].days;
    const now = new Date();
    const cutoff = new Date(now.getTime() - days * 86400000);
    return data.filter((d) => new Date(d.time).getTime() >= cutoff.getTime());
  })();

  // 聚合：today 按小时，7d/30d 按天
  const aggregated = (() => {
    if (filtered.length === 0) return [];
    if (range === "today") return filtered;
    const dayMap = new Map<string, { requests: number; tokens: number }>();
    for (const d of filtered) {
      const day = d.time.slice(0, 10);
      const prev = dayMap.get(day) || { requests: 0, tokens: 0 };
      dayMap.set(day, {
        requests: prev.requests + d.requests,
        tokens: prev.tokens + d.tokens,
      });
    }
    return Array.from(dayMap.entries()).map(([time, val]) => ({
      time,
      ...val,
    }));
  })();

  const formattedData = aggregated.map((d) => ({
    ...d,
    displayTime:
      range === "today" ? d.time.slice(11, 16) : d.time.slice(5, 10),
  }));

  const metricLabel = metric === "requests" ? tc("requestCount") : tc("tokenConsumption");

  return (
    <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-6">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 mb-6">
        <h3 className="text-lg font-semibold text-[var(--body-text)]">
          {metric === "requests" ? tc("requestCount") : tc("tokenConsumption")}
          {" "}
          {tc("time")}
        </h3>
        <div className="flex gap-2">
          <div className="flex rounded-lg bg-[var(--surface-raised)] p-0.5">
            <button
              onClick={() => setMetric("requests")}
              className={`px-3 py-1.5 text-xs rounded-md transition-colors ${
                metric === "requests"
                  ? "bg-brand-600 text-white"
                  : "text-[var(--muted-text)] hover:text-[var(--body-text)]"
              }`}
            >
              {tc("requests")}
            </button>
            <button
              onClick={() => setMetric("tokens")}
              className={`px-3 py-1.5 text-xs rounded-md transition-colors ${
                metric === "tokens"
                  ? "bg-brand-600 text-white"
                  : "text-[var(--muted-text)] hover:text-[var(--body-text)]"
              }`}
            >
              {tc("tokens")}
            </button>
          </div>
          <div className="flex rounded-lg bg-[var(--surface-raised)] p-0.5">
            {(Object.entries(rangeMap) as [Range, { label: string; days: number }][]).map(
              ([key, val]) => (
                <button
                  key={key}
                  onClick={() => setRange(key)}
                  className={`px-3 py-1.5 text-xs rounded-md transition-colors ${
                    range === key
                      ? "bg-brand-600 text-white"
                      : "text-[var(--muted-text)] hover:text-[var(--body-text)]"
                  }`}
                >
                  {val.label}
                </button>
              )
            )}
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
            {/* 空图框架 — 显示坐标轴骨架 */}
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={[{ displayTime: "", requests: 0, tokens: 0 }]}>
                <CartesianGrid strokeDasharray="3 3" stroke="var(--color-neutral-600)" />
                <XAxis
                  dataKey="displayTime"
                  stroke="var(--color-neutral-400)"
                  fontSize={12}
                  tickLine={false}
                  axisLine={false}
                />
                <YAxis
                  stroke="var(--color-neutral-400)"
                  fontSize={12}
                  tickLine={false}
                  axisLine={false}
                  domain={[0, 10]}
                />
              </LineChart>
            </ResponsiveContainer>
            <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
              <span className="text-sm text-[var(--muted-text)] bg-[var(--card-bg)]/80 px-3 py-1 rounded">{tc("noData")}</span>
            </div>
          </div>
        ) : (
          <ResponsiveContainer width="100%" height="100%">
            <LineChart data={formattedData}>
              <CartesianGrid strokeDasharray="3 3" stroke="var(--color-neutral-600)" />
              <XAxis
                dataKey="displayTime"
                stroke="var(--color-neutral-400)"
                fontSize={12}
                tickLine={false}
                axisLine={false}
                interval="preserveStartEnd"
              />
              <YAxis
                stroke="var(--color-neutral-400)"
                fontSize={12}
                tickLine={false}
                axisLine={false}
                tickFormatter={(v: number) =>
                  metric === "tokens"
                    ? v >= 1000000
                      ? `${(v / 1000000).toFixed(1)}M`
                      : `${(v / 1000).toFixed(0)}K`
                    : v.toString()
                }
              />
              <Tooltip
                contentStyle={{
                  backgroundColor: "var(--color-neutral-700)",
                  border: "1px solid var(--color-neutral-600)",
                  borderRadius: "8px",
                  color: "var(--color-neutral-100)",
                }}
                formatter={(value) => [
                  typeof value === "number"
                    ? value.toLocaleString()
                    : String(value),
                  metric === "tokens" ? tc("tokens") : tc("requestCount"),
                ]}
                labelFormatter={(label) => `${tc("time")}: ${String(label)}`}
              />
              <Legend />
              <Line
                type="monotone"
                dataKey={metric}
                stroke="#7B61FF"
                strokeWidth={2}
                dot={false}
                name={metricLabel}
                activeDot={{ r: 4, fill: "#7B61FF" }}
              />
            </LineChart>
          </ResponsiveContainer>
        )}
      </div>
    </div>
  );
}
