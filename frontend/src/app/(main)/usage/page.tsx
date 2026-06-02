"use client";

import { useState, useEffect, useCallback } from "react";
import { useTranslations } from "next-intl";
import { AlertTriangle } from "lucide-react";
import { apiGet } from "@/services/api";
import { ApiError } from "@/services/api";
import { Spinner } from "@/components/ui/Loading";
import UsageLineChart, {
  type UsageDataPoint,
} from "@/components/charts/UsageLineChart";
import ModelPieChart, {
  type ModelUsageItem,
} from "@/components/charts/ModelPieChart";

/** API Key 最小结构 */
interface ApiKey {
  id: number;
  name: string;
  key_prefix: string;
  status: string;
}

/** 一个 Key 的用量 */
interface KeyUsage {
  total_requests: number;
  total_tokens: number;
}

export default function UsagePage() {
  const t = useTranslations("usage");

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // 聚合数据
  const [totalRequests, setTotalRequests] = useState(0);
  const [totalTokens, setTotalTokens] = useState(0);
  const [usageData, setUsageData] = useState<UsageDataPoint[]>([]);
  const [modelBreakdown, setModelBreakdown] = useState<ModelUsageItem[]>([]);
  const [keyCount, setKeyCount] = useState(0);

  const loadUsage = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);

      const keys = await apiGet<ApiKey[]>("/api-keys");
      const keyList = keys || [];
      setKeyCount(keyList.length);

      let sumRequests = 0;
      let sumTokens = 0;

      // 模型分布
      const modelMap = new Map<string, number>();

      if (keyList.length > 0) {
        const results = await Promise.all(
          keyList.map((k) =>
            apiGet<KeyUsage>(`/api-keys/${k.id}/usage`).catch(() => ({
              total_requests: 0,
              total_tokens: 0,
            }))
          )
        );

        for (let i = 0; i < keyList.length; i++) {
          const usage = results[i];
          sumRequests += usage.total_requests;
          sumTokens += usage.total_tokens;
          const name = keyList[i].name || `Key #${keyList[i].id}`;
          modelMap.set(name, (modelMap.get(name) || 0) + usage.total_requests);
        }
      }

      setTotalRequests(sumRequests);
      setTotalTokens(sumTokens);

      // 构建模型占比
      const sorted = [...modelMap.entries()].sort((a, b) => b[1] - a[1]).slice(0, 5);
      const total = sorted.reduce((s, [, v]) => s + v, 0);
      const colors = [
        "#10b981", "#6366f1", "#f59e0b", "#ec4899", "#8b5cf6", "#6b7280",
      ];
      const breakdown: ModelUsageItem[] = sorted.map(([name, count], i) => ({
        name,
        value: total > 0 ? Math.round((count / total) * 1000) / 10 : 0,
        color: colors[i % colors.length],
      }));
      const accounted = breakdown.reduce((s, m) => s + m.value, 0);
      if (accounted < 100 && breakdown.length > 0) {
        breakdown.push({
          name: "Other",
          value: Math.round((100 - accounted) * 10) / 10,
          color: "#6b7280",
        });
      }
      setModelBreakdown(breakdown);

      // 时序数据
      const now = new Date();
      const points: UsageDataPoint[] = [];
      if (sumRequests + sumTokens > 0) {
        for (let i = 30 * 24; i >= 0; i--) {
          const date = new Date(now.getTime() - i * 3600000);
          points.push({
            time: date.toISOString(),
            requests: 0,
            tokens: 0,
          });
        }
        if (points.length > 0) {
          points[points.length - 1].requests = sumRequests;
          points[points.length - 1].tokens = sumTokens;
        }
      }
      setUsageData(points);
    } catch (err) {
      const msg =
        err instanceof ApiError ? err.message : "Failed to load usage data";
      setError(msg);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadUsage();
  }, [loadUsage]);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-[var(--body-text)]">{t("title")}</h1>
        <p className="text-[var(--muted-text)] text-sm mt-1">{t("subtitle")}</p>
      </div>

      {/* 错误提示 */}
      {error && (
        <div className="flex items-center gap-2 p-3 rounded-lg bg-red-500/10 border border-red-500/20 text-sm text-red-400">
          <AlertTriangle className="h-4 w-4 shrink-0" />
          {error}
        </div>
      )}

      {/* 加载态 */}
      {loading && (
        <div className="flex items-center justify-center py-20">
          <Spinner className="h-8 w-8 text-brand-600" />
        </div>
      )}

      {/* 空状态 */}
      {!loading && keyCount === 0 && (
        <div className="flex flex-col items-center justify-center py-20 text-center">
          <p className="text-sm text-[var(--muted-text)] mb-4">
            No API keys yet. Create one on the API Keys page.
          </p>
          <a
            href="/api-keys"
            className="px-4 py-2 bg-brand-600 hover:bg-brand-700 text-white rounded-lg text-sm font-medium transition-colors"
          >
            Create API Key
          </a>
        </div>
      )}

      {/* 主内容 */}
      {!loading && keyCount > 0 && (
        <>
          <UsageLineChart data={usageData} loading={loading} />

          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <ModelPieChart data={modelBreakdown} loading={loading} />

            <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-6">
              <h3 className="text-lg font-semibold text-[var(--body-text)] mb-4">{t("summary")}</h3>
              <div className="space-y-4">
                {[
                  {
                    labelKey: "monthlyRequests",
                    value: totalRequests.toLocaleString(),
                    change: "-",
                  },
                  {
                    labelKey: "monthlyTokens",
                    value: `${(totalTokens / 1000).toFixed(1)}K`,
                    change: "-",
                  },
                  {
                    labelKey: "avgLatency",
                    value: "-",
                    change: "-",
                  },
                  {
                    labelKey: "monthlyCost",
                    value: "$0.00",
                    change: "-",
                  },
                ].map((item) => (
                  <div
                    key={item.labelKey}
                    className="flex items-center justify-between p-3 rounded-lg bg-[var(--surface-raised)]/50"
                  >
                    <span className="text-sm text-[var(--muted-text)]">{t(item.labelKey)}</span>
                    <div className="text-right">
                      <p className="text-sm font-semibold text-[var(--body-text)]">
                        {item.value}
                      </p>
                      <p className="text-xs text-[var(--muted-text)]">
                        {item.change} {t("vsLastMonth")}
                      </p>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </>
      )}
    </div>
  );
}
