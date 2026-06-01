"use client";

import { useTranslations } from "next-intl";
import {
  PieChart,
  Pie,
  Cell,
  Tooltip,
  ResponsiveContainer,
  Legend,
} from "recharts";

export interface ModelUsageItem {
  name: string;
  value: number;
  color: string;
}

interface Props {
  /** 模型用量占比数据 */
  data?: ModelUsageItem[];
  /** 数据加载中 */
  loading?: boolean;
}

const DEFAULT_COLORS = [
  "#10b981", "#6366f1", "#f59e0b", "#ec4899", "#8b5cf6", "#6b7280",
];

export default function ModelPieChart({ data, loading }: Props) {
  const tc = useTranslations("chart");

  const items = data && data.length > 0
    ? data
    : [{ name: "-", value: 100, color: "#374151" }];

  return (
    <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-6">
      <h3 className="text-lg font-semibold text-[var(--body-text)] mb-4">
        {tc("modelUsageBreakdown")}
      </h3>
      <div className="h-72">
        {loading ? (
          <div className="flex items-center justify-center h-full">
            <div className="w-8 h-8 border-2 border-brand-600 border-t-transparent rounded-full animate-spin" />
          </div>
        ) : !data || data.length === 0 ? (
          <div className="flex items-center justify-center h-full">
            <span className="text-sm text-[var(--muted-text)]">{tc("noData")}</span>
          </div>
        ) : (
          <ResponsiveContainer width="100%" height="100%">
            <PieChart>
              <Pie
                data={items}
                cx="50%"
                cy="50%"
                innerRadius={60}
                outerRadius={100}
                paddingAngle={2}
                dataKey="value"
              >
                {items.map((entry, index) => (
                  <Cell
                    key={`cell-${index}`}
                    fill={entry.color || DEFAULT_COLORS[index % DEFAULT_COLORS.length]}
                  />
                ))}
              </Pie>
              <Tooltip
                contentStyle={{
                  backgroundColor: "var(--color-neutral-700)",
                  border: "1px solid var(--color-neutral-600)",
                  borderRadius: "8px",
                  color: "var(--color-neutral-100)",
                }}
                formatter={(value) => [`${value}%`, tc("percentage")]}
              />
              <Legend
                formatter={(value: string) => (
                  <span className="text-[var(--body-text)] text-sm">{value}</span>
                )}
              />
            </PieChart>
          </ResponsiveContainer>
        )}
      </div>
    </div>
  );
}
