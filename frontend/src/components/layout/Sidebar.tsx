"use client";

import { useTranslations } from "next-intl";
import { usePathname } from "next/navigation";
import Link from "next/link";
import {
  LayoutDashboard,
  Key,
  Zap,
  BookOpen,
  Wallet,
  ChevronLeft,
  ChevronRight,
} from "lucide-react";

const navItems = [
  { href: "/dashboard", key: "dashboard", icon: LayoutDashboard },
  { href: "/api-keys", key: "apiKeys", icon: Key },
  { href: "/models", key: "models", icon: Zap },
  { href: "/docs", key: "docs", icon: BookOpen },
  { href: "/recharge", key: "recharge", icon: Wallet },
];

interface SidebarProps {
  collapsed: boolean;
  onToggle: () => void;
}

export default function Sidebar({ collapsed, onToggle }: SidebarProps) {
  const t = useTranslations("nav");
  const pathname = usePathname();

  return (
    <aside
      className={`fixed left-0 top-14 z-40 h-[calc(100vh-3.5rem)] bg-[var(--page-bg)] border-r border-[var(--border-color)] transition-all duration-200 flex flex-col ${
        collapsed ? "w-16" : "w-60"
      }`}
    >
      {/* 导航链接 */}
      <nav className="flex-1 px-2 py-4 space-y-1 overflow-y-auto min-h-0">
        {navItems.map((item) => {
          const Icon = item.icon;
          const isActive = pathname === item.href;
          return (
            <Link
              key={item.href}
              href={item.href}
              className={`flex items-center gap-3 px-3 py-2.5 rounded-lg transition-colors text-sm ${
                isActive
                  ? "bg-brand-500/10 text-brand-300 border border-brand-500/20"
                  : "text-[var(--muted-text)] hover:text-[var(--body-text)] hover:bg-[var(--surface-raised)]/50"
              }`}
            >
              <Icon className="h-5 w-5 shrink-0" />
              {!collapsed && <span className="whitespace-nowrap">{t(item.key)}</span>}
            </Link>
          );
        })}
      </nav>

      {/* 折叠按钮 */}
      <div className="p-2 border-t border-[var(--border-color)]">
        <button
          onClick={onToggle}
          className="w-full flex items-center justify-center p-2 rounded-lg text-[var(--muted-text)] hover:text-[var(--body-text)] hover:bg-[var(--surface-raised)]/50 transition-colors"
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
