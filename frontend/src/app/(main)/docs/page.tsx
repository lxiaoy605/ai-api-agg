"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";
import { errorCodes } from "@/data/models";
import {
  Copy,
  Check,
  Terminal,
  BookOpen,
  AlertTriangle,
  ArrowRight,
  Server,
  Key,
} from "lucide-react";
import Link from "next/link";

const langTabs = [
  { key: "curl", label: "cURL" },
  { key: "python", label: "Python" },
  { key: "nodejs", label: "Node.js" },
] as const;

const quickStartCode: Record<string, string> = {
  curl: `# Set your API Key
export API_KEY="sk-your-api-key-here"

# Send a chat request
curl https://api.example.com/v1/chat/completions \\
  -H "Content-Type: application/json" \\
  -H "Authorization: Bearer $API_KEY" \\
  -d '{
    "model": "deepseek-v4-flash",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant"},
      {"role": "user", "content": "Hello, please introduce yourself"}
    ],
    "temperature": 0.7,
    "max_tokens": 500
  }'`,
  python: `# Install OpenAI SDK
# pip install openai

import openai

client = openai.OpenAI(
    base_url="https://api.example.com/v1",
    api_key="sk-your-api-key-here"
)

response = client.chat.completions.create(
    model="deepseek-v4-flash",
    messages=[
        {"role": "system", "content": "You are a helpful assistant"},
        {"role": "user", "content": "Hello, please introduce yourself"}
    ],
    temperature=0.7,
    max_tokens=500
)

print(response.choices[0].message.content)`,
  nodejs: `// Install OpenAI SDK
// npm install openai

import OpenAI from "openai";

const client = new OpenAI({
  baseURL: "https://api.example.com/v1",
  apiKey: "sk-your-api-key-here",
});

const response = await client.chat.completions.create({
  model: "deepseek-v4-flash",
  messages: [
    { role: "system", content: "You are a helpful assistant" },
    { role: "user", content: "Hello, please introduce yourself" },
  ],
  temperature: 0.7,
  max_tokens: 500,
});

console.log(response.choices[0].message.content);`,
};

const endpoints = [
  { method: "POST", path: "/v1/chat/completions", descKey: "chat" },
  { method: "POST", path: "/v1/embeddings", descKey: "embeddings" },
  { method: "GET", path: "/v1/models", descKey: "models" },
  { method: "GET", path: "/v1/usage", descKey: "usage" },
];

const modelIds = [
  "deepseek-v4-flash",
  "deepseek-v4-pro",
  "glm-4_5",
  "glm-4_5-air",
  "glm-4_6",
  "glm-4_7",
  "glm-5",
  "glm-5-turbo",
  "glm-5_1",
  "mimo-v2-flash",
  "mimo-v2-omni",
  "mimo-v2-pro",
  "mimo-v2_5",
  "mimo-v2_5-pro",
];

export default function DocsPage() {
  const td = useTranslations("docs");
  const tc = useTranslations("common");
  const [lang, setLang] = useState<string>("curl");
  const [copied, setCopied] = useState(false);

  const handleCopy = (text: string) => {
    navigator.clipboard.writeText(text);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold text-[var(--body-text)]">{td("title")}</h1>
        <p className="text-[var(--muted-text)] text-sm mt-1">{td("subtitle")}</p>
      </div>

      {/* 快速开始 */}
      <section className="space-y-4">
        <div className="flex items-center gap-2">
          <Terminal className="h-5 w-5 text-brand-600" />
          <h2 className="text-lg font-semibold text-[var(--body-text)]">{td("quickStart")}</h2>
        </div>
        <p className="text-sm text-[var(--muted-text)]">{td("quickStartDesc")}</p>

        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <Link href="/api-keys" className="cursor-pointer bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-5 hover:border-brand-500/30 hover:bg-[var(--surface-raised)] transition-colors">
            <div className="w-8 h-8 rounded-full bg-brand-500/10 flex items-center justify-center mb-3">
              <Key className="h-4 w-4 text-brand-300" />
            </div>
            <h3 className="text-sm font-medium text-[var(--body-text)] mb-1">
              {td("step1Title")}
            </h3>
            <p className="text-xs text-[var(--muted-text)]">{td("step1Desc")}</p>
          </Link>
          <a href="#quick-start-code" className="cursor-pointer bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-5 hover:border-brand-500/30 hover:bg-[var(--surface-raised)] transition-colors">
            <div className="w-8 h-8 rounded-full bg-brand-500/10 flex items-center justify-center mb-3">
              <Server className="h-4 w-4 text-brand-300" />
            </div>
            <h3 className="text-sm font-medium text-[var(--body-text)] mb-1">
              {td("step2Title")}
            </h3>
            <p className="text-xs text-[var(--muted-text)]">
              {td("step2Desc")}{" "}
              <code className="text-brand-300 bg-[var(--surface-raised)] px-1 rounded">
                https://api.example.com/v1
              </code>
            </p>
          </a>
          <Link href="/models" className="cursor-pointer bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-5 hover:border-brand-500/30 hover:bg-[var(--surface-raised)] transition-colors">
            <div className="w-8 h-8 rounded-full bg-brand-500/10 flex items-center justify-center mb-3">
              <ArrowRight className="h-4 w-4 text-brand-300" />
            </div>
            <h3 className="text-sm font-medium text-[var(--body-text)] mb-1">
              {td("step3Title")}
            </h3>
            <p className="text-xs text-[var(--muted-text)]">{td("step3Desc")}</p>
          </Link>
        </div>

        <div id="quick-start-code" className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] overflow-hidden">
          <div className="flex items-center justify-between px-5 py-3 border-b border-[var(--border-color)]">
            <div className="flex rounded-lg bg-[var(--surface-raised)] p-0.5">
              {langTabs.map((tab) => (
                <button
                  key={tab.key}
                  onClick={() => setLang(tab.key)}
                  className={`px-3 py-1.5 text-xs rounded-md transition-colors ${
                    lang === tab.key
                      ? "bg-brand-600 text-white"
                      : "text-[var(--muted-text)] hover:text-[var(--body-text)]"
                  }`}
                >
                  {tab.label}
                </button>
              ))}
            </div>
            <button
              onClick={() => handleCopy(quickStartCode[lang])}
              className="flex items-center gap-1 text-xs text-[var(--muted-text)] hover:text-[var(--body-text)] transition-colors"
            >
              {copied ? (
                <>
                  <Check className="h-3.5 w-3.5 text-brand-300" />
                  <span className="text-brand-300">{tc("copied")}</span>
                </>
              ) : (
                <>
                  <Copy className="h-3.5 w-3.5" />
                  <span>{tc("copy")}</span>
                </>
              )}
            </button>
          </div>
          <pre className="p-5 text-xs text-[var(--body-text)] overflow-x-auto font-mono leading-relaxed bg-[var(--page-bg)]/50">
            {quickStartCode[lang]}
          </pre>
        </div>
      </section>

      {/* API 参考 */}
      <section className="space-y-4">
        <div className="flex items-center gap-2">
          <BookOpen className="h-5 w-5 text-brand-600" />
          <h2 className="text-lg font-semibold text-[var(--body-text)]">{td("apiReference")}</h2>
        </div>
        <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-[var(--border-color)] text-left">
                  <th className="py-3 px-5 text-[var(--muted-text)] font-medium">{td("tableMethod")}</th>
                  <th className="py-3 px-5 text-[var(--muted-text)] font-medium">{td("tableEndpoint")}</th>
                  <th className="py-3 px-5 text-[var(--muted-text)] font-medium">{td("tableDescription")}</th>
                </tr>
              </thead>
              <tbody>
                {endpoints.map((ep) => (
                  <tr
                    key={ep.path}
                    className="border-b border-[var(--border-color)]/50 hover:bg-[var(--surface-raised)]/30 transition-colors"
                  >
                    <td className="py-3 px-5">
                      <span className="text-xs font-mono px-2 py-0.5 rounded bg-brand-500/10 text-brand-300">
                        {ep.method}
                      </span>
                    </td>
                    <td className="py-3 px-5">
                      <code className="text-[var(--body-text)] font-mono text-xs">
                        {ep.path}
                      </code>
                    </td>
                    <td className="py-3 px-5 text-[var(--muted-text)]">
                      {td(`endpoints.${ep.descKey}`)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </section>

      {/* 错误码说明 */}
      <section className="space-y-4">
        <div className="flex items-center gap-2">
          <AlertTriangle className="h-5 w-5 text-brand-600" />
          <h2 className="text-lg font-semibold text-[var(--body-text)]">{td("errorCodes")}</h2>
        </div>
        <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-[var(--border-color)] text-left">
                  <th className="py-3 px-5 text-[var(--muted-text)] font-medium">{td("tableStatusCode")}</th>
                  <th className="py-3 px-5 text-[var(--muted-text)] font-medium">Error</th>
                  <th className="py-3 px-5 text-[var(--muted-text)] font-medium">{td("tableDescription")}</th>
                </tr>
              </thead>
              <tbody>
                {(errorCodes as {code:number;message:string;description:string}[]).map((err) => {
                  const code = err.code;
                  return (
                  <tr
                    key={code}
                    className="border-b border-[var(--border-color)]/50 hover:bg-[var(--surface-raised)]/30 transition-colors"
                  >
                    <td className="py-3 px-5">
                      <span
                        className={`text-xs font-mono px-2 py-0.5 rounded ${
                          code < 400
                            ? "bg-brand-500/10 text-brand-300"
                            : code < 500
                            ? "bg-yellow-500/10 text-yellow-400"
                            : "bg-red-500/10 text-red-400"
                        }`}
                      >
                        {code}
                      </span>
                    </td>
                    <td className="py-3 px-5 text-[var(--body-text)] font-medium">
                      {td(`errorMessages.${code}`)}
                    </td>
                    <td className="py-3 px-5 text-[var(--muted-text)]">
                      {td(`errorDescriptions.${code}`)}
                    </td>
                  </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      </section>

      {/* 模型命名规范 */}
      <section className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-6 space-y-3">
        <h3 className="text-sm font-semibold text-[var(--body-text)]">{td("modelNaming")}</h3>
        <p className="text-sm text-[var(--muted-text)]">
          {td("modelNamingDesc")}
        </p>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 text-xs">
          {modelIds.map((id) => {
            // i18n 动态 key 无法在编译期提取，直接从 ID 生成显示名
            const nameFromT = td(`modelNamingExamples.${id}`);
            const isMissing = !nameFromT || nameFromT.startsWith("docs.") || nameFromT.startsWith("modelNamingExamples.");
            const name = isMissing
              ? id.split("-").map((w) => w.charAt(0).toUpperCase() + w.slice(1)).join(" ")
              : nameFromT;
            return (
            <div
              key={id}
              className="flex items-center justify-between bg-[var(--surface-raised)]/50 rounded-lg px-3 py-2"
            >
              <code className="text-[var(--body-text)] font-mono">{id}</code>
              <span className="text-[var(--muted-text)]">{name}</span>
            </div>
            );
          })}
        </div>
      </section>
    </div>
  );
}
