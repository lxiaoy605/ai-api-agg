"use client";

import { useLocale } from "next-intl";

const languages = [
  { code: "en", flag: "/flags/gb.svg", label: "English" },
  { code: "ru", flag: "/flags/ru.svg", label: "Русский" },
  { code: "tr", flag: "/flags/tr.svg", label: "Türkçe" },
] as const;

export default function LocaleSwitcher() {
  const locale = useLocale();

  const switchLocale = (newLocale: string) => {
    document.cookie = `NEXT_LOCALE=${newLocale}; path=/; max-age=31536000; SameSite=Lax`;
    window.location.reload();
  };

  return (
    <div className="flex items-center gap-1.5">
      {languages.map((lang) => (
        <button
          key={lang.code}
          onClick={() => switchLocale(lang.code)}
          className={`rounded transition-all ${
            locale === lang.code
              ? "ring-1 ring-brand-500/30 scale-105"
              : "opacity-40 hover:opacity-70 grayscale"
          }`}
          title={lang.label}
        >
          <img
            src={lang.flag}
            alt={lang.label}
            className="h-4 w-auto"
          />
        </button>
      ))}
    </div>
  );
}
