"use client";

import { useTranslations } from "next-intl";
import UsageLineChart from "@/components/charts/UsageLineChart";
import ModelPieChart from "@/components/charts/ModelPieChart";

export default function UsagePage() {
  const t = useTranslations("usage");

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-neutral-100">{t("title")}</h1>
        <p className="text-neutral-300 text-sm mt-1">{t("subtitle")}</p>
      </div>

      <UsageLineChart />

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <ModelPieChart />

        <div className="bg-neutral-800 rounded-xl border border-neutral-600 p-6">
          <h3 className="text-lg font-semibold text-neutral-100 mb-4">{t("summary")}</h3>
          <div className="space-y-4">
            {[
              { labelKey: "monthlyRequests", value: "156,230", change: "+18.5%" },
              { labelKey: "monthlyTokens", value: "42.8M", change: "+22.3%" },
              { labelKey: "avgLatency", value: "380ms", change: "-5.2%" },
              { labelKey: "monthlyCost", value: "$48.50", change: "+12.0%" },
            ].map((item) => (
              <div
                key={item.labelKey}
                className="flex items-center justify-between p-3 rounded-lg bg-neutral-700/50"
              >
                <span className="text-sm text-neutral-300">{t(item.labelKey)}</span>
                <div className="text-right">
                  <p className="text-sm font-semibold text-neutral-100">
                    {item.value}
                  </p>
                  <p
                    className={`text-xs ${
                      item.change.startsWith("+")
                        ? "text-brand-300"
                        : "text-brand-300"
                    }`}
                  >
                    {item.change} {t("vsLastMonth")}
                  </p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
