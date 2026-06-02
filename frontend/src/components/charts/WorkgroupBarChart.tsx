"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  Cell,
} from "recharts";

export interface WorkgroupBarData {
  name: string;
  cost: number;
  tokens: number;
  color: string;
}

interface Props {
  data?: WorkgroupBarData[];
  loading?: boolean;
}

const BAR_COLORS = [
  "#10b981", "#6366f1", "#f59e0b", "#ec4899", "#8b5cf6", "#6b7280",
];

function CustomTooltip({
  active,
  payload,
  label,
  metric,
}: {
  active?: boolean;
  payload?: Array<{ value: number }>;
  label?: string;
  metric: "cost" | "tokens";
}) {
  if (!active || !payload?.length) return null;
  const val = payload[0].value;
  return (
    <div className="bg-[var(--tooltip-bg)] border border-[var(--border-color)] rounded-lg px-3 py-2 shadow-lg backdrop-blur-sm">
      <p className="text-[var(--body-text)] text-sm font-medium mb-0.5">{label}</p>
      <p className="text-[var(--body-text)] text-sm">
        {metric === "tokens"
          ? `${Number(val).toLocaleString()} tokens`
          : `$${Number(val).toFixed(2)}`}
      </p>
    </div>
  );
}

export default function WorkgroupBarChart({ data, loading = false }: Props) {
  const td = useTranslations("dashboard");
  const tc = useTranslations("chart");
  const [metric, setMetric] = useState<"cost" | "tokens">("cost");

  const items = data && data.length > 0 ? data : [];
  const isEmpty = !loading && items.length === 0;

  return (
    <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-6">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 mb-6">
        <h3 className="text-lg font-semibold text-[var(--body-text)]">
          {td("workgroupSpending")}
        </h3>
        <div className="flex rounded-lg bg-[var(--surface-raised)] p-0.5">
          <button
            onClick={() => setMetric("cost")}
            className={`px-3 py-1.5 text-xs rounded-md transition-colors ${
              metric === "cost"
                ? "bg-brand-600 text-white"
                : "text-[var(--muted-text)] hover:text-[var(--body-text)]"
            }`}
          >
            {td("cost")} ($)
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
      </div>

      <div className="h-72">
        {loading ? (
          <div className="flex items-center justify-center h-full">
            <div className="w-8 h-8 border-2 border-brand-600 border-t-transparent rounded-full animate-spin" />
          </div>
        ) : isEmpty ? (
          <div className="relative h-full w-full">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={[{ name: "", cost: 0, tokens: 0 }]}>
                <CartesianGrid strokeDasharray="3 3" stroke="var(--color-neutral-600)" />
                <XAxis dataKey="name" stroke="var(--color-neutral-400)" fontSize={12} />
                <YAxis stroke="var(--color-neutral-400)" fontSize={12} domain={[0, 10]} />
              </BarChart>
            </ResponsiveContainer>
            <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
              <span className="text-sm text-[var(--muted-text)] bg-[var(--card-bg)]/80 px-3 py-1 rounded">
                {td("noDataHint")}
              </span>
            </div>
          </div>
        ) : (
          <ResponsiveContainer width="100%" height="100%">
            <BarChart data={items}>
              <CartesianGrid strokeDasharray="3 3" stroke="var(--color-neutral-600)" />
              <XAxis
                dataKey="name"
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
                tickFormatter={(v: number) =>
                  metric === "tokens"
                    ? v >= 1000000
                      ? `${(v / 1000000).toFixed(1)}M`
                      : `${(v / 1000).toFixed(0)}K`
                    : `$${v}`
                }
              />
              <Tooltip
                cursor={false}
                content={<CustomTooltip metric={metric} />}
              />
              <Bar dataKey={metric} radius={[4, 4, 0, 0]}>
                {items.map((entry, index) => (
                  <Cell
                    key={`cell-${index}`}
                    fill={entry.color || BAR_COLORS[index % BAR_COLORS.length]}
                  />
                ))}
              </Bar>
            </BarChart>
          </ResponsiveContainer>
        )}
      </div>
    </div>
  );
}
