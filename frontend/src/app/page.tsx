"use client";

import { useTranslations } from "next-intl";
import Link from "next/link";
import { useEffect, useState } from "react";
import TopNav from "@/components/layout/TopNav";

const models = [
  "DeepSeek V4",
  "GPT-4o",
  "GPT-4o Mini",
  "Claude 3.5 Sonnet",
  "GLM-5.1",
  "GLM-4.7 Flash",
  "MiMo Pro",
];

export default function Home() {
  const t = useTranslations("home");
  const ct = useTranslations("common");
  const [ready, setReady] = useState(false);

  useEffect(() => {
    if (localStorage.getItem("token")) {
      window.location.href = "/dashboard";
    } else {
      setReady(true);
    }
  }, []);

  if (!ready) return null;

  return (
    <div className="min-h-screen bg-white">
      <TopNav />

      {/* Hero */}
      <section className="pt-24 pb-20 sm:pt-32 sm:pb-24">
        <div className="mx-auto max-w-3xl px-4 sm:px-6 text-center">
          <h1 className="text-4xl font-bold tracking-tight text-gray-900 sm:text-5xl lg:text-6xl">
            {t("title")}
          </h1>
          <p className="mx-auto mt-6 max-w-xl text-base leading-relaxed text-gray-500 sm:text-lg">
            {t("subtitle")}
          </p>
          <div className="mt-8 flex items-center justify-center gap-4">
            <Link
              href="/register"
              className="inline-flex items-center rounded-lg bg-gray-900 px-6 py-2.5 text-sm font-medium text-white hover:bg-gray-800 transition-colors"
            >
              {t("ctaPrimary")} <span className="ml-1.5">→</span>
            </Link>
            <Link
              href="/docs"
              className="inline-flex items-center rounded-lg border border-gray-200 bg-white px-6 py-2.5 text-sm font-medium text-gray-600 hover:text-gray-900 hover:border-gray-300 transition-colors"
            >
              {t("ctaSecondary")}
            </Link>
          </div>
          <p className="mt-4 text-sm text-gray-400">{t("freeTrial")}</p>
        </div>
      </section>

      {/* Models */}
      <section className="border-t border-gray-100 py-14">
        <div className="mx-auto max-w-3xl px-4 sm:px-6 text-center">
          <h2 className="text-sm font-semibold text-gray-900 tracking-wide uppercase">
            {t("modelsSection")}
          </h2>
          <p className="mt-1 text-sm text-gray-400">{t("modelsDesc")}</p>
          <div className="mt-6 flex flex-wrap justify-center gap-2">
            {models.map((m) => (
              <span
                key={m}
                className="inline-flex items-center rounded-md border border-gray-200 bg-gray-50 px-3 py-1 text-xs font-medium text-gray-600"
              >
                {m}
              </span>
            ))}
            <span className="inline-flex items-center rounded-md border border-dashed border-gray-200 px-3 py-1 text-xs text-gray-400">
              + {t("moreProviders")}
            </span>
          </div>
        </div>
      </section>

      {/* Why */}
      <section className="border-t border-gray-100 py-14">
        <div className="mx-auto max-w-xl px-4 sm:px-6 text-center">
          <h2 className="text-sm font-semibold text-gray-900 tracking-wide uppercase">
            {t("whyUs")}
          </h2>
          <p className="mt-3 text-sm leading-relaxed text-gray-500">
            {t("whyUsDesc")}
          </p>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-gray-100 py-8">
        <div className="mx-auto max-w-3xl px-4 sm:px-6 flex flex-col items-center gap-3 sm:flex-row sm:justify-between">
          <div className="flex items-center gap-2 text-xs text-gray-400">
            <span className="font-medium text-gray-600">API Hub</span>
            <span className="text-gray-300">·</span>
            <span>{t("footerDesc")}</span>
          </div>
          <div className="flex items-center gap-4 text-xs text-gray-400">
            <Link href="/terms" className="hover:text-gray-600">{t("terms")}</Link>
            <Link href="/privacy" className="hover:text-gray-600">{t("privacy")}</Link>
          </div>
        </div>
      </footer>
    </div>
  );
}
