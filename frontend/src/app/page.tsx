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
  Globe,
  ArrowRight,
  Sparkles,
  Star,
  Check,
} from "lucide-react";

const providers = [
  { name: "DeepSeek", icon: Brain },
  { name: "GLM", icon: Cpu },
  { name: "Qwen", icon: Sparkles },
  { name: "MiniMax", icon: Zap },
  { name: "Moonshot", icon: Star },
];

const whyItems = [
  "whyItem1",
  "whyItem2",
  "whyItem3",
  "whyItem4",
  "whyItem5",
  "whyItem6",
] as const;

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
    <div className="min-h-screen" style={{ background: "var(--hero-bg)" }}>
      <TopNav />

      {/* Hero */}
      <section className="pt-10 pb-8 sm:pt-10 sm:pb-8">
        <div className="mx-auto max-w-3xl px-4 sm:px-6 text-center">
          <h1 className="animate-slide-up text-5xl font-bold tracking-tight text-[var(--body-text)] sm:text-6xl lg:text-7xl" style={{ animationDelay: "0.1s" }}>
            {t("title")}
          </h1>
          <p className="animate-slide-up mx-auto mt-4 max-w-xl text-base leading-relaxed text-[var(--muted-text)] sm:text-lg" style={{ animationDelay: "0.25s" }}>
            {t("subtitle")}
          </p>
          <div className="animate-fade-in mt-6 flex items-center justify-center gap-4" style={{ animationDelay: "0.45s" }}>
            <Link
              href="/register"
              className="inline-flex items-center rounded-lg bg-brand-600 px-6 py-2 text-sm font-medium text-white hover:bg-brand-700 transition-colors"
            >
              {t("ctaPrimary")} <ArrowRight className="ml-1 h-4 w-4" />
            </Link>
            <Link
              href="/docs"
              className="inline-flex items-center rounded-lg border border-[var(--border-color)] bg-transparent px-6 py-2 text-sm font-medium text-[var(--muted-text)] hover:text-[var(--body-text)] hover:border-[var(--border-color)] transition-colors"
            >
              {t("ctaSecondary")}
            </Link>
          </div>
          <p className="mt-3 text-sm text-[var(--muted-text)]">{t("freeTrial")}</p>
        </div>
      </section>

      {/* 模型展示区 — 5 models */}
      <section className="border-t border-[var(--border-color)] py-8">
        <div className="mx-auto max-w-3xl px-4 sm:px-6 text-center">
          <h2 className="text-sm font-semibold text-[var(--body-text)] tracking-wide uppercase">
            {t("modelsSection")}
          </h2>
          <p className="mt-2 text-sm text-[var(--muted-text)]">{t("modelsDesc")}</p>
          <div className="stagger mt-8 flex flex-wrap justify-center gap-4">
            {providers.map((p) => {
              const Icon = p.icon;
              return (
                <div
                  key={p.name}
                  className="flex flex-col items-center gap-2 rounded-xl bg-[var(--card-bg)] border border-[var(--border-color)] px-4 py-4 hover:border-brand-500/30 hover:bg-[var(--surface-raised)] transition-all"
                >
                  <Icon className="h-7 w-7 text-brand-600" />
                  <span className="text-xs font-medium text-[var(--muted-text)]">
                    {p.name}
                  </span>
                </div>
              );
            })}
            <div className="flex flex-col items-center gap-2 rounded-xl border border-dashed border-[var(--border-color)] px-4 py-4">
              <Layers className="h-7 w-7 text-brand-600/40" />
              <span className="text-xs text-[var(--muted-text)]">
                {t("moreProviders")}
              </span>
            </div>
          </div>
        </div>
      </section>

      {/* 特性区 — 三列 */}
      <section className="border-t border-[var(--border-color)] py-8">
        <div className="mx-auto max-w-4xl px-4 sm:px-6 text-center">
          <h2 className="text-sm font-semibold text-[var(--body-text)] tracking-wide uppercase">
            {t("whyUs")}
          </h2>
          <p className="mt-2 text-sm text-[var(--muted-text)]">{t("whyUsDesc")}</p>
          <div className="stagger mt-8 grid grid-cols-1 gap-8 sm:grid-cols-3">
            <div className="flex flex-col items-center text-center">
              <div className="w-12 h-12 rounded-xl bg-brand-500/10 flex items-center justify-center mb-4">
                <Layers className="h-6 w-6 text-brand-600" />
              </div>
              <h3 className="text-sm font-semibold text-[var(--body-text)]">
                {t("featureUnifiedTitle")}
              </h3>
              <p className="mt-2 text-sm text-[var(--muted-text)] leading-relaxed">
                {t("featureUnifiedDesc")}
              </p>
            </div>
            <div className="flex flex-col items-center text-center">
              <div className="w-12 h-12 rounded-xl bg-brand-500/10 flex items-center justify-center mb-4">
                <Zap className="h-6 w-6 text-brand-600" />
              </div>
              <h3 className="text-sm font-semibold text-[var(--body-text)]">
                {t("featureLatencyTitle")}
              </h3>
              <p className="mt-2 text-sm text-[var(--muted-text)] leading-relaxed">
                {t("featureLatencyDesc")}
              </p>
            </div>
            <div className="flex flex-col items-center text-center">
              <div className="w-12 h-12 rounded-xl bg-brand-500/10 flex items-center justify-center mb-4">
                <Globe className="h-6 w-6 text-brand-600" />
              </div>
              <h3 className="text-sm font-semibold text-[var(--body-text)]">
                {t("featureCompatibleTitle")}
              </h3>
              <p className="mt-2 text-sm text-[var(--muted-text)] leading-relaxed">
                {t("featureCompatibleDesc")}
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Why AiFlowHub — 六大卖点 */}
      <section className="border-t border-[var(--border-color)] py-8">
        <div className="mx-auto max-w-3xl px-4 sm:px-6">
          <h2 className="text-sm font-semibold text-[var(--body-text)] tracking-wide uppercase text-center">
            {t("whySectionTitle")}
          </h2>
          <div className="stagger mt-8 grid grid-cols-1 gap-3 sm:grid-cols-2">
            {whyItems.map((key) => (
              <div
                key={key}
                className="flex items-start gap-3 rounded-lg border border-[var(--border-color)] bg-[var(--card-bg)]/50 px-4 py-3"
              >
                <Check className="mt-1 h-5 w-5 flex-shrink-0 text-brand-600" />
                <span className="text-sm text-[var(--muted-text)]">
                  {t(key)}
                </span>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-[var(--border-color)] py-6">
        <div className="mx-auto max-w-3xl px-4 sm:px-6 flex flex-col items-center gap-3 sm:flex-row sm:justify-between">
          <div className="flex items-center gap-2 text-xs text-[var(--muted-text)]">
            <span className="font-medium text-[var(--body-text)]">AiFlowHub</span>
            <span className="text-[var(--muted-text)]">·</span>
            <span>{t("footerDesc")}</span>
          </div>
          <div className="flex items-center gap-4 text-xs text-[var(--muted-text)]">
            <Link href="/terms" className="hover:text-[var(--body-text)]">{t("terms")}</Link>
            <Link href="/privacy" className="hover:text-[var(--body-text)]">{t("privacy")}</Link>
          </div>
        </div>
      </footer>
    </div>
  );
}
