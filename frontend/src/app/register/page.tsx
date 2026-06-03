"use client";

import { useState, useEffect, type FormEvent } from "react";
import { useTranslations } from "next-intl";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { useAuth, AuthError } from "@/context/AuthContext";
import BrandLogo from "@/components/brand/BrandLogo";

export default function RegisterPage() {
  const t = useTranslations();
  const router = useRouter();
  const { user, register } = useAuth();

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({});

  // Already logged in — redirect (useEffect to avoid render-phase setState)
  useEffect(() => {
    if (user) router.replace("/dashboard");
  }, [user, router]);

  if (user) return null;

  const validate = (): boolean => {
    const errors: Record<string, string> = {};
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) errors.email = t("auth.invalidEmailFormat");
    const passwordRegex = /^(?=.*[A-Z])(?=.*[a-z])(?=.*\d).{8,}$/;
    if (!passwordRegex.test(password)) errors.password = t("auth.passwordMinLength");
    if (password !== confirmPassword) errors.confirmPassword = t("auth.passwordsMismatch");
    setFieldErrors(errors);
    return Object.keys(errors).length === 0;
  };

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    if (submitting) return; // prevent double-submit flicker
    if (!validate()) return;

    const prevError = error;
    setError(null);
    setSubmitting(true);

    try {
      await register(email, password);
      router.replace("/dashboard");
    } catch (err) {
      setSubmitting(false);
      if (err instanceof AuthError) {
        let msg: string | null = null;
        const body = (err.message || "").toLowerCase();
        if (err.status === 400) {
          if (body.includes("已注册") || body.includes("already") || body.includes("registered") || body.includes("exist")) {
            msg = t("auth.alreadyRegistered") + " " + t("auth.signInInstead");
          } else if (body.includes("邮箱") || body.includes("invalid email") || body.includes("format")) {
            setFieldErrors({ email: t("auth.invalidEmailFormat") });
            return;
          }
        }
        if (!msg) msg = t("auth.networkError");
        if (msg !== prevError) setError(msg);
      } else {
        const msg = t("auth.networkError");
        if (msg !== prevError) setError(msg);
      }
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center p-4" style={{ background: "var(--page-bg)" }}>
      <div className="w-full max-w-sm">
        <div className="text-center mb-8">
          <div className="flex justify-center mb-4">
            <BrandLogo />
          </div>
          <h1 className="text-2xl font-bold text-[var(--body-text)]">{t("auth.signUpTitle")}</h1>
        </div>

        <div className="rounded-xl border border-[var(--border-color)] bg-[var(--card-bg)] p-8 shadow-lg">
          <form onSubmit={handleSubmit} className="space-y-5">
            {/* Error banner */}
            <div className={`overflow-hidden transition-all duration-200 ${error ? "max-h-20 opacity-100" : "max-h-0 opacity-0"}`}>
              <div className="flex items-center gap-2 p-3 rounded-lg bg-red-500/10 border border-red-500/20">
                <svg className="h-4 w-4 text-red-400 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M12 9v3.75m9-.75a9 9 0 11-18 0 9 9 0 0118 0zm-9 3.75h.008v.008H12v-.008z" />
                </svg>
                <p className="text-sm text-red-400">
                  {error}
                  {error?.includes(t("auth.signInInstead")) && (
                    <Link href="/login" className="text-brand-400 hover:text-brand-300 font-medium underline ml-1">
                      {t("common.signIn")}
                    </Link>
                  )}
                </p>
              </div>
            </div>

            <div>
              <label htmlFor="email" className="block text-sm font-medium text-[var(--muted-text)] mb-1.5">
                {t("auth.emailLabel")}
              </label>
              <input
                id="email"
                type="email" maxLength={254}
                value={email}
                onChange={(e) => { setEmail(e.target.value); if (fieldErrors.email) setFieldErrors((p) => ({ ...p, email: "" })); }}
                required
                autoComplete="email"
                autoFocus
                disabled={submitting}
                className={`w-full px-3 py-2.5 bg-[var(--surface-raised)] border rounded-lg text-[var(--body-text)] text-sm placeholder-[var(--muted-text)] focus:outline-none focus:ring-1 transition-colors disabled:opacity-50 ${
                  fieldErrors.email ? "border-red-500/50 focus:ring-red-500/20" : "border-[var(--border-color)] focus:border-brand-500/50 focus:ring-brand-500/20"
                }`}
              />
              {fieldErrors.email && <p className="mt-1 text-xs text-red-400">{fieldErrors.email}</p>}
            </div>

            <div>
              <label htmlFor="password" className="block text-sm font-medium text-[var(--muted-text)] mb-1.5">
                {t("auth.passwordLabel")}
              </label>
              <input
                id="password"
                type="password" maxLength={128}
                value={password}
                onChange={(e) => { setPassword(e.target.value); if (fieldErrors.password) setFieldErrors((p) => ({ ...p, password: "" })); }}
                required
                autoComplete="new-password"
                disabled={submitting}
                className={`w-full px-3 py-2.5 bg-[var(--surface-raised)] border rounded-lg text-[var(--body-text)] text-sm placeholder-[var(--muted-text)] focus:outline-none focus:ring-1 transition-colors disabled:opacity-50 ${
                  fieldErrors.password ? "border-red-500/50 focus:ring-red-500/20" : "border-[var(--border-color)] focus:border-brand-500/50 focus:ring-brand-500/20"
                }`}
              />
              {fieldErrors.password && <p className="mt-1 text-xs text-red-400">{fieldErrors.password}</p>}
            </div>

            <div>
              <label htmlFor="confirmPassword" className="block text-sm font-medium text-[var(--muted-text)] mb-1.5">
                {t("auth.confirmPasswordLabel")}
              </label>
              <input
                id="confirmPassword"
                type="password" maxLength={128}
                value={confirmPassword}
                onChange={(e) => { setConfirmPassword(e.target.value); if (fieldErrors.confirmPassword) setFieldErrors((p) => ({ ...p, confirmPassword: "" })); }}
                required
                autoComplete="new-password"
                disabled={submitting}
                className={`w-full px-3 py-2.5 bg-[var(--surface-raised)] border rounded-lg text-[var(--body-text)] text-sm placeholder-[var(--muted-text)] focus:outline-none focus:ring-1 transition-colors disabled:opacity-50 ${
                  fieldErrors.confirmPassword ? "border-red-500/50 focus:ring-red-500/20" : "border-[var(--border-color)] focus:border-brand-500/50 focus:ring-brand-500/20"
                }`}
              />
              {fieldErrors.confirmPassword && <p className="mt-1 text-xs text-red-400">{fieldErrors.confirmPassword}</p>}
              {confirmPassword && password === confirmPassword && !fieldErrors.confirmPassword && (
                <p className="mt-1 text-xs text-brand-400">{t("auth.passwordsMatch")}</p>
              )}
            </div>

            <button
              type="submit"
              disabled={submitting}
              className="w-full py-2.5 rounded-lg bg-brand-600 hover:bg-brand-700 disabled:bg-neutral-600 disabled:text-neutral-400 text-white font-medium text-sm transition-colors flex items-center justify-center gap-2"
            >
              {submitting ? (
                <>
                  <svg className="h-4 w-4 animate-spin" viewBox="0 0 24 24" fill="none">
                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
                  </svg>
                  {t("auth.creatingAccount")}
                </>
              ) : (
                t("common.signUp")
              )}
            </button>
          </form>

          {/* Divider + OAuth */}
          <div className="mt-5">
            <div className="relative">
              <div className="absolute inset-0 flex items-center">
                <div className="w-full border-t border-[var(--border-color)]" />
              </div>
              <div className="relative flex justify-center text-xs">
                <span className="bg-[var(--card-bg)] px-3 text-[var(--muted-text)]">or continue with</span>
              </div>
            </div>
            <div className="mt-4 grid grid-cols-2 gap-3">
              <button type="button" onClick={() => { const backend = window.location.hostname === 'localhost' ? 'http://localhost:8082' : ''; window.location.href = `${backend}/auth/oauth/github`; }} className="flex items-center justify-center gap-2 py-2.5 rounded-lg border border-[var(--border-color)] text-[var(--body-text)] text-sm font-medium hover:bg-[var(--surface-raised)] transition-colors">
                <svg className="h-4 w-4" viewBox="0 0 24 24" fill="currentColor"><path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"/></svg>
                GitHub
              </button>
              <button type="button" onClick={() => { const backend = window.location.hostname === 'localhost' ? 'http://localhost:8082' : ''; window.location.href = `${backend}/auth/oauth/google`; }} className="flex items-center justify-center gap-2 py-2.5 rounded-lg border border-[var(--border-color)] text-[var(--body-text)] text-sm font-medium hover:bg-[var(--surface-raised)] transition-colors">
                <svg className="h-4 w-4" viewBox="0 0 24 24"><path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 01-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z" fill="#4285F4"/><path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853"/><path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" fill="#FBBC05"/><path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335"/></svg>
                Google
              </button>
            </div>
          </div>

          <p className="mt-6 text-center text-sm text-[var(--muted-text)]">
            {t("auth.alreadyHaveAccount")}{" "}
            <Link href="/login" className="text-brand-400 hover:text-brand-300 font-medium transition-colors">
              {t("common.signIn")}
            </Link>
          </p>
        </div>
      </div>
    </div>
  );
}
