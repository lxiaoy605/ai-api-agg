"use client";

import { useTranslations } from "next-intl";
import Link from "next/link";
import Card from "@/components/ui/Card";
import { Check } from "lucide-react";

interface PlanProps {
  title: string;
  price: string;
  period: string;
  description: string;
  features: string[];
  ctaLabel: string;
  ctaHref: string;
  ctaMailto?: boolean;
  featured?: boolean;
}

function PricingCard({ title, price, period, description, features, ctaLabel, ctaHref, ctaMailto, featured }: PlanProps) {
  return (
    <Card
      variant={featured ? "hover" : "default"}
      className={`relative flex flex-col h-full ${featured ? "border-brand-500/30" : ""}`}
    >
      {featured && (
        <div className="absolute -top-3 left-1/2 -translate-x-1/2 px-3 py-1 rounded-full bg-brand-600 text-white text-xs font-medium">
          Popular
        </div>
      )}
      <Card.Content className="flex flex-col h-full">
        <h3 className="text-lg font-semibold text-[var(--body-text)]">{title}</h3>
        <div className="mt-3 flex items-baseline gap-1 h-9">
          {price ? (
            <>
              <span className="text-3xl font-bold text-[var(--body-text)]">{price}</span>
              {period && <span className="text-sm text-[var(--muted-text)]">{period}</span>}
            </>
          ) : (
            <span className="text-sm text-[var(--muted-text)] opacity-75">&mdash;</span>
          )}
        </div>
        <p className="mt-2 text-sm text-[var(--muted-text)]">{description}</p>

        <ul className="mt-6 space-y-3 flex-1">
          {features.map((feat, i) => (
            <li key={i} className="flex items-start gap-3">
              <Check className="h-4 w-4 text-brand-500 shrink-0 mt-0.5" />
              <span className="text-sm text-[var(--body-text)]">{feat}</span>
            </li>
          ))}
        </ul>

        {ctaMailto ? (
          <a
            href={ctaHref}
            className="mt-8 block w-full py-2.5 rounded-lg text-center text-sm font-medium border border-[var(--border-color)] text-[var(--muted-text)] hover:text-[var(--body-text)] hover:border-[var(--border-color)] transition-colors"
          >
            {ctaLabel}
          </a>
        ) : (
          <Link
            href={ctaHref}
            className="mt-8 block w-full py-2.5 rounded-lg text-center text-sm font-medium bg-brand-600 hover:bg-brand-700 text-white transition-colors"
          >
            {ctaLabel}
          </Link>
        )}
      </Card.Content>
    </Card>
  );
}

export default function PricingPage() {
  const t = useTranslations("pricing");

  return (
    <div className="min-h-screen" style={{ background: "var(--page-bg)" }}>
      <div className="mx-auto max-w-6xl px-4 sm:px-6 py-16">
        {/* Header */}
        <div className="text-center mb-12">
          <h1 className="text-3xl font-bold text-[var(--body-text)] sm:text-4xl">
            {t("title")}
          </h1>
        </div>

        {/* Cards */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 max-w-4xl mx-auto mt-5">
          {/* Free Plan */}
          <PricingCard
            title={t("freeTitle")}
            price={t("freePrice")}
            period={t("freePeriod")}
            description={t("freeDesc")}
            features={[
              t("freeFeature1"),
              t("freeFeature2"),
            ]}
            ctaLabel={t("getStarted")}
            ctaHref="/register"
          />

          {/* Starter Plan */}
          <PricingCard
            title={t("starterTitle")}
            price={t("starterPrice")}
            period={t("starterPeriod")}
            description={t("starterDesc")}
            features={[
              t("starterFeature1"),
              t("starterFeature2"),
            ]}
            ctaLabel={t("getStarted")}
            ctaHref="/register"
            featured
          />

          {/* Pro Plan */}
          <PricingCard
            title={t("proTitle")}
            price={t("proPrice")}
            period={t("proPeriod")}
            description={t("proDesc")}
            features={[
              t("proFeature1"),
              t("proFeature2"),
              t("proFeature3"),
            ]}
            ctaLabel={t("contactUs")}
            ctaHref="mailto:support@aiflowhub.ai"
            ctaMailto
          />
        </div>
      </div>
    </div>
  );
}
