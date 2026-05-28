import { useTranslations } from "next-intl";

export default function Home() {
  const t = useTranslations("home");

  return (
    <main className="flex min-h-screen flex-col items-center justify-center p-8">
      <div className="max-w-2xl text-center space-y-6">
        <h1 className="text-4xl font-bold tracking-tight sm:text-5xl">
          {t("title")}
        </h1>
        <p className="text-lg text-gray-600 leading-relaxed">
          {t("subtitle")}
        </p>
        <div className="flex flex-wrap justify-center gap-3 pt-4">
          <span className="rounded-full bg-blue-100 px-4 py-1.5 text-sm font-medium text-blue-700">
            DeepSeek
          </span>
          <span className="rounded-full bg-green-100 px-4 py-1.5 text-sm font-medium text-green-700">
            Zhipu Z.ai
          </span>
          <span className="rounded-full bg-purple-100 px-4 py-1.5 text-sm font-medium text-purple-700">
            Xiaomi MiMo
          </span>
          <span className="rounded-full bg-orange-100 px-4 py-1.5 text-sm font-medium text-orange-700">
            {t("moreProviders")}
          </span>
        </div>
        <p className="text-sm text-gray-400 pt-4">
          {t("comingSoon")}
        </p>
      </div>
    </main>
  );
}
