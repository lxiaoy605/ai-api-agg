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
          <h1 className="text-2xl font-bold text-[#e2e8f0]">{t("title")}</h1>
          <p className="text-[#94a3b8] text-sm mt-1">{t("subtitle")}</p>
        </div>
        <button
          onClick={() => {
            setNewKey(null);
            setShowCreateDialog(true);
          }}
          className="flex items-center gap-2 px-4 py-2 bg-blue-600 hover:bg-blue-400 text-[#e2e8f0] rounded-lg text-sm font-medium transition-colors"
        >
          <Plus className="h-4 w-4" />
          {t("create")}
        </button>
      </div>

      {/* Key 列表 */}
      <div className="bg-[#141620] rounded-xl border border-[#1e2030] overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-[#1e2030] bg-[#141620]/50 text-left">
                <th className="py-3 px-5 text-[#94a3b8] font-medium">{t("tableName")}</th>
                <th className="py-3 px-5 text-[#94a3b8] font-medium">{t("tableKey")}</th>
                <th className="py-3 px-5 text-[#94a3b8] font-medium">{t("tableCreated")}</th>
                <th className="py-3 px-5 text-[#94a3b8] font-medium">{t("tableStatus")}</th>
                <th className="py-3 px-5 text-[#94a3b8] font-medium">{t("tableLastUsed")}</th>
                <th className="py-3 px-5 text-[#94a3b8] font-medium">{t("tableActions")}</th>
              </tr>
            </thead>
            <tbody>
              {keys.map((key) => (
                <tr
                  key={key.id}
                  className="border-b border-[#1e2030]/50 hover:bg-[#1a1d2e]/30 transition-colors"
                >
                  <td className="py-3 px-5 text-[#e2e8f0] font-medium">
                    {key.name}
                  </td>
                  <td className="py-3 px-5">
                    <code className="text-[#94a3b8] bg-[#1a1d2e] px-2 py-0.5 rounded text-xs font-mono">
                      {key.prefix}
                    </code>
                  </td>
                  <td className="py-3 px-5 text-[#94a3b8]">{key.createdAt}</td>
                  <td className="py-3 px-5">
                    <button
                      onClick={() => handleToggleStatus(key.id)}
                      className={`text-xs font-medium px-2 py-0.5 rounded-full transition-colors ${
                        key.status === "active"
                          ? "bg-blue-500/10 text-blue-400 hover:bg-blue-500/20"
                          : "bg-[#2a2d3e] text-[#94a3b8] hover:bg-[#2a2d3e]"
                      }`}
                    >
                      {ts(key.status === "active" ? "active" : "disabled")}
                    </button>
                  </td>
                  <td className="py-3 px-5 text-[#94a3b8]">{key.lastUsed}</td>
                  <td className="py-3 px-5">
                    <div className="flex items-center gap-2">
                      <button
                        onClick={() => handleCopy(`sk-xxx-${key.id}`)}
                        className="p-1.5 rounded-lg text-[#64748b] hover:text-[#e2e8f0] hover:bg-[#1a1d2e] transition-colors"
                        title={t("copyKey")}
                      >
                        <Copy className="h-4 w-4" />
                      </button>
                      <button
                        onClick={() => setDeleteTarget(key)}
                        className="p-1.5 rounded-lg text-[#64748b] hover:text-red-400 hover:bg-red-500/10 transition-colors"
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
                  <td colSpan={6} className="py-12 text-center text-[#64748b]">
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
              className="bg-[#141620] rounded-xl border border-[#1e2030] p-5"
            >
              <div className="flex items-center gap-2 mb-3">
                <Key className="h-4 w-4 text-blue-500" />
                <span className="text-sm font-medium text-[#e2e8f0]">
                  {key.name}
                </span>
              </div>
              <div className="space-y-2">
                <div className="flex justify-between text-xs">
                  <span className="text-[#64748b]">
                    <BarChart3 className="inline h-3 w-3 mr-1" />
                    {t("usageRequests")}
                  </span>
                  <span className="text-[#e2e8f0]">
                    {key.requestCount.toLocaleString()}
                  </span>
                </div>
                <div className="flex justify-between text-xs">
                  <span className="text-[#64748b]">
                    <Activity className="inline h-3 w-3 mr-1" />
                    {t("usageTokens")}
                  </span>
                  <span className="text-[#e2e8f0]">
                    {(key.tokenUsage / 1000).toFixed(0)}K
                  </span>
                </div>
                <div className="flex justify-between text-xs">
                  <span className="text-[#64748b]">
                    <Clock className="inline h-3 w-3 mr-1" />
                    {t("usageLastUsed")}
                  </span>
                  <span className="text-[#e2e8f0]">{key.lastUsed}</span>
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
          <div className="relative bg-[#141620] border border-[#1e2030] rounded-xl p-6 w-full max-w-md mx-4 shadow-2xl">
            {!newKey ? (
              <>
                <h3 className="text-lg font-semibold text-[#e2e8f0] mb-4">
                  {t("createTitle")}
                </h3>
                <label className="block text-sm text-[#94a3b8] mb-2">
                  {t("createNameLabel")}
                </label>
                <input
                  type="text"
                  value={newKeyName}
                  onChange={(e) => setNewKeyName(e.target.value)}
                  placeholder={t("createNamePlaceholder")}
                  className="w-full px-3 py-2 bg-[#1a1d2e] border border-[#2a2d3e] rounded-lg text-[#e2e8f0] text-sm placeholder-[#64748b] focus:outline-none focus:border-blue-500 transition-colors"
                  autoFocus
                  onKeyDown={(e) => e.key === "Enter" && handleCreate()}
                />
                <div className="flex justify-end gap-3 mt-6">
                  <button
                    onClick={() => setShowCreateDialog(false)}
                    className="px-4 py-2 text-sm text-[#94a3b8] hover:text-[#e2e8f0] transition-colors"
                  >
                    {tc("cancel")}
                  </button>
                  <button
                    onClick={handleCreate}
                    disabled={!newKeyName.trim()}
                    className="px-4 py-2 bg-blue-600 hover:bg-blue-400 disabled:bg-[#2a2d3e] disabled:text-[#64748b] text-[#e2e8f0] rounded-lg text-sm font-medium transition-colors"
                  >
                    {t("create")}
                  </button>
                </div>
              </>
            ) : (
              <>
                <div className="flex items-center gap-3 mb-4">
                  <div className="w-10 h-10 rounded-full bg-blue-500/10 flex items-center justify-center">
                    <Check className="h-5 w-5 text-blue-400" />
                  </div>
                  <div>
                    <h3 className="text-lg font-semibold text-[#e2e8f0]">
                      {t("createSuccess")}
                    </h3>
                    <p className="text-sm text-[#94a3b8]">{newKey.name}</p>
                  </div>
                </div>

                <div className="bg-red-500/10 border border-red-500/20 rounded-lg p-3 mb-4 flex items-start gap-2">
                  <AlertTriangle className="h-4 w-4 text-red-400 shrink-0 mt-0.5" />
                  <p className="text-xs text-red-300">{t("createWarning")}</p>
                </div>

                <div className="flex items-center gap-2 bg-[#1a1d2e] rounded-lg p-3">
                  <code className="flex-1 text-sm text-[#e2e8f0] font-mono break-all">
                    {newKey.fullKey}
                  </code>
                  <button
                    onClick={() => handleCopy(newKey.fullKey!)}
                    className="shrink-0 p-2 rounded-lg bg-[#2a2d3e] hover:bg-[#2a2d3e] text-[#e2e8f0] transition-colors"
                  >
                    {copied ? (
                      <Check className="h-4 w-4 text-blue-400" />
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
                  className="w-full mt-4 px-4 py-2 bg-[#1a1d2e] hover:bg-[#2a2d3e] text-[#e2e8f0] rounded-lg text-sm font-medium transition-colors"
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
          <div className="relative bg-[#141620] border border-[#1e2030] rounded-xl p-6 w-full max-w-sm mx-4 shadow-2xl">
            <div className="flex items-center gap-3 mb-4">
              <div className="w-10 h-10 rounded-full bg-red-500/10 flex items-center justify-center">
                <AlertTriangle className="h-5 w-5 text-red-400" />
              </div>
              <h3 className="text-lg font-semibold text-[#e2e8f0]">{t("deleteTitle")}</h3>
            </div>
            <p className="text-sm text-[#94a3b8] mb-2">
              {t("deleteConfirm", { name: deleteTarget.name })}
            </p>
            <p className="text-xs text-red-400 mb-6">{t("deleteWarning")}</p>
            <div className="flex justify-end gap-3">
              <button
                onClick={() => setDeleteTarget(null)}
                className="px-4 py-2 text-sm text-[#94a3b8] hover:text-[#e2e8f0] transition-colors"
              >
                {tc("cancel")}
              </button>
              <button
                onClick={() => handleDelete(deleteTarget.id)}
                className="px-4 py-2 bg-red-600 hover:bg-red-500 text-[#e2e8f0] rounded-lg text-sm font-medium transition-colors"
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
