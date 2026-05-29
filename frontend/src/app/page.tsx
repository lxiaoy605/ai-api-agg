"use client";

import { useTranslations } from "next-intl";
import Link from "next/link";
import { useEffect, useState } from "react";
import TopNav from "@/components/layout/TopNav";
import {
  Cpu,
  Zap,
  Brain,
  Layers,
  Wallet,
  Globe,
  ArrowRight,
} from "lucide-react";

const providers = [
  { name: "DeepSeek", icon: Brain },
  { name: "Zhipu AI", icon: Cpu },
  { name: "MiMo", icon: Zap },
];

export default function Home() {
  const t = useTranslations("home");
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
    <div className="min-h-screen bg-neutral-950">
      <TopNav />

      {/* Hero */}
      <section className="pt-28 pb-24 sm:pt-36 sm:pb-32">
        <div className="mx-auto max-w-3xl px-4 sm:px-6 text-center">
          <h1 className="text-5xl font-bold tracking-tight text-neutral-100 sm:text-6xl lg:text-7xl">
            {t("title")}
          </h1>
          <p className="mx-auto mt-6 max-w-xl text-base leading-relaxed text-neutral-300 sm:text-lg">
            {t("subtitle")}
          </p>
          <div className="mt-10 flex items-center justify-center gap-4">
            <Link
              href="/register"
              className="inline-flex items-center rounded-lg bg-brand-600 px-6 py-2.5 text-sm font-medium text-white hover:bg-brand-700 transition-colors"
            >
              {t("ctaPrimary")} <ArrowRight className="ml-1.5 h-4 w-4" />
            </Link>
            <Link
              href="/docs"
              className="inline-flex items-center rounded-lg border border-neutral-600 bg-transparent px-6 py-2.5 text-sm font-medium text-neutral-300 hover:text-neutral-100 hover:border-neutral-500 transition-colors"
            >
              {t("ctaSecondary")}
            </Link>
          </div>
          <p className="mt-5 text-sm text-neutral-400">{t("freeTrial")}</p>
        </div>
      </section>

      {/* 模型展示区 — 图标卡片 */}
      <section className="border-t border-neutral-600 py-16">
        <div className="mx-auto max-w-3xl px-4 sm:px-6 text-center">
          <h2 className="text-sm font-semibold text-neutral-100 tracking-wide uppercase">
            {t("modelsSection")}
          </h2>
          <p className="mt-2 text-sm text-neutral-400">{t("modelsDesc")}</p>
          <div className="mt-8 flex flex-wrap justify-center gap-4">
            {providers.map((p) => {
              const Icon = p.icon;
              return (
                <div
                  key={p.name}
                  className="flex flex-col items-center gap-2 rounded-xl bg-neutral-800 border border-neutral-600 px-5 py-4 hover:border-brand-500/30 hover:bg-neutral-700 transition-all"
                >
                  <Icon className="h-7 w-7 text-brand-600" />
                  <span className="text-xs font-medium text-neutral-300">
                    {p.name}
                  </span>
                </div>
              );
            })}
            <div className="flex flex-col items-center gap-2 rounded-xl border border-dashed border-neutral-600 px-5 py-4">
              <Layers className="h-7 w-7 text-brand-600/40" />
              <span className="text-xs text-neutral-400">
                {t("moreProviders")}
              </span>
            </div>
          </div>
        </div>
      </section>

      {/* 特性区 — 三列图标 */}
      <section className="border-t border-neutral-600 py-16">
        <div className="mx-auto max-w-4xl px-4 sm:px-6 text-center">
          <h2 className="text-sm font-semibold text-neutral-100 tracking-wide uppercase">
            {t("whyUs")}
          </h2>
          <p className="mt-2 text-sm text-neutral-400">{t("whyUsDesc")}</p>
          <div className="mt-10 grid grid-cols-1 gap-8 sm:grid-cols-3">
            <div className="flex flex-col items-center text-center">
              <div className="w-12 h-12 rounded-xl bg-brand-500/10 flex items-center justify-center mb-4">
                <Layers className="h-6 w-6 text-brand-600" />
              </div>
              <h3 className="text-sm font-semibold text-neutral-100">
                One API, All Models
              </h3>
              <p className="mt-2 text-sm text-neutral-300 leading-relaxed">
                Unified API format compatible with all providers
              </p>
            </div>
            <div className="flex flex-col items-center text-center">
              <div className="w-12 h-12 rounded-xl bg-red-500/10 flex items-center justify-center mb-4">
                <Wallet className="h-6 w-6 text-error" />
              </div>
              <h3 className="text-sm font-semibold text-neutral-100">
                Pay What You Use
              </h3>
              <p className="mt-2 text-sm text-neutral-300 leading-relaxed">
                No fixed costs, pay only for the tokens you consume
              </p>
            </div>
            <div className="flex flex-col items-center text-center">
              <div className="w-12 h-12 rounded-xl bg-brand-500/10 flex items-center justify-center mb-4">
                <Globe className="h-6 w-6 text-brand-600" />
              </div>
              <h3 className="text-sm font-semibold text-neutral-100">
                Global Access
              </h3>
              <p className="mt-2 text-sm text-neutral-300 leading-relaxed">
                Deployed globally with low-latency access from anywhere
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-neutral-600 py-8">
        <div className="mx-auto max-w-3xl px-4 sm:px-6 flex flex-col items-center gap-3 sm:flex-row sm:justify-between">
          <div className="flex items-center gap-2 text-xs text-neutral-400">
            <span className="font-medium text-neutral-100">AiflowHub</span>
            <span className="text-neutral-600">·</span>
            <span>{t("footerDesc")}</span>
          </div>
          <div className="flex items-center gap-4 text-xs text-neutral-400">
            <Link href="/terms" className="hover:text-neutral-100">{t("terms")}</Link>
            <Link href="/privacy" className="hover:text-neutral-100">{t("privacy")}</Link>
          </div>
        </div>
      </footer>
    </div>
  );
}
