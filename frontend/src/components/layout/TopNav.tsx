"use client";

import { useTranslations } from "next-intl";
import Link from "next/link";
import { useState, useEffect } from "react";
import BrandLogo from "@/components/brand/BrandLogo";
import ThemeSwitcher from "@/components/theme/ThemeSwitcher";

export default function TopNav() {
  const t = useTranslations();
  const [isLoggedIn, setIsLoggedIn] = useState(false);
  const [username, setUsername] = useState("");
  const [menuOpen, setMenuOpen] = useState(false);

  useEffect(() => {
    setIsLoggedIn(!!localStorage.getItem("token"));
    setUsername(localStorage.getItem("username") || "");
  }, []);

  const navLinks = [
    { href: "/models", label: t("nav.models") },
    { href: "/docs", label: t("nav.docs") },
    { href: "/pricing", label: t("nav.pricing") },
  ];

  const handleSignOut = () => {
    localStorage.removeItem("token");
    localStorage.removeItem("username");
    window.location.href = "/";
  };

  return (
    <header className="sticky top-0 z-50 w-full border-b border-neutral-600 bg-neutral-950/95 backdrop-blur supports-[backdrop-filter]:bg-neutral-950/60">
      <div className="mx-auto flex h-14 max-w-6xl items-center justify-between px-4 sm:px-6">
        {/* Logo */}
        <Link href="/" className="flex items-center gap-2">
          <BrandLogo />
        </Link>

        {/* Desktop nav */}
        <nav className="hidden md:flex items-center gap-6">
          {navLinks.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              className="text-sm text-neutral-300 hover:text-neutral-100 transition-colors"
            >
              {link.label}
            </Link>
          ))}
        </nav>

        {/* Desktop auth + theme */}
        <div className="hidden md:flex items-center gap-3">
          <ThemeSwitcher />
          {isLoggedIn ? (
            <div className="relative">
              <button
                onClick={() => setMenuOpen(!menuOpen)}
                className="flex h-8 w-8 items-center justify-center rounded-full bg-brand-600 text-white text-xs font-bold hover:bg-brand-700 transition-colors"
                aria-label={t("common.userMenu")}
              >
                {(username || "U").charAt(0).toUpperCase()}
              </button>
              {menuOpen && (
                <div className="absolute right-0 mt-2 w-36 rounded-lg border border-neutral-600 bg-neutral-800 py-1 shadow-lg">
                  <Link
                    href="/dashboard"
                    className="block px-4 py-2 text-sm text-neutral-300 hover:text-neutral-100 hover:bg-neutral-700"
                    onClick={() => setMenuOpen(false)}
                  >
                    {t("common.console")}
                  </Link>
                  <Link
                    href="/api-keys"
                    className="block px-4 py-2 text-sm text-neutral-300 hover:text-neutral-100 hover:bg-neutral-700"
                    onClick={() => setMenuOpen(false)}
                  >
                    {t("nav.apiKeys")}
                  </Link>
                  <Link
                    href="/recharge"
                    className="block px-4 py-2 text-sm text-neutral-300 hover:text-neutral-100 hover:bg-neutral-700"
                    onClick={() => setMenuOpen(false)}
                  >
                    {t("nav.recharge")}
                  </Link>
                  <hr className="my-1 border-neutral-600" />
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
                className="text-sm text-neutral-300 hover:text-neutral-100 transition-colors"
              >
                {t("common.signIn")}
              </Link>
              <Link
                href="/register"
                className="inline-flex items-center rounded-lg bg-brand-600 px-4 py-1.5 text-sm font-medium text-white hover:bg-brand-700 transition-colors"
              >
                {t("common.signUp")}
              </Link>
            </>
          )}
        </div>

        {/* Mobile toggle */}
        <button
          className="md:hidden flex items-center justify-center rounded-md p-2 text-neutral-300 hover:bg-neutral-700"
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
        <div className="md:hidden border-t border-neutral-600 bg-neutral-950 px-4 py-3 space-y-2">
          {navLinks.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              className="block text-sm text-neutral-300 py-1.5"
              onClick={() => setMenuOpen(false)}
            >
              {link.label}
            </Link>
          ))}
          {isLoggedIn ? (
            <>
              <hr className="border-neutral-600" />
              <Link href="/dashboard" className="block text-sm font-medium text-neutral-100 py-1.5" onClick={() => setMenuOpen(false)}>
                {t("common.console")}
              </Link>
              <Link href="/api-keys" className="block text-sm text-neutral-300 py-1.5" onClick={() => setMenuOpen(false)}>
                {t("nav.apiKeys")}
              </Link>
              <button onClick={handleSignOut} className="block text-sm text-error py-1.5">
                {t("common.signOut")}
              </button>
            </>
          ) : (
            <>
              <hr className="border-neutral-600" />
              <Link href="/login" className="block text-sm text-neutral-300 py-1.5" onClick={() => setMenuOpen(false)}>
                {t("common.signIn")}
              </Link>
              <Link
                href="/register"
                className="inline-flex items-center rounded-lg bg-brand-600 px-4 py-1.5 text-sm font-medium text-white"
                onClick={() => setMenuOpen(false)}
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
