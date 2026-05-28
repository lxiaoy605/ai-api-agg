"use client";

import { useTranslations, useLocale } from "next-intl";
import { Link, usePathname, useRouter } from "@/i18n/navigation";
import {
  LayoutDashboard,
  Key,
  Box,
  BookOpen,
  BarChart3,
  Settings,
  ChevronLeft,
  ChevronRight,
  Zap,
  Wallet,
  Globe,
} from "lucide-react";

const navItems = [
  { href: "/dashboard", key: "dashboard", icon: LayoutDashboard },
  { href: "/api-keys", key: "apiKeys", icon: Key },
  { href: "/models", key: "models", icon: Box },
  { href: "/docs", key: "docs", icon: BookOpen },
  { href: "/usage", key: "usage", icon: BarChart3 },
  { href: "/recharge", key: "recharge", icon: Wallet },
];

const languages = [
  { code: "en", label: "English" },
  { code: "ru", label: "Русский" },
  { code: "tr", label: "Türkçe" },
] as const;

interface SidebarProps {
  collapsed: boolean;
  onToggle: () => void;
}

export default function Sidebar({ collapsed, onToggle }: SidebarProps) {
  const t = useTranslations("nav");
  const pathname = usePathname();
  const router = useRouter();
  const locale = useLocale();

  const handleLocaleChange = (newLocale: string) => {
    // 获取当前路径，替换 locale 前缀
    const pathWithoutLocale = pathname === "/" ? "/" : pathname;
    router.replace(pathWithoutLocale, { locale: newLocale });
  };

  return (
    <aside
      className={`fixed left-0 top-0 z-40 h-screen bg-slate-950 border-r border-slate-800 transition-all duration-200 flex flex-col ${
        collapsed ? "w-16" : "w-60"
      }`}
    >
      {/* Logo */}
      <div className="flex items-center h-14 px-4 border-b border-slate-800 shrink-0">
        <Link href="/" className="flex items-center gap-2 overflow-hidden">
          <Zap className="h-6 w-6 text-emerald-500 shrink-0" />
          {!collapsed && (
            <span className="text-lg font-bold text-white whitespace-nowrap">
              {t("brand")}
            </span>
          )}
        </Link>
      </div>

      {/* 导航链接 */}
      <nav className="flex-1 px-2 py-4 space-y-1 overflow-y-auto">
        {navItems.map((item) => {
          const Icon = item.icon;
          const isActive = pathname === item.href;
          return (
            <Link
              key={item.href}
              href={item.href}
              className={`flex items-center gap-3 px-3 py-2.5 rounded-lg transition-colors text-sm ${
                isActive
                  ? "bg-emerald-500/10 text-emerald-400 border border-emerald-500/20"
                  : "text-slate-400 hover:text-slate-200 hover:bg-slate-800/50"
              }`}
            >
              <Icon className="h-5 w-5 shrink-0" />
              {!collapsed && <span className="whitespace-nowrap">{t(item.key)}</span>}
            </Link>
          );
        })}
      </nav>

      {/* 语言切换器 */}
      {!collapsed ? (
        <div className="px-3 py-2 border-t border-slate-800">
          <div className="flex items-center gap-2 text-xs text-slate-500 mb-1.5">
            <Globe className="h-3.5 w-3.5" />
            <span>Language</span>
          </div>
          <div className="flex gap-1">
            {languages.map((lang) => (
              <button
                key={lang.code}
                onClick={() => handleLocaleChange(lang.code)}
                className={`flex-1 py-1.5 text-xs rounded-md transition-colors ${
                  locale === lang.code
                    ? "bg-emerald-500/10 text-emerald-400 border border-emerald-500/20"
                    : "text-slate-400 hover:text-slate-200 hover:bg-slate-800/50"
                }`}
              >
                {lang.code.toUpperCase()}
              </button>
            ))}
          </div>
        </div>
      ) : (
        <div className="p-2 border-t border-slate-800 flex justify-center">
          <button
            onClick={() => {
              const currentIdx = languages.findIndex((l) => l.code === locale);
              const next = languages[(currentIdx + 1) % languages.length];
              handleLocaleChange(next.code);
            }}
            className="p-2 rounded-lg text-slate-400 hover:text-slate-200 hover:bg-slate-800/50 transition-colors"
            title={`Language: ${locale.toUpperCase()}`}
          >
            <Globe className="h-4 w-4" />
          </button>
        </div>
      )}

      {/* 折叠按钮 */}
      <div className="p-2 border-t border-slate-800">
        <button
          onClick={onToggle}
          className="w-full flex items-center justify-center p-2 rounded-lg text-slate-500 hover:text-slate-300 hover:bg-slate-800/50 transition-colors"
        >
          {collapsed ? (
            <ChevronRight className="h-4 w-4" />
          ) : (
            <>
              <ChevronLeft className="h-4 w-4" />
              <span className="ml-2 text-xs">{t("collapse")}</span>
            </>
          )}
        </button>
      </div>
    </aside>
  );
}
