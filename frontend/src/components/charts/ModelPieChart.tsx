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
import { modelUsageBreakdown } from "@/data/dashboard";

export default function ModelPieChart() {
  const tc = useTranslations("chart");

  return (
    <div className="bg-neutral-800 rounded-xl border border-neutral-600 p-6">
      <h3 className="text-lg font-semibold text-white mb-4">
        {tc("modelUsageBreakdown")}
      </h3>
      <div className="h-72">
        <ResponsiveContainer width="100%" height="100%">
          <PieChart>
            <Pie
              data={modelUsageBreakdown}
              cx="50%"
              cy="50%"
              innerRadius={60}
              outerRadius={100}
              paddingAngle={2}
              dataKey="value"
            >
              {modelUsageBreakdown.map((entry, index) => (
                <Cell key={`cell-${index}`} fill={entry.color} />
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
                <span className="text-neutral-100 text-sm">{value}</span>
              )}
            />
          </PieChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}
