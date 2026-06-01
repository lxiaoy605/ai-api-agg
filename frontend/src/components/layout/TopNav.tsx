"use client";

import { useTranslations } from "next-intl";
import { usePathname } from "next/navigation";
import Link from "next/link";
import { useState } from "react";
import { useAuth } from "@/context/AuthContext";
import BrandLogo from "@/components/brand/BrandLogo";
import ThemeSwitcher from "@/components/theme/ThemeSwitcher";
import LocaleSwitcher from "@/components/layout/LocaleSwitcher";
import { Mail } from "lucide-react";

const SUPPORT_EMAIL = "user@aiflowhub.com";

export default function TopNav() {
  const t = useTranslations();
  const pathname = usePathname();
  const { user, logout } = useAuth();
  const [menuOpen, setMenuOpen] = useState(false);
  const [showMail, setShowMail] = useState(false);

  const isLoggedIn = !!user;

  const navLinks = [
    { href: "/models", label: t("nav.models") },
    { href: "/docs", label: t("nav.docs") },
    { href: "/pricing", label: t("nav.pricing") },
  ];

  const handleSignOut = () => {
    logout();
    setMenuOpen(false);
    window.location.href = "/";
  };

  const closeMenu = () => setMenuOpen(false);

  return (
    <header className="fixed top-0 z-50 w-full border-b border-[var(--border-color)] bg-[var(--page-bg)]/95 backdrop-blur supports-[backdrop-filter]:bg-[var(--page-bg)]/60">
      <div className="flex h-14 items-center justify-between px-4 sm:px-6">
        {/* Logo */}
        <Link href="/" className="flex items-center gap-2" onClick={closeMenu}>
          <BrandLogo />
        </Link>

        {/* Desktop nav */}
        <nav className="hidden md:flex items-center gap-2">
          {navLinks.map((link) => {
            const isActive = pathname === link.href || pathname.startsWith(link.href + "/");
            return (
              <Link
                key={link.href}
                href={link.href}
                prefetch={link.href === "/pricing" ? false : undefined}
                className={`text-sm px-3 py-1.5 rounded-lg transition-all ${
                  isActive
                    ? "bg-brand-500/10 text-brand-300 font-medium"
                    : "text-[var(--muted-text)] hover:text-[var(--body-text)] hover:bg-brand-500/8"
                }`}
              >
                {link.label}
              </Link>
            );
          })}
        </nav>

        {/* Desktop auth + theme */}
        <div className="hidden md:flex items-center gap-3">
          {/* 客服邮箱 */}
          <div className="relative">
            <button
              onClick={() => setShowMail(!showMail)}
              className="flex h-8 w-8 items-center justify-center rounded-lg text-[var(--muted-text)] hover:text-[var(--body-text)] hover:bg-[var(--surface-raised)] transition-colors"
              aria-label="Contact support"
            >
              <Mail className="h-4 w-4" />
            </button>
            {showMail && (
              <div className="absolute right-0 mt-2 w-56 rounded-lg border border-[var(--border-color)] bg-[var(--card-bg)] py-2 px-3 shadow-lg">
                <p className="text-xs text-[var(--muted-text)]">Support</p>
                <a href={`mailto:${SUPPORT_EMAIL}`} className="text-sm text-brand-400 hover:text-brand-300 break-all">
                  {SUPPORT_EMAIL}
                </a>
              </div>
            )}
          </div>
          <LocaleSwitcher />
          <ThemeSwitcher />
          {isLoggedIn ? (
            <div className="relative">
              <button
                onClick={() => setMenuOpen(!menuOpen)}
                className="flex h-8 w-8 items-center justify-center rounded-full bg-brand-600 text-white text-xs font-bold hover:bg-brand-700 transition-colors"
                aria-label={t("common.userMenu")}
              >
                {user.email.charAt(0).toUpperCase()}
              </button>
              {menuOpen && (
                <div className="absolute right-0 mt-2 w-40 rounded-lg border border-[var(--border-color)] bg-[var(--card-bg)] py-1 shadow-lg">
                  <Link
                    href="/dashboard"
                    className="block px-4 py-2 text-sm text-[var(--muted-text)] hover:text-[var(--body-text)] hover:bg-[var(--surface-raised)]"
                    onClick={closeMenu}
                  >
                    {t("common.console")}
                  </Link>
                  <Link
                    href="/profile"
                    className="block px-4 py-2 text-sm text-[var(--muted-text)] hover:text-[var(--body-text)] hover:bg-[var(--surface-raised)]"
                    onClick={closeMenu}
                  >
                    Profile
                  </Link>
                  <hr className="my-1 border-[var(--border-color)]" />
                  <button
                    onClick={handleSignOut}
                    className="block w-full text-left px-4 py-2 text-sm text-error hover:bg-red-500/10"
                  >
                    {t("common.signOut")}
                  </button>
                </div>
              )}
            </div>
          ) : (
            <>
              <Link
                href="/login"
                prefetch={false}
                className="text-sm text-[var(--muted-text)] hover:text-[var(--body-text)] hover:bg-brand-500/8 transition-all rounded-lg px-3 py-2"
              >
                {t("common.signIn")}
              </Link>
              <Link
                href="/register"
                prefetch={false}
                className="inline-flex items-center rounded-lg bg-brand-600 px-4 py-2 text-sm font-medium text-white hover:bg-brand-700 transition-all"
              >
                {t("common.signUp")}
              </Link>
            </>
          )}
        </div>

        {/* Mobile toggle */}
        <button
          className="md:hidden flex items-center justify-center rounded-md p-2 text-[var(--muted-text)] hover:bg-[var(--surface-raised)]"
          onClick={() => setMenuOpen(!menuOpen)}
          aria-label={menuOpen ? t("common.closeMenu") : t("common.openMenu")}
        >
          <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            {menuOpen ? (
              <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
            ) : (
              <path strokeLinecap="round" strokeLinejoin="round" d="M4 6h16M4 12h16M4 18h16" />
            )}
          </svg>
        </button>
      </div>

      {/* Mobile nav */}
      {menuOpen && (
        <div className="md:hidden border-t border-[var(--border-color)] bg-[var(--page-bg)] px-4 py-3 space-y-2">
          {navLinks.map((link) => {
            const isActive = pathname === link.href || pathname.startsWith(link.href + "/");
            return (
              <Link
                key={link.href}
                href={link.href}
                prefetch={link.href === "/pricing" ? false : undefined}
                className={`block text-sm px-3 py-2 rounded-lg transition-all ${
                  isActive
                    ? "bg-brand-500/10 text-brand-300 font-medium"
                    : "text-[var(--muted-text)] hover:text-[var(--body-text)] hover:bg-brand-500/8"
                }`}
                onClick={closeMenu}
              >
                {link.label}
              </Link>
            );
          })}
          <hr className="border-[var(--border-color)]" />
          {isLoggedIn ? (
            <>
              <Link href="/dashboard" className="block text-sm font-medium text-[var(--body-text)] py-1.5" onClick={closeMenu}>
                {t("common.console")}
              </Link>
              <Link href="/profile" className="block text-sm text-[var(--muted-text)] py-1.5" onClick={closeMenu}>
                Profile
              </Link>
              <button onClick={handleSignOut} className="block text-sm text-error py-1.5">
                {t("common.signOut")}
              </button>
            </>
          ) : (
            <>
              <Link href="/login" prefetch={false} className="block text-sm text-[var(--muted-text)] hover:text-[var(--body-text)] active:text-[var(--body-text)] py-1.5" onClick={closeMenu}>
                {t("common.signIn")}
              </Link>
              <Link
                href="/register"
                prefetch={false}
                className="inline-flex items-center rounded-lg bg-brand-600 px-4 py-1.5 text-sm font-medium text-white"
                onClick={closeMenu}
              >
                {t("common.signUp")}
              </Link>
            </>
          )}
        </div>
      )}
    </header>
  );
}
