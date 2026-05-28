import { defineRouting } from "next-intl/routing";

export const routing = defineRouting({
  locales: ["en", "ru", "tr"],
  defaultLocale: "en",
  localePrefix: "never",
});
