import type { Metadata } from "next";
import { NextIntlClientProvider } from "next-intl";
import { getLocale, getMessages } from "next-intl/server";
import { ThemeProvider } from "@/components/theme/ThemeProvider";
import { AuthProvider } from "@/context/AuthContext";
import TopNav from "@/components/layout/TopNav";
import "./globals.css";

export const metadata: Metadata = {
  title: "AiFlowHub — Chinese AI Models, One Simple API",
  description:
    "Access DeepSeek, GLM, Qwen, MiniMax and more through a unified OpenAI-compatible endpoint.",
};

export default async function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const locale = await getLocale();
  const messages = await getMessages();

  return (
    <html lang={locale} suppressHydrationWarning>
      <head>
        {/* 阻止主题闪烁：在首帧渲染前同步读取 localStorage 设置 theme class */}
        <script
          dangerouslySetInnerHTML={{
            __html: `(function(){var t=localStorage.getItem('aiflowhub-theme')||'light';document.documentElement.className=t;document.documentElement.setAttribute('data-theme',t)})()`,
          }}
        />
        <link rel="icon" type="image/svg+xml" href="/favicon.svg" />
      </head>
      <body className="min-h-screen bg-[var(--page-bg)] text-[var(--body-text)] antialiased">
        <ThemeProvider>
          <NextIntlClientProvider messages={messages}>
            <AuthProvider>
              <TopNav />
              <div className="pt-14">
                {children}
              </div>
            </AuthProvider>
          </NextIntlClientProvider>
        </ThemeProvider>
      </body>
    </html>
  );
}
