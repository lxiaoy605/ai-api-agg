"use client";

import { Sun, Moon } from "lucide-react";
import { useTheme } from "@/components/theme/ThemeProvider";

export default function ThemeSwitcher() {
  const { theme, toggleTheme } = useTheme();

  return (
    <button
      onClick={toggleTheme}
      className="flex h-8 w-8 items-center justify-center rounded-md text-[var(--muted-text)] hover:text-[var(--body-text)] hover:bg-[var(--surface-raised)] transition-colors"
      aria-label={theme === "dark" ? "Switch to light mode" : "Switch to dark mode"}
      title={theme === "dark" ? "Switch to light mode" : "Switch to dark mode"}
    >
      {theme === "dark" ? <Sun className="h-4 w-4" /> : <Moon className="h-4 w-4" />}
    </button>
  );
}
