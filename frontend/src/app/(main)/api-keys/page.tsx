"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";
import {
  Key,
  Plus,
  Copy,
  Trash2,
  Clock,
  Activity,
  BarChart3,
  Check,
  AlertTriangle,
} from "lucide-react";
import { mockApiKeys, generateNewKey, ApiKey } from "@/data/api-keys";

export default function ApiKeysPage() {
  const t = useTranslations("apiKeys");
  const ts = useTranslations("status");
  const tc = useTranslations("common");
  const [keys, setKeys] = useState<ApiKey[]>(mockApiKeys);
  const [showCreateDialog, setShowCreateDialog] = useState(false);
  const [newKeyName, setNewKeyName] = useState("");
  const [newKey, setNewKey] = useState<ApiKey | null>(null);
  const [copied, setCopied] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<ApiKey | null>(null);

  const handleCreate = () => {
    if (!newKeyName.trim()) return;
    const key = generateNewKey(newKeyName.trim());
    setNewKey(key);
    setKeys((prev) => [key, ...prev]);
    setNewKeyName("");
  };

  const handleCopy = (text: string) => {
    navigator.clipboard.writeText(text);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const handleDelete = (id: string) => {
    setKeys((prev) => prev.filter((k) => k.id !== id));
    setDeleteTarget(null);
  };

  const handleToggleStatus = (id: string) => {
    setKeys((prev) =>
      prev.map((k) =>
        k.id === id
          ? {
              ...k,
              status: k.status === "active" ? ("disabled" as const) : ("active" as const),
            }
          : k
      )
    );
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white">{t("title")}</h1>
          <p className="text-slate-400 text-sm mt-1">{t("subtitle")}</p>
        </div>
        <button
          onClick={() => {
            setNewKey(null);
            setShowCreateDialog(true);
          }}
          className="flex items-center gap-2 px-4 py-2 bg-emerald-600 hover:bg-emerald-500 text-white rounded-lg text-sm font-medium transition-colors"
        >
          <Plus className="h-4 w-4" />
          {t("create")}
        </button>
      </div>

      {/* Key 列表 */}
      <div className="bg-slate-900 rounded-xl border border-slate-800 overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-slate-800 bg-slate-900/50 text-left">
                <th className="py-3 px-5 text-slate-400 font-medium">{t("tableName")}</th>
                <th className="py-3 px-5 text-slate-400 font-medium">{t("tableKey")}</th>
                <th className="py-3 px-5 text-slate-400 font-medium">{t("tableCreated")}</th>
                <th className="py-3 px-5 text-slate-400 font-medium">{t("tableStatus")}</th>
                <th className="py-3 px-5 text-slate-400 font-medium">{t("tableLastUsed")}</th>
                <th className="py-3 px-5 text-slate-400 font-medium">{t("tableActions")}</th>
              </tr>
            </thead>
            <tbody>
              {keys.map((key) => (
                <tr
                  key={key.id}
                  className="border-b border-slate-800/50 hover:bg-slate-800/30 transition-colors"
                >
                  <td className="py-3 px-5 text-slate-200 font-medium">
                    {key.name}
                  </td>
                  <td className="py-3 px-5">
                    <code className="text-slate-400 bg-slate-800 px-2 py-0.5 rounded text-xs font-mono">
                      {key.prefix}
                    </code>
                  </td>
                  <td className="py-3 px-5 text-slate-400">{key.createdAt}</td>
                  <td className="py-3 px-5">
                    <button
                      onClick={() => handleToggleStatus(key.id)}
                      className={`text-xs font-medium px-2 py-0.5 rounded-full transition-colors ${
                        key.status === "active"
                          ? "bg-emerald-500/10 text-emerald-400 hover:bg-emerald-500/20"
                          : "bg-slate-700 text-slate-400 hover:bg-slate-600"
                      }`}
                    >
                      {ts(key.status === "active" ? "active" : "disabled")}
                    </button>
                  </td>
                  <td className="py-3 px-5 text-slate-400">{key.lastUsed}</td>
                  <td className="py-3 px-5">
                    <div className="flex items-center gap-2">
                      <button
                        onClick={() => handleCopy(`sk-xxx-${key.id}`)}
                        className="p-1.5 rounded-lg text-slate-500 hover:text-slate-300 hover:bg-slate-800 transition-colors"
                        title={t("copyKey")}
                      >
                        <Copy className="h-4 w-4" />
                      </button>
                      <button
                        onClick={() => setDeleteTarget(key)}
                        className="p-1.5 rounded-lg text-slate-500 hover:text-red-400 hover:bg-red-500/10 transition-colors"
                        title={t("deleteKey")}
                      >
                        <Trash2 className="h-4 w-4" />
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
              {keys.length === 0 && (
                <tr>
                  <td colSpan={6} className="py-12 text-center text-slate-500">
                    {t("empty")}
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* 用量概览卡片 */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        {keys
          .filter((k) => k.status === "active")
          .slice(0, 4)
          .map((key) => (
            <div
              key={key.id}
              className="bg-slate-900 rounded-xl border border-slate-800 p-5"
            >
              <div className="flex items-center gap-2 mb-3">
                <Key className="h-4 w-4 text-emerald-500" />
                <span className="text-sm font-medium text-slate-200">
                  {key.name}
                </span>
              </div>
              <div className="space-y-2">
                <div className="flex justify-between text-xs">
                  <span className="text-slate-500">
                    <BarChart3 className="inline h-3 w-3 mr-1" />
                    {t("usageRequests")}
                  </span>
                  <span className="text-slate-300">
                    {key.requestCount.toLocaleString()}
                  </span>
                </div>
                <div className="flex justify-between text-xs">
                  <span className="text-slate-500">
                    <Activity className="inline h-3 w-3 mr-1" />
                    {t("usageTokens")}
                  </span>
                  <span className="text-slate-300">
                    {(key.tokenUsage / 1000).toFixed(0)}K
                  </span>
                </div>
                <div className="flex justify-between text-xs">
                  <span className="text-slate-500">
                    <Clock className="inline h-3 w-3 mr-1" />
                    {t("usageLastUsed")}
                  </span>
                  <span className="text-slate-300">{key.lastUsed}</span>
                </div>
              </div>
            </div>
          ))}
      </div>

      {/* 创建 Key 弹窗 */}
      {showCreateDialog && (
        <div className="fixed inset-0 z-50 flex items-center justify-center">
          <div
            className="absolute inset-0 bg-black/60 backdrop-blur-sm"
            onClick={() => setShowCreateDialog(false)}
          />
          <div className="relative bg-slate-900 border border-slate-800 rounded-xl p-6 w-full max-w-md mx-4 shadow-2xl">
            {!newKey ? (
              <>
                <h3 className="text-lg font-semibold text-white mb-4">
                  {t("createTitle")}
                </h3>
                <label className="block text-sm text-slate-400 mb-2">
                  {t("createNameLabel")}
                </label>
                <input
                  type="text"
                  value={newKeyName}
                  onChange={(e) => setNewKeyName(e.target.value)}
                  placeholder={t("createNamePlaceholder")}
                  className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-slate-200 text-sm placeholder-slate-500 focus:outline-none focus:border-emerald-500 transition-colors"
                  autoFocus
                  onKeyDown={(e) => e.key === "Enter" && handleCreate()}
                />
                <div className="flex justify-end gap-3 mt-6">
                  <button
                    onClick={() => setShowCreateDialog(false)}
                    className="px-4 py-2 text-sm text-slate-400 hover:text-slate-200 transition-colors"
                  >
                    {tc("cancel")}
                  </button>
                  <button
                    onClick={handleCreate}
                    disabled={!newKeyName.trim()}
                    className="px-4 py-2 bg-emerald-600 hover:bg-emerald-500 disabled:bg-slate-700 disabled:text-slate-500 text-white rounded-lg text-sm font-medium transition-colors"
                  >
                    {t("create")}
                  </button>
                </div>
              </>
            ) : (
              <>
                <div className="flex items-center gap-3 mb-4">
                  <div className="w-10 h-10 rounded-full bg-emerald-500/10 flex items-center justify-center">
                    <Check className="h-5 w-5 text-emerald-400" />
                  </div>
                  <div>
                    <h3 className="text-lg font-semibold text-white">
                      {t("createSuccess")}
                    </h3>
                    <p className="text-sm text-slate-400">{newKey.name}</p>
                  </div>
                </div>

                <div className="bg-red-500/10 border border-red-500/20 rounded-lg p-3 mb-4 flex items-start gap-2">
                  <AlertTriangle className="h-4 w-4 text-red-400 shrink-0 mt-0.5" />
                  <p className="text-xs text-red-300">{t("createWarning")}</p>
                </div>

                <div className="flex items-center gap-2 bg-slate-800 rounded-lg p-3">
                  <code className="flex-1 text-sm text-slate-200 font-mono break-all">
                    {newKey.fullKey}
                  </code>
                  <button
                    onClick={() => handleCopy(newKey.fullKey!)}
                    className="shrink-0 p-2 rounded-lg bg-slate-700 hover:bg-slate-600 text-slate-300 transition-colors"
                  >
                    {copied ? (
                      <Check className="h-4 w-4 text-emerald-400" />
                    ) : (
                      <Copy className="h-4 w-4" />
                    )}
                  </button>
                </div>

                <button
                  onClick={() => {
                    setShowCreateDialog(false);
                    setNewKey(null);
                  }}
                  className="w-full mt-4 px-4 py-2 bg-slate-800 hover:bg-slate-700 text-slate-300 rounded-lg text-sm font-medium transition-colors"
                >
                  {t("createSaved")}
                </button>
              </>
            )}
          </div>
        </div>
      )}

      {/* 删除确认弹窗 */}
      {deleteTarget && (
        <div className="fixed inset-0 z-50 flex items-center justify-center">
          <div
            className="absolute inset-0 bg-black/60 backdrop-blur-sm"
            onClick={() => setDeleteTarget(null)}
          />
          <div className="relative bg-slate-900 border border-slate-800 rounded-xl p-6 w-full max-w-sm mx-4 shadow-2xl">
            <div className="flex items-center gap-3 mb-4">
              <div className="w-10 h-10 rounded-full bg-red-500/10 flex items-center justify-center">
                <AlertTriangle className="h-5 w-5 text-red-400" />
              </div>
              <h3 className="text-lg font-semibold text-white">{t("deleteTitle")}</h3>
            </div>
            <p className="text-sm text-slate-400 mb-2">
              {t("deleteConfirm", { name: deleteTarget.name })}
            </p>
            <p className="text-xs text-red-400 mb-6">{t("deleteWarning")}</p>
            <div className="flex justify-end gap-3">
              <button
                onClick={() => setDeleteTarget(null)}
                className="px-4 py-2 text-sm text-slate-400 hover:text-slate-200 transition-colors"
              >
                {tc("cancel")}
              </button>
              <button
                onClick={() => handleDelete(deleteTarget.id)}
                className="px-4 py-2 bg-red-600 hover:bg-red-500 text-white rounded-lg text-sm font-medium transition-colors"
              >
                {t("delete")}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
