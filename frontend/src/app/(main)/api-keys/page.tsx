"use client";

import { useState, useEffect, useCallback } from "react";
import { useTranslations } from "next-intl";
import Link from "next/link";
import {
  Key,
  Plus,
  Copy,
  Trash2,
  Check,
  AlertTriangle,
} from "lucide-react";
import { apiGet, apiPost, apiDelete, ApiError } from "@/services/api";
import { Spinner } from "@/components/ui/Loading";

/** API Key 类型 — 匹配后端 /api-keys 响应 */
export interface ApiKey {
  id: string;
  name: string;
  prefix: string;
  fullKey?: string; // 仅在创建时返回
  key?: string; // 后端 json:"key"
  status: "active" | "disabled";
  created_at?: number; // 后端 json:"created_at"
  createdAt?: string; // 格式化后展示
  lastUsed: string;
  last_used_at?: number; // 后端 json:"last_used_at"
  requestCount: number;
  tokenUsage: number;
}

export default function ApiKeysPage() {
  const t = useTranslations("apiKeys");
  const ts = useTranslations("status");
  const tc = useTranslations("common");
  const [keys, setKeys] = useState<ApiKey[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [showCreateDialog, setShowCreateDialog] = useState(false);
  const [newKeyName, setNewKeyName] = useState("");
  const [creating, setCreating] = useState(false);
  const [newKey, setNewKey] = useState<ApiKey | null>(null);
  const [copied, setCopied] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<ApiKey | null>(null);
  const [deleting, setDeleting] = useState(false);

  const loadKeys = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const data = await apiGet<ApiKey[]>("/api-keys");
      setKeys(data || []);
    } catch (err) {
      const msg =
        err instanceof ApiError ? err.message : "Failed to load API keys";
      setError(msg);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadKeys();
  }, [loadKeys]);

  const handleCreate = async () => {
    if (!newKeyName.trim()) return;
    try {
      setCreating(true);
      setError(null);
      const key = await apiPost<ApiKey>("/api-keys", {
        name: newKeyName.trim(),
      });
      setNewKey(key);
      setKeys((prev) => [key, ...prev]);
      setNewKeyName("");
    } catch (err) {
      const msg =
        err instanceof ApiError ? err.message : "Failed to create API key";
      setError(msg);
    } finally {
      setCreating(false);
    }
  };

  const handleCopy = (text: string) => {
    navigator.clipboard.writeText(text);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const handleDelete = async (id: string) => {
    try {
      setDeleting(true);
      setError(null);
      await apiDelete(`/api-keys/${id}`);
      setKeys((prev) => prev.filter((k) => k.id !== id));
      setDeleteTarget(null);
    } catch (err) {
      const msg =
        err instanceof ApiError ? err.message : "Failed to delete API key";
      setError(msg);
    } finally {
      setDeleting(false);
    }
  };

  const handleToggleStatus = (id: string) => {
    // 后端暂无 PATCH/PUT 端点，仅在前端切换显示状态
    setKeys((prev) =>
      prev.map((k) =>
        k.id === id
          ? {
              ...k,
              status:
                k.status === "active"
                  ? ("disabled" as const)
                  : ("active" as const),
            }
          : k
      )
    );
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-[var(--body-text)]">{t("title")}</h1>
          <p className="text-[var(--muted-text)] text-sm mt-1">{t("subtitle")}</p>
        </div>
        <button
          onClick={() => {
            setNewKey(null);
            setError(null);
            setShowCreateDialog(true);
          }}
          className="flex items-center gap-2 px-4 py-2 bg-brand-600 hover:bg-brand-700 text-white rounded-lg text-sm font-medium transition-colors"
        >
          <Plus className="h-4 w-4" />
          {t("create")}
        </button>
      </div>

      {/* 错误提示 */}
      {error && (
        <div className="flex items-center gap-2 p-3 rounded-lg bg-red-500/10 border border-red-500/20 text-sm text-red-400">
          <AlertTriangle className="h-4 w-4 shrink-0" />
          {error}
        </div>
      )}

      {/* 加载态 */}
      {loading && (
        <div className="flex items-center justify-center py-20">
          <Spinner className="h-8 w-8 text-brand-600" />
        </div>
      )}

      {/* Key 列表 */}
      {!loading && (
        <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-[var(--border-color)] bg-[var(--card-bg)]/50 text-left">
                  <th className="py-3 px-5 text-[var(--muted-text)] font-medium">{t("tableName")}</th>
                  <th className="py-3 px-5 text-[var(--muted-text)] font-medium">{t("tableKey")}</th>
                  <th className="py-3 px-5 text-[var(--muted-text)] font-medium">{t("tableCreated")}</th>
                  <th className="py-3 px-5 text-[var(--muted-text)] font-medium">{t("tableStatus")}</th>
                  <th className="py-3 px-5 text-[var(--muted-text)] font-medium">{t("tableLastUsed")}</th>
                  <th className="py-3 px-5 text-[var(--muted-text)] font-medium">{t("tableActions")}</th>
                </tr>
              </thead>
              <tbody>
                {keys.map((key) => (
                  <tr
                    key={key.id}
                    className="border-b border-[var(--border-color)]/50 hover:bg-[var(--surface-raised)]/30 transition-colors"
                  >
                    <td className="py-3 px-5 text-[var(--body-text)] font-medium">
                      {key.name}
                    </td>
                    <td className="py-3 px-5">
                      <code className="text-[var(--muted-text)] bg-[var(--surface-raised)] px-2 py-0.5 rounded text-xs font-mono">
                        {key.prefix}
                      </code>
                    </td>
                    <td className="py-3 px-5 text-[var(--muted-text)]">
                      {key.created_at
                        ? new Date(key.created_at * 1000).toLocaleDateString("en-US")
                        : key.createdAt || "-"}
                    </td>
                    <td className="py-3 px-5">
                      <button
                        onClick={() => handleToggleStatus(key.id)}
                        className={`text-xs font-medium px-2 py-0.5 rounded-full transition-colors ${
                          key.status === "active"
                            ? "bg-brand-500/10 text-brand-300 hover:bg-brand-500/20"
                            : "bg-[var(--surface-raised)] text-[var(--muted-text)]"
                        }`}
                      >
                        {ts(key.status === "active" ? "active" : "disabled")}
                      </button>
                    </td>
                    <td className="py-3 px-5 text-[var(--muted-text)]">
                      {key.last_used_at
                        ? new Date(key.last_used_at * 1000).toLocaleString("en-US")
                        : key.lastUsed || "-"}
                    </td>
                    <td className="py-3 px-5">
                      <div className="flex items-center gap-2">
                        <button
                          onClick={() =>
                            handleCopy(
                              key.fullKey || `sk-xxx-${key.id}`
                            )
                          }
                          className="p-1.5 rounded-lg text-[var(--muted-text)] hover:text-[var(--body-text)] hover:bg-[var(--surface-raised)] transition-colors"
                          title={t("copyKey")}
                        >
                          <Copy className="h-4 w-4" />
                        </button>
                        <button
                          onClick={() => setDeleteTarget(key)}
                          className="p-1.5 rounded-lg text-[var(--muted-text)] hover:text-error hover:bg-red-500/10 transition-colors"
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
                    <td colSpan={6}>
                      <div className="flex flex-col items-center justify-center py-16 text-center">
                        <div className="w-14 h-14 mb-4 rounded-full bg-[var(--surface-raised)] flex items-center justify-center">
                          <Key className="h-7 w-7 text-[var(--muted-text)]" />
                        </div>
                        <h3 className="text-base font-semibold text-[var(--body-text)] mb-1">
                          {t("emptyTitle")}
                        </h3>
                        <p className="text-sm text-[var(--muted-text)] mb-6">
                          {t("emptyDesc")}
                        </p>
                        <button
                          onClick={() => {
                            setNewKey(null);
                            setError(null);
                            setShowCreateDialog(true);
                          }}
                          className="flex items-center gap-2 px-4 py-2 bg-brand-600 hover:bg-brand-700 text-white rounded-lg text-sm font-medium transition-colors"
                        >
                          <Plus className="h-4 w-4" />
                          {t("create")}
                        </button>
                      </div>
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* 创建 Key 弹窗 */}
      {showCreateDialog && (
        <div className="fixed inset-0 z-50 flex items-center justify-center">
          <div
            className="absolute inset-0 bg-black/60 backdrop-blur-sm"
            onClick={() => setShowCreateDialog(false)}
          />
          <div className="relative bg-[var(--card-bg)] border border-[var(--border-color)] rounded-xl p-6 w-full max-w-md mx-4 shadow-2xl">
            {!newKey ? (
              <>
                <h3 className="text-lg font-semibold text-[var(--body-text)] mb-4">
                  {t("createTitle")}
                </h3>
                <label className="block text-sm text-[var(--muted-text)] mb-2">
                  {t("createNameLabel")}
                </label>
                <input
                  type="text"
                  value={newKeyName}
                  onChange={(e) => setNewKeyName(e.target.value)}
                  placeholder={t("createNamePlaceholder")}
                  className="w-full px-3 py-2 bg-[var(--surface-raised)] border border-[var(--border-color)] rounded-lg text-[var(--body-text)] text-sm placeholder-[var(--muted-text)] focus:outline-none focus:border-brand-500 transition-colors"
                  autoFocus
                  onKeyDown={(e) => e.key === "Enter" && handleCreate()}
                />
                <div className="flex justify-end gap-3 mt-6">
                  <button
                    onClick={() => setShowCreateDialog(false)}
                    className="px-4 py-2 text-sm text-[var(--muted-text)] hover:text-[var(--body-text)] transition-colors"
                  >
                    {tc("cancel")}
                  </button>
                  <button
                    onClick={handleCreate}
                    disabled={!newKeyName.trim() || creating}
                    className="px-4 py-2 bg-brand-600 hover:bg-brand-700 disabled:bg-neutral-600 disabled:text-neutral-400 text-white rounded-lg text-sm font-medium transition-colors"
                  >
                    {creating ? <Spinner className="h-4 w-4" /> : t("create")}
                  </button>
                </div>
              </>
            ) : (
              <>
                <div className="flex items-center gap-3 mb-4">
                  <div className="w-10 h-10 rounded-full bg-brand-500/10 flex items-center justify-center">
                    <Check className="h-5 w-5 text-brand-300" />
                  </div>
                  <div>
                    <h3 className="text-lg font-semibold text-[var(--body-text)]">
                      {t("createSuccess")}
                    </h3>
                    <p className="text-sm text-[var(--muted-text)]">{newKey.name}</p>
                  </div>
                </div>

                <div className="bg-red-500/10 border border-red-500/20 rounded-lg p-3 mb-4 flex items-start gap-2">
                  <AlertTriangle className="h-4 w-4 text-red-400 shrink-0 mt-0.5" />
                  <p className="text-xs text-red-300">{t("createWarning")}</p>
                </div>

                <div className="flex items-center gap-2 bg-[var(--surface-raised)] rounded-lg p-3">
                  <code className="flex-1 text-sm text-[var(--body-text)] font-mono break-all">
                    {newKey.fullKey || newKey.key}
                  </code>
                  <button
                    onClick={() => handleCopy(newKey.fullKey || newKey.key || "")}
                    className="shrink-0 p-2 rounded-lg bg-[var(--surface-raised)] hover:bg-[var(--border-color)] text-[var(--body-text)] transition-colors"
                  >
                    {copied ? (
                      <Check className="h-4 w-4 text-brand-300" />
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
                  className="w-full mt-4 px-4 py-2 bg-[var(--surface-raised)] hover:bg-[var(--border-color)] text-[var(--body-text)] rounded-lg text-sm font-medium transition-colors"
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
            onClick={() => !deleting && setDeleteTarget(null)}
          />
          <div className="relative bg-[var(--card-bg)] border border-[var(--border-color)] rounded-xl p-6 w-full max-w-sm mx-4 shadow-2xl">
            <div className="flex items-center gap-3 mb-4">
              <div className="w-10 h-10 rounded-full bg-red-500/10 flex items-center justify-center">
                <AlertTriangle className="h-5 w-5 text-red-400" />
              </div>
              <h3 className="text-lg font-semibold text-[var(--body-text)]">{t("deleteTitle")}</h3>
            </div>
            <p className="text-sm text-[var(--muted-text)] mb-1">
              Delete key &apos;{deleteTarget.name}&apos;? This action cannot be undone.
            </p>
            <div className="flex justify-end gap-3 mt-6">
              <button
                onClick={() => setDeleteTarget(null)}
                disabled={deleting}
                className="px-4 py-2 text-sm text-[var(--muted-text)] hover:text-[var(--body-text)] transition-colors disabled:opacity-50"
              >
                {tc("cancel")}
              </button>
              <button
                onClick={() => handleDelete(deleteTarget.id)}
                disabled={deleting}
                className="px-4 py-2 bg-red-600 hover:bg-red-500 text-[var(--body-text)] rounded-lg text-sm font-medium transition-colors disabled:opacity-50"
              >
                {deleting ? <Spinner className="h-4 w-4" /> : t("delete")}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
