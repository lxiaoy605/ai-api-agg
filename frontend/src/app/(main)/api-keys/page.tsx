"use client";

import { useState, useEffect, useCallback, Fragment } from "react";
import { useTranslations } from "next-intl";
import { Key, Plus, Copy, Trash2, Check, AlertTriangle, ChevronRight, ChevronDown, Folder, Pencil } from "lucide-react";
import { apiGet, apiPost, apiPatch, apiPut, apiDelete, ApiError } from "@/services/api";
import { Spinner } from "@/components/ui/Loading";

/** API Key 类型 */
export interface ApiKey {
  id: string;
  name: string;
  prefix: string;
  key_prefix?: string;
  fullKey?: string;
  key?: string;
  status: "active" | "disabled";
  workgroup_id?: number | null;
  workgroup_name?: string;
  created_at?: number;
  createdAt?: string;
  lastUsed: string;
  last_used_at?: number;
  requestCount: number;
  tokenUsage: number;
}

interface WorkgroupOption {
  id: number;
  name: string;
  description?: string;
}

const LS_LAST_WG = "aiflowhub_last_workgroup";

export default function ApiKeysPage() {
  const t = useTranslations("apiKeys");
  const ts = useTranslations("status");
  const tc = useTranslations("common");
  const td = useTranslations("dashboard");
  const [keys, setKeys] = useState<ApiKey[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // ── 创建 Key ──
  const [showCreateDialog, setShowCreateDialog] = useState(false);
  const [newKeyName, setNewKeyName] = useState("");
  const [newKeyWg, setNewKeyWg] = useState<number | null>(null);
  const [wgDropdownOpen, setWgDropdownOpen] = useState(false);
  const [creating, setCreating] = useState(false);
  const [newKey, setNewKey] = useState<ApiKey | null>(null);
  const [copied, setCopied] = useState(false);

  // ── 工作组创建 ──
  const [showWgDialog, setShowWgDialog] = useState(false);
  const [wgName, setWgName] = useState("");
  const [wgDesc, setWgDesc] = useState("");
  const [wgCreating, setWgCreating] = useState(false);

  // ── 工作组编辑 ──
  const [showEditWg, setShowEditWg] = useState(false);
  const [editWgId, setEditWgId] = useState<number | null>(null);
  const [editWgName, setEditWgName] = useState("");
  const [editWgDesc, setEditWgDesc] = useState("");
  const [editWgSaving, setEditWgSaving] = useState(false);

  // ── 工作组列表（供下拉使用）──
  const [workgroups, setWorkgroups] = useState<WorkgroupOption[]>([]);

  // ── 删除 ──
  const [deleteTarget, setDeleteTarget] = useState<ApiKey | null>(null);
  const [deleting, setDeleting] = useState(false);

  // ── 树形展开 ──
  const [expanded, setExpanded] = useState<Set<string>>(new Set());

  const loadKeys = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const [keyData, wgData] = await Promise.all([
        apiGet<ApiKey[]>("/api-keys"),
        apiGet<WorkgroupOption[]>("/workgroups").catch(() => [] as WorkgroupOption[]),
      ]);
      setKeys(keyData || []);
      setWorkgroups(wgData || []);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Failed to load API keys");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadKeys();
  }, [loadKeys]);

  // 展开逻辑：单组默认展开，多组查缓存
  useEffect(() => {
    if (workgroups.length === 0) return;
    const wgNames = new Set(workgroups.map((w) => w.name));
    // 也包含 keys 中可能有的 workgroup_name（比如已删除工作组但 key 还保留的）
    for (const k of keys) {
      if (k.workgroup_name) wgNames.add(k.workgroup_name);
    }
    const list = Array.from(wgNames);

    if (list.length <= 1) {
      setExpanded(new Set(list));
    } else {
      const cached = (() => {
        try { return localStorage.getItem(LS_LAST_WG); } catch { return null; }
      })();
      if (cached && list.includes(cached)) {
        setExpanded(new Set([cached]));
      } else {
        setExpanded(new Set());
      }
    }
  }, [workgroups, keys]);

  const toggleGroup = (name: string) => {
    setExpanded((prev) => {
      const next = new Set(prev);
      if (next.has(name)) {
        next.delete(name);
      } else {
        next.add(name);
        try { localStorage.setItem(LS_LAST_WG, name); } catch {}
      }
      return next;
    });
  };

  // ── 创建 Key ──
  const handleCreate = async () => {
    if (!newKeyName.trim()) return;
    try {
      setCreating(true);
      setError(null);
      const body: Record<string, unknown> = { name: newKeyName.trim() };
      if (newKeyWg) body.workgroup_id = newKeyWg;
      const key = await apiPost<ApiKey>("/api-keys", body);
      setNewKey(key);
      // Refresh full list to get workgroup_name
      const fresh = await apiGet<ApiKey[]>("/api-keys");
      setKeys(fresh || []);
      setNewKeyName("");
      setNewKeyWg(null);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Failed to create API key");
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
      setError(err instanceof ApiError ? err.message : "Failed to delete API key");
    } finally {
      setDeleting(false);
    }
  };

  const handleToggleStatus = async (id: string) => {
    try {
      const res = await apiPatch<{ id: string; status: string }>(`/api-keys/${id}/toggle`);
      setKeys((prev) =>
        prev.map((k) => (k.id === id ? { ...k, status: res.status as "active" | "disabled" } : k))
      );
    } catch {
      // silent fail
    }
  };

  const handleCreateWorkgroup = async () => {
    if (!wgName.trim()) {
      setError("Group name is required");
      return;
    }
    try {
      setWgCreating(true);
      setError(null);
      await apiPost("/workgroups", { name: wgName.trim(), description: wgDesc.trim() });
      setShowWgDialog(false);
      setWgName("");
      setWgDesc("");
      await loadKeys();
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Failed to create workgroup");
    } finally {
      setWgCreating(false);
    }
  };

  const handleEditWorkgroup = async () => {
    if (!editWgId || !editWgName.trim()) return;
    try {
      setEditWgSaving(true);
      setError(null);
      await apiPut(`/workgroups/${editWgId}`, { name: editWgName.trim(), description: editWgDesc.trim() });
      setShowEditWg(false);
      await loadKeys();
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Failed to update workgroup");
    } finally {
      setEditWgSaving(false);
    }
  };

  // ── 按工作组分组 ──
  const grouped = (() => {
    const wgDesc = new Map(workgroups.map((w) => [w.name, w.description || ""]));
    const map = new Map<string, ApiKey[]>();
    const seen = new Set<string>();
    for (const wg of workgroups) {
      map.set(wg.name, []);
      seen.add(wg.name);
    }
    for (const k of keys) {
      const wn = k.workgroup_name || "Default";
      if (!map.has(wn)) map.set(wn, []);
      map.get(wn)!.push(k);
    }
    const result: [string, string, ApiKey[]][] = [];
    for (const wg of workgroups) {
      const list = map.get(wg.name) || [];
      if (list.length > 0 || workgroups.length <= 1) {
        result.push([wg.name, wgDesc.get(wg.name) || "", list]);
      }
    }
    for (const [name, list] of map) {
      if (!seen.has(name) && list.length > 0) {
        result.push([name, "", list]);
      }
    }
    return result;
  })();

  // ── Key 行（共用）──
  const renderKeyRow = (key: ApiKey) => (
    <tr
      key={key.id}
      className="border-b border-[var(--border-color)]/40 hover:bg-[var(--surface-raised)]/30 transition-colors"
    >
      <td className="py-2.5 pl-8 pr-3 text-[var(--body-text)] font-medium text-sm">
        {key.name}
      </td>
      <td className="py-2.5 px-3">
        <code className="text-[var(--muted-text)] bg-[var(--surface-raised)] px-2 py-0.5 rounded text-xs font-mono">
          {key["key_prefix"] || "—"}
        </code>
      </td>
      <td className="py-2.5 px-3 text-[var(--muted-text)] text-xs">
        {key.created_at
          ? new Date(key.created_at * 1000).toLocaleDateString("en-US")
          : key.createdAt || "-"}
      </td>
      <td className="py-2.5 px-3">
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
      <td className="py-2.5 px-3 text-[var(--muted-text)] text-xs">
        {key.last_used_at
          ? new Date(key.last_used_at * 1000).toLocaleString("en-US")
          : key.lastUsed || "-"}
      </td>
      <td className="py-2.5 px-3">
        <button
          onClick={() => setDeleteTarget(key)}
          className="p-1.5 rounded-lg text-[var(--muted-text)] hover:text-error hover:bg-red-500/10 transition-colors"
          title={t("deleteKey")}
        >
          <Trash2 className="h-4 w-4" />
        </button>
      </td>
    </tr>
  );

  return (
    <div className="space-y-6">
      {/* ── 标题行 ── */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-[var(--body-text)]">{t("title")}</h1>
          <p className="text-[var(--muted-text)] text-sm mt-1">{t("subtitle")}</p>
        </div>
        <div className="flex items-center gap-3">
          <button
            onClick={() => { setError(null); setShowWgDialog(true); }}
            className="flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition-colors border border-[var(--border-color)] text-[var(--body-text)] hover:bg-[var(--surface-raised)]"
          >
            <Plus className="h-4 w-4" />
            {t("createWorkgroup")}
          </button>
          <button
            onClick={() => {
              setNewKey(null);
              setNewKeyWg(null);
              setWgDropdownOpen(false);
              setError(null);
              setShowCreateDialog(true);
            }}
            className="flex items-center gap-2 px-4 py-2 bg-brand-600 hover:bg-brand-700 text-white rounded-lg text-sm font-medium transition-colors"
          >
            <Plus className="h-4 w-4" />
            {t("create")}
          </button>
        </div>
      </div>

      {/* ── 错误提示 ── */}
      {error && (
        <div className="flex items-center gap-2 p-3 rounded-lg bg-red-500/10 border border-red-500/20 text-sm text-red-400">
          <AlertTriangle className="h-4 w-4 shrink-0" />
          {error}
        </div>
      )}

      {/* ── 加载态 ── */}
      {loading && (
        <div className="flex items-center justify-center py-20">
          <Spinner className="h-8 w-8 text-brand-600" />
        </div>
      )}

      {/* ── 树形 Key 列表 ── */}
      {!loading && (
        <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] overflow-hidden">
          {keys.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-16 text-center">
              <div className="w-14 h-14 mb-4 rounded-full bg-[var(--surface-raised)] flex items-center justify-center">
                <Key className="h-7 w-7 text-[var(--muted-text)]" />
              </div>
              <h3 className="text-base font-semibold text-[var(--body-text)] mb-1">{t("emptyTitle")}</h3>
              <p className="text-sm text-[var(--muted-text)] mb-6">{t("emptyDesc")}</p>
              <button
                onClick={() => {
                  setNewKey(null);
                  setNewKeyWg(null);
                  setError(null);
                  setShowCreateDialog(true);
                }}
                className="flex items-center gap-2 px-4 py-2 bg-brand-600 hover:bg-brand-700 text-white rounded-lg text-sm font-medium transition-colors"
              >
                <Plus className="h-4 w-4" />
                {t("create")}
              </button>
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-[var(--border-color)] bg-[var(--card-bg)]/50 text-left">
                    <th className="py-3 pl-8 pr-3 text-[var(--muted-text)] font-medium w-[160px]">{t("tableName")}</th>
                    <th className="py-3 px-3 text-[var(--muted-text)] font-medium w-[180px]">{t("tableKey")}</th>
                    <th className="py-3 px-3 text-[var(--muted-text)] font-medium w-[110px]">{t("tableCreated")}</th>
                    <th className="py-3 px-3 text-[var(--muted-text)] font-medium w-[110px]">{t("tableStatus")}</th>
                    <th className="py-3 px-3 text-[var(--muted-text)] font-medium w-[170px]">{t("tableLastUsed")}</th>
                    <th className="py-3 px-3 text-[var(--muted-text)] font-medium w-[60px]">{t("tableActions")}</th>
                  </tr>
                </thead>
                <tbody>
                  {grouped.map(([groupName, groupDesc, groupKeys]) => {
                    const isOpen = expanded.has(groupName);
                    return (
                      <Fragment key={groupName}>
                        {/* 组头行 */}
                        <tr
                          className="border-b border-[var(--border-color)] bg-[var(--surface-raised)]/40 cursor-pointer hover:bg-[var(--surface-raised)]/60 transition-colors"
                          onClick={() => toggleGroup(groupName)}
                        >
                          <td colSpan={6} className="py-2.5 px-5">
                            <div className="flex items-center gap-3">
                              <div className="flex items-center gap-2">
                                {isOpen ? (
                                  <ChevronDown className="h-4 w-4 text-[var(--muted-text)]" />
                                ) : (
                                  <ChevronRight className="h-4 w-4 text-[var(--muted-text)]" />
                                )}
                                <Folder className="h-4 w-4 text-brand-400" />
                                <span className="text-[var(--body-text)] font-medium">{groupName}</span>
                                <span className="text-xs text-[var(--muted-text)]">
                                  ({groupKeys.length} {groupKeys.length === 1 ? "key" : "keys"})
                                </span>
                              </div>
                              {groupDesc && (
                                <>
                                  <span className="text-xs text-[var(--muted-text)] truncate max-w-[50%] hidden sm:inline">
                                    {groupDesc}
                                  </span>
                                  <button
                                    onClick={(e) => {
                                      e.stopPropagation();
                                      const wg = workgroups.find((w) => w.name === groupName);
                                      if (wg) {
                                        setEditWgId(wg.id);
                                        setEditWgName(wg.name);
                                        setEditWgDesc(wg.description || "");
                                        setShowEditWg(true);
                                      }
                                    }}
                                    className="p-1 rounded hover:bg-[var(--border-color)] text-[var(--muted-text)] hover:text-[var(--body-text)] transition-colors shrink-0"
                                    title="Edit workgroup"
                                  >
                                    <Pencil className="h-3.5 w-3.5" />
                                  </button>
                                </>
                              )}
                            </div>
                          </td>
                        </tr>
                        {/* 子行 */}
                        {isOpen && groupKeys.map(renderKeyRow)}
                      </Fragment>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}

      {/* ── 创建 Key 弹窗 ── */}
      {showCreateDialog && (
        <div className="fixed inset-0 z-50 flex items-center justify-center">
          <div
            className="absolute inset-0 bg-black/60 backdrop-blur-sm"
            onClick={() => setShowCreateDialog(false)}
          />
          <div className="relative bg-[var(--card-bg)] border border-[var(--border-color)] rounded-xl p-6 w-full max-w-md mx-4 shadow-2xl">
            {!newKey ? (
              <>
                <h3 className="text-lg font-semibold text-[var(--body-text)] mb-4">{t("createTitle")}</h3>

                {/* 工作组选择 — 自定义下拉，避免原生 select 白闪 */}
                {workgroups.length > 0 && (() => {
                  const filteredWg = workgroups.filter((w) => w.name !== "Default");
                  if (filteredWg.length === 0) return null;
                  const selectedWg = workgroups.find((w) => w.id === newKeyWg);
                  return (
                    <div className="mb-4">
                      <label className="block text-sm text-[var(--muted-text)] mb-1.5">
                        {t("selectWorkgroup")}
                      </label>
                      <div className="relative">
                        <button
                          type="button"
                          onClick={() => setWgDropdownOpen(!wgDropdownOpen)}
                          className="w-full flex items-center justify-between px-3 py-2 bg-[var(--surface-raised)] border border-[var(--border-color)] rounded-lg text-[var(--body-text)] text-sm focus:outline-none focus:border-brand-500 transition-colors"
                        >
                          <span className={selectedWg ? "text-[var(--body-text)]" : "text-[var(--muted-text)]"}>
                            {selectedWg ? selectedWg.name : "Default (auto-assign)"}
                          </span>
                          <ChevronDown className={`h-4 w-4 text-[var(--muted-text)] transition-transform ${wgDropdownOpen ? "rotate-180" : ""}`} />
                        </button>
                        {wgDropdownOpen && (
                          <>
                            <div className="fixed inset-0 z-10" onClick={() => setWgDropdownOpen(false)} />
                            <div className="absolute z-20 top-full mt-1 w-full bg-[var(--card-bg)] border border-[var(--border-color)] rounded-lg shadow-xl overflow-hidden">
                              <button
                                type="button"
                                onClick={() => { setNewKeyWg(null); setWgDropdownOpen(false); }}
                                className={`w-full text-left px-3 py-2 text-sm transition-colors ${!newKeyWg ? "bg-brand-600/20 text-brand-300" : "text-[var(--body-text)] hover:bg-[var(--surface-raised)]"}`}
                              >
                                Default (auto-assign)
                              </button>
                              {filteredWg.map((wg) => (
                                <button
                                  key={wg.id}
                                  type="button"
                                  onClick={() => { setNewKeyWg(wg.id); setWgDropdownOpen(false); }}
                                  className={`w-full text-left px-3 py-2 text-sm transition-colors ${newKeyWg === wg.id ? "bg-brand-600/20 text-brand-300" : "text-[var(--body-text)] hover:bg-[var(--surface-raised)]"}`}
                                >
                                  {wg.name}
                                </button>
                              ))}
                            </div>
                          </>
                        )}
                      </div>
                      <p className="text-xs text-[var(--muted-text)] mt-1">{t("selectWorkgroupDesc")}</p>
                    </div>
                  );
                })()}

                <label className="block text-sm text-[var(--muted-text)] mb-2">{t("createNameLabel")}</label>
                <input
                  type="text" maxLength={30}
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
                    <h3 className="text-lg font-semibold text-[var(--body-text)]">{t("createSuccess")}</h3>
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
                    {copied ? <Check className="h-4 w-4 text-brand-300" /> : <Copy className="h-4 w-4" />}
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

      {/* ── 创建工作组弹窗 ── */}
      {showWgDialog && (
        <div className="fixed inset-0 z-50 flex items-center justify-center">
          <div
            className="absolute inset-0 bg-black/60 backdrop-blur-sm"
            onClick={() => !wgCreating && setShowWgDialog(false)}
          />
          <div className="relative bg-[var(--card-bg)] border border-[var(--border-color)] rounded-xl p-6 w-full max-w-sm mx-4 shadow-2xl">
            <h3 className="text-lg font-semibold text-[var(--body-text)] mb-4">{t("createWorkgroupTitle")}</h3>
            <div className="space-y-3">
              <div>
                <label className="block text-sm font-medium text-[var(--body-text)] mb-1">{t("workgroupName")}</label>
                <input type="text" maxLength={30} value={wgName} onChange={(e) => setWgName(e.target.value)}
                  placeholder={t("workgroupNamePlaceholder")}
                  className="w-full px-3 py-2 bg-[var(--input-bg)] border border-[var(--border-color)] rounded-lg text-sm text-[var(--body-text)] placeholder:text-[var(--muted-text)] focus:outline-none focus:border-brand-500/50" autoFocus />
              </div>
              <div>
                <label className="block text-sm font-medium text-[var(--body-text)] mb-1">{t("workgroupDescription")}</label>
                <textarea value={wgDesc} onChange={(e) => setWgDesc(e.target.value)}
                  placeholder={t("workgroupDescriptionPlaceholder")} rows={2}
                  className="w-full px-3 py-2 bg-[var(--input-bg)] border border-[var(--border-color)] rounded-lg text-sm text-[var(--body-text)] placeholder:text-[var(--muted-text)] focus:outline-none focus:border-brand-500/50 resize-none" />
              </div>
            </div>
            <div className="flex justify-end gap-3 mt-5">
              <button onClick={() => setShowWgDialog(false)} disabled={wgCreating}
                className="px-4 py-2 text-sm text-[var(--muted-text)] hover:text-[var(--body-text)] transition-colors disabled:opacity-50">
                {t("cancel")}
              </button>
              <button onClick={handleCreateWorkgroup} disabled={wgCreating || !wgName.trim()}
                className="px-4 py-2 bg-brand-600 hover:bg-brand-700 text-white rounded-lg text-sm font-medium transition-colors disabled:opacity-50">
                {wgCreating ? <Spinner className="h-4 w-4" /> : t("create")}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ── 编辑工作组弹窗 ── */}
      {showEditWg && (
        <div className="fixed inset-0 z-50 flex items-center justify-center">
          <div
            className="absolute inset-0 bg-black/60 backdrop-blur-sm"
            onClick={() => !editWgSaving && setShowEditWg(false)}
          />
          <div className="relative bg-[var(--card-bg)] border border-[var(--border-color)] rounded-xl p-6 w-full max-w-sm mx-4 shadow-2xl">
            <h3 className="text-lg font-semibold text-[var(--body-text)] mb-4">Edit Workgroup</h3>
            <div className="space-y-3">
              <div>
                <label className="block text-sm font-medium text-[var(--body-text)] mb-1">Name</label>
                <input
                  type="text"
                  maxLength={30}
                  value={editWgName}
                  onChange={(e) => setEditWgName(e.target.value)}
                  className="w-full px-3 py-2 bg-[var(--input-bg)] border border-[var(--border-color)] rounded-lg text-sm text-[var(--body-text)] focus:outline-none focus:border-brand-500/50"
                  autoFocus
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-[var(--body-text)] mb-1">Description</label>
                <textarea
                  value={editWgDesc}
                  onChange={(e) => setEditWgDesc(e.target.value)}
                  rows={2}
                  className="w-full px-3 py-2 bg-[var(--input-bg)] border border-[var(--border-color)] rounded-lg text-sm text-[var(--body-text)] focus:outline-none focus:border-brand-500/50 resize-none"
                />
              </div>
            </div>
            <div className="flex justify-end gap-3 mt-5">
              <button
                onClick={() => setShowEditWg(false)}
                disabled={editWgSaving}
                className="px-4 py-2 text-sm text-[var(--muted-text)] hover:text-[var(--body-text)] transition-colors disabled:opacity-50"
              >
                {t("cancel")}
              </button>
              <button
                onClick={handleEditWorkgroup}
                disabled={editWgSaving || !editWgName.trim()}
                className="px-4 py-2 bg-brand-600 hover:bg-brand-700 text-white rounded-lg text-sm font-medium transition-colors disabled:opacity-50"
              >
                {editWgSaving ? <Spinner className="h-4 w-4" /> : "Save"}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ── 删除确认弹窗 ── */}
      {deleteTarget && (
        <div className="fixed inset-0 z-50 flex items-center justify-center">
          <div className="absolute inset-0 bg-black/60 backdrop-blur-sm" onClick={() => !deleting && setDeleteTarget(null)} />
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
              <button onClick={() => setDeleteTarget(null)} disabled={deleting}
                className="px-4 py-2 text-sm text-[var(--muted-text)] hover:text-[var(--body-text)] transition-colors disabled:opacity-50">
                {tc("cancel")}
              </button>
              <button onClick={() => handleDelete(deleteTarget.id)} disabled={deleting}
                className="px-4 py-2 bg-red-600 hover:bg-red-500 text-[var(--body-text)] rounded-lg text-sm font-medium transition-colors disabled:opacity-50">
                {deleting ? <Spinner className="h-4 w-4" /> : t("delete")}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
