"use client";

import { useEffect, useState, useCallback } from "react";
import { useTranslations } from "next-intl";
import { useAuth } from "@/context/AuthContext";
import Card from "@/components/ui/Card";
import { Spinner, Skeleton } from "@/components/ui/Loading";

function formatDate(timestamp: number): string {
  const date = new Date(timestamp * 1000);
  return date.toLocaleDateString("en-US", {
    year: "numeric",
    month: "long",
    day: "numeric",
  });
}

function capitalize(str: string): string {
  return str.charAt(0).toUpperCase() + str.slice(1);
}

export default function ProfilePage() {
  const t = useTranslations("profile");
  const tc = useTranslations("common");
  const { user, refreshUser } = useAuth();

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);

  const loadProfile = useCallback(async () => {
    setLoading(true);
    setError(false);
    try {
      await refreshUser();
    } catch {
      setError(true);
    } finally {
      setLoading(false);
    }
  }, [refreshUser]);

  useEffect(() => {
    loadProfile();
  }, [loadProfile]);

  if (loading) {
    return (
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-bold text-[var(--body-text)]">{t("title")}</h1>
        </div>
        <Card className="max-w-lg">
          <Card.Content>
            <div className="space-y-4">
              <Skeleton className="h-5 w-24" />
              <Skeleton className="h-4 w-48" />
              <Skeleton className="h-4 w-36" />
              <Skeleton className="h-4 w-32" />
              <Skeleton className="h-4 w-28" />
            </div>
          </Card.Content>
        </Card>
      </div>
    );
  }

  if (error || !user) {
    return (
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-bold text-[var(--body-text)]">{t("title")}</h1>
        </div>
        <Card className="max-w-lg">
          <Card.Content>
            <div className="text-center py-6">
              <p className="text-[var(--muted-text)] mb-4">{t("loadError")}</p>
              <button
                onClick={loadProfile}
                className="px-4 py-2 bg-brand-600 hover:bg-brand-700 text-white rounded-lg text-sm font-medium transition-colors"
              >
                {tc("save")}
              </button>
            </div>
          </Card.Content>
        </Card>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-[var(--body-text)]">{t("title")}</h1>
      </div>

      <Card className="max-w-lg">
        <Card.Content>
          <div className="space-y-5">
            {/* Email */}
            <div className="flex items-center justify-between py-2 border-b border-[var(--border-color)]/50">
              <span className="text-sm text-[var(--muted-text)]">{t("email")}</span>
              <span className="text-sm text-[var(--body-text)] font-medium">{user.email}</span>
            </div>

            {/* Member since */}
            <div className="flex items-center justify-between py-2 border-b border-[var(--border-color)]/50">
              <span className="text-sm text-[var(--muted-text)]">{t("memberSince")}</span>
              <span className="text-sm text-[var(--body-text)]">{formatDate(user.created_at)}</span>
            </div>

            {/* Account type */}
            <div className="flex items-center justify-between py-2 border-b border-[var(--border-color)]/50">
              <span className="text-sm text-[var(--muted-text)]">{t("accountType")}</span>
              <span className="text-sm px-2 py-0.5 rounded-full bg-brand-500/10 text-brand-300 font-medium">
                {capitalize(user.role)}
              </span>
            </div>

            {/* Balance */}
            <div className="flex items-center justify-between py-2">
              <span className="text-sm text-[var(--muted-text)]">{t("balance")}</span>
              <span className="text-sm text-[var(--body-text)] font-mono font-semibold">
                ${(user.quota / 100).toFixed(2)} USD
              </span>
            </div>
          </div>
        </Card.Content>
      </Card>
    </div>
  );
}
