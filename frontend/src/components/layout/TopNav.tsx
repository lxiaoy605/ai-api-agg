"use client";

import { useTranslations } from "next-intl";
import Link from "next/link";
import { useState, useEffect } from "react";

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
    <header className="sticky top-0 z-50 w-full border-b border-[#1e2030] bg-[#0a0a10]/95 backdrop-blur supports-[backdrop-filter]:bg-[#0a0a10]/60">
      <div className="mx-auto flex h-14 max-w-6xl items-center justify-between px-4 sm:px-6">
        {/* Logo */}
        <Link href="/" className="flex items-center gap-2 text-sm font-semibold tracking-tight">
          <span className="flex h-7 w-7 items-center justify-center rounded-md bg-[#3b82f6] text-white text-xs font-bold">
            ⚡
          </span>
          <span className="text-[#e2e8f0]">{t("nav.brand")}</span>
        </Link>

        {/* Desktop nav */}
        <nav className="hidden md:flex items-center gap-6">
          {navLinks.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              className="text-sm text-[#94a3b8] hover:text-[#e2e8f0] transition-colors"
            >
              {link.label}
            </Link>
          ))}
        </nav>

        {/* Desktop auth */}
        <div className="hidden md:flex items-center gap-3">
          {isLoggedIn ? (
            <div className="relative">
              <button
                onClick={() => setMenuOpen(!menuOpen)}
                className="flex h-8 w-8 items-center justify-center rounded-full bg-[#3b82f6] text-white text-xs font-bold hover:bg-blue-400 transition-colors"
                aria-label={t("common.userMenu")}
              >
                {(username || "U").charAt(0).toUpperCase()}
              </button>
              {menuOpen && (
                <div className="absolute right-0 mt-2 w-36 rounded-lg border border-[#1e2030] bg-[#141620] py-1 shadow-lg">
                  <Link
                    href="/dashboard"
                    className="block px-4 py-2 text-sm text-[#94a3b8] hover:text-[#e2e8f0] hover:bg-[#1a1d2e]"
                    onClick={() => setMenuOpen(false)}
                  >
                    {t("common.console")}
                  </Link>
                  <Link
                    href="/api-keys"
                    className="block px-4 py-2 text-sm text-[#94a3b8] hover:text-[#e2e8f0] hover:bg-[#1a1d2e]"
                    onClick={() => setMenuOpen(false)}
                  >
                    {t("nav.apiKeys")}
                  </Link>
                  <Link
                    href="/recharge"
                    className="block px-4 py-2 text-sm text-[#94a3b8] hover:text-[#e2e8f0] hover:bg-[#1a1d2e]"
                    onClick={() => setMenuOpen(false)}
                  >
                    {t("nav.recharge")}
                  </Link>
                  <hr className="my-1 border-[#1e2030]" />
                  <button
                    onClick={handleSignOut}
                    className="block w-full text-left px-4 py-2 text-sm text-red-400 hover:bg-red-500/10"
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
                className="text-sm text-[#94a3b8] hover:text-[#e2e8f0] transition-colors"
              >
                {t("common.signIn")}
              </Link>
              <Link
                href="/register"
                className="inline-flex items-center rounded-lg bg-[#3b82f6] px-4 py-1.5 text-sm font-medium text-white hover:bg-blue-400 transition-colors"
              >
                {t("common.signUp")}
              </Link>
            </>
          )}
        </div>

        {/* Mobile toggle */}
        <button
          className="md:hidden flex items-center justify-center rounded-md p-2 text-[#94a3b8] hover:bg-[#1a1d2e]"
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
        <div className="md:hidden border-t border-[#1e2030] bg-[#0a0a10] px-4 py-3 space-y-2">
          {navLinks.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              className="block text-sm text-[#94a3b8] py-1.5"
              onClick={() => setMenuOpen(false)}
            >
              {link.label}
            </Link>
          ))}
          {isLoggedIn ? (
            <>
              <hr className="border-[#1e2030]" />
              <Link href="/dashboard" className="block text-sm font-medium text-[#e2e8f0] py-1.5" onClick={() => setMenuOpen(false)}>
                {t("common.console")}
              </Link>
              <Link href="/api-keys" className="block text-sm text-[#94a3b8] py-1.5" onClick={() => setMenuOpen(false)}>
                {t("nav.apiKeys")}
              </Link>
              <button onClick={handleSignOut} className="block text-sm text-red-400 py-1.5">
                {t("common.signOut")}
              </button>
            </>
          ) : (
            <>
              <hr className="border-[#1e2030]" />
              <Link href="/login" className="block text-sm text-[#94a3b8] py-1.5" onClick={() => setMenuOpen(false)}>
                {t("common.signIn")}
              </Link>
              <Link
                href="/register"
                className="inline-flex items-center rounded-lg bg-[#3b82f6] px-4 py-1.5 text-sm font-medium text-white"
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
