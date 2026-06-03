"use client";

import { useState, useEffect, useCallback } from "react";
import { useTranslations } from "next-intl";
import Link from "next/link";
import { Plus, Pencil, Trash2, FolderOpen, Loader2, Key } from "lucide-react";
import { apiGet, apiPost, apiPut, apiDelete } from "@/lib/api";
import { ApiError } from "@/lib/api";

interface Workgroup {
  id: number;
  user_id: number;
  name: string;
  description: string;
  key_count: number;
  created_at: number;
}

export default function WorkgroupsPage() {
  const t = useTranslations();
  const [workgroups, setWorkgroups] = useState<Workgroup[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Create modal
  const [showCreate, setShowCreate] = useState(false);
  const [creatingName, setCreatingName] = useState("");
  const [creatingDesc, setCreatingDesc] = useState("");
  const [creating, setCreating] = useState(false);
  const [createError, setCreateError] = useState<string | null>(null);

  // Edit modal
  const [editTarget, setEditTarget] = useState<Workgroup | null>(null);
  const [editingName, setEditingName] = useState("");
  const [editingDesc, setEditingDesc] = useState("");
  const [editing, setEditing] = useState(false);
  const [editError, setEditError] = useState<string | null>(null);

  // Delete modal
  const [deleteTarget, setDeleteTarget] = useState<Workgroup | null>(null);
  const [deleting, setDeleting] = useState(false);
  const [deleteError, setDeleteError] = useState<string | null>(null);

  const fetchWorkgroups = useCallback(async () => {
    try {
      setError(null);
      const data = await apiGet<Workgroup[]>("/api/workgroups");
      setWorkgroups(data || []);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Failed to load workgroups");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchWorkgroups();
  }, [fetchWorkgroups]);

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    const name = creatingName.trim();
    if (!name) {
      setCreateError(t("workgroups.nameRequired"));
      return;
    }
    setCreating(true);
    setCreateError(null);
    try {
      await apiPost("/api/workgroups", { name, description: creatingDesc.trim() });
      setShowCreate(false);
      setCreatingName("");
      setCreatingDesc("");
      await fetchWorkgroups();
    } catch (err) {
      setCreateError(err instanceof ApiError ? err.message : t("workgroups.createError"));
    } finally {
      setCreating(false);
    }
  };

  const handleEdit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!editTarget) return;
    const name = editingName.trim();
    if (!name) {
      setEditError(t("workgroups.nameRequired"));
      return;
    }
    setEditing(true);
    setEditError(null);
    try {
      await apiPut(`/api/workgroups/${editTarget.id}`, { name, description: editingDesc.trim() });
      setEditTarget(null);
      await fetchWorkgroups();
    } catch (err) {
      setEditError(err instanceof ApiError ? err.message : t("workgroups.editError"));
    } finally {
      setEditing(false);
    }
  };

  const handleDelete = async () => {
    if (!deleteTarget) return;
    setDeleting(true);
    setDeleteError(null);
    try {
      await apiDelete(`/api/workgroups/${deleteTarget.id}`);
      setDeleteTarget(null);
      await fetchWorkgroups();
    } catch (err) {
      setDeleteError(err instanceof ApiError ? err.message : t("workgroups.deleteError"));
    } finally {
      setDeleting(false);
    }
  };

  const openEdit = (wg: Workgroup) => {
    setEditTarget(wg);
    setEditingName(wg.name);
    setEditingDesc(wg.description || "");
    setEditError(null);
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <Loader2 className="h-6 w-6 animate-spin text-[var(--muted-text)]" />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-[var(--body-text)]">{t("workgroups.title")}</h1>
          <p className="mt-1 text-sm text-[var(--muted-text)]">{t("workgroups.subtitle")}</p>
        </div>
        <button
          onClick={() => { setShowCreate(true); setCreateError(null); }}
          className="inline-flex items-center gap-2 px-4 py-2.5 rounded-lg bg-brand-600 hover:bg-brand-700 text-white text-sm font-medium transition-colors"
        >
          <Plus className="h-4 w-4" />
          {t("workgroups.create")}
        </button>
      </div>

      {/* Error */}
      {error && (
        <div className="p-4 rounded-lg bg-red-500/10 border border-red-500/20 text-sm text-red-400">
          {error}
        </div>
      )}

      {/* Empty state */}
      {!loading && workgroups.length === 0 && (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <FolderOpen className="h-12 w-12 text-[var(--muted-text)] mb-4" />
          <h3 className="text-lg font-medium text-[var(--body-text)] mb-1">{t("workgroups.emptyTitle")}</h3>
          <p className="text-sm text-[var(--muted-text)] mb-6 max-w-sm">{t("workgroups.emptyDesc")}</p>
          <button
            onClick={() => setShowCreate(true)}
            className="inline-flex items-center gap-2 px-4 py-2.5 rounded-lg bg-brand-600 hover:bg-brand-700 text-white text-sm font-medium transition-colors"
          >
            <Plus className="h-4 w-4" />
            {t("workgroups.create")}
          </button>
        </div>
      )}

      {/* Workgroup cards */}
      {workgroups.length > 0 && (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {workgroups.map((wg) => (
            <div
              key={wg.id}
              className="rounded-xl border border-[var(--border-color)] bg-[var(--card-bg)] p-5 hover:border-brand-500/30 transition-colors"
            >
              <div className="flex items-start justify-between mb-3">
                <div className="flex-1 min-w-0">
                  <h3 className="font-semibold text-[var(--body-text)] truncate">{wg.name}</h3>
                  <p className="text-xs text-[var(--muted-text)] mt-0.5">
                    {wg.description || t("workgroups.noDescription")}
                  </p>
                </div>
                {wg.name !== "Default" && (
                  <div className="flex items-center gap-1 shrink-0 ml-2">
                    <button
                      onClick={() => openEdit(wg)}
                      className="p-1.5 rounded-lg text-[var(--muted-text)] hover:text-[var(--body-text)] hover:bg-[var(--surface-raised)] transition-colors"
                      title={t("common.edit")}
                    >
                      <Pencil className="h-3.5 w-3.5" />
                    </button>
                    <button
                      onClick={() => { setDeleteTarget(wg); setDeleteError(null); }}
                      className="p-1.5 rounded-lg text-[var(--muted-text)] hover:text-red-400 hover:bg-red-500/10 transition-colors"
                      title={t("common.delete")}
                    >
                      <Trash2 className="h-3.5 w-3.5" />
                    </button>
                  </div>
                )}
              </div>

              <div className="flex items-center gap-2 text-sm text-[var(--muted-text)]">
                <Key className="h-4 w-4" />
                <span>{t("workgroups.keyCount", { count: wg.key_count })}</span>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Create Modal */}
      {showCreate && (
        <div className="fixed inset-0 z-50 flex items-center justify-center">
          <div className="absolute inset-0 bg-black/60" onClick={() => setShowCreate(false)} />
          <div className="relative bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] w-full max-w-md mx-4 p-6 shadow-2xl">
            <h2 className="text-lg font-semibold text-[var(--body-text)] mb-4">{t("workgroups.createTitle")}</h2>
            <form onSubmit={handleCreate} className="space-y-4">
              {createError && (
                <div className="p-3 rounded-lg bg-red-500/10 border border-red-500/20 text-sm text-red-400">{createError}</div>
              )}
              <div>
                <label className="block text-sm font-medium text-[var(--muted-text)] mb-1.5">
                  {t("workgroups.nameLabel")}
                </label>
                <input
                  type="text" maxLength={64}
                  value={creatingName}
                  onChange={(e) => setCreatingName(e.target.value)}
                  placeholder={t("workgroups.namePlaceholder")}
                  autoFocus
                  disabled={creating}
                  className="w-full px-3 py-2.5 bg-[var(--surface-raised)] border border-[var(--border-color)] rounded-lg text-[var(--body-text)] text-sm focus:outline-none focus:ring-1 focus:border-brand-500/50 focus:ring-brand-500/20 disabled:opacity-50"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-[var(--muted-text)] mb-1.5">
                  {t("workgroups.descriptionLabel")}
                </label>
                <input
                  type="text" maxLength={256}
                  value={creatingDesc}
                  onChange={(e) => setCreatingDesc(e.target.value)}
                  placeholder={t("workgroups.descriptionPlaceholder")}
                  disabled={creating}
                  className="w-full px-3 py-2.5 bg-[var(--surface-raised)] border border-[var(--border-color)] rounded-lg text-[var(--body-text)] text-sm focus:outline-none focus:ring-1 focus:border-brand-500/50 focus:ring-brand-500/20 disabled:opacity-50"
                />
              </div>
              <div className="flex items-center justify-end gap-3 pt-2">
                <button
                  type="button"
                  onClick={() => setShowCreate(false)}
                  disabled={creating}
                  className="px-4 py-2 text-sm text-[var(--muted-text)] hover:text-[var(--body-text)] transition-colors disabled:opacity-50"
                >
                  {t("common.cancel")}
                </button>
                <button
                  type="submit"
                  disabled={creating}
                  className="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-brand-600 hover:bg-brand-700 disabled:bg-neutral-600 text-white text-sm font-medium transition-colors"
                >
                  {creating && <Loader2 className="h-4 w-4 animate-spin" />}
                  {t("common.create")}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Edit Modal */}
      {editTarget && (
        <div className="fixed inset-0 z-50 flex items-center justify-center">
          <div className="absolute inset-0 bg-black/60" onClick={() => setEditTarget(null)} />
          <div className="relative bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] w-full max-w-md mx-4 p-6 shadow-2xl">
            <h2 className="text-lg font-semibold text-[var(--body-text)] mb-4">{t("workgroups.editTitle")}</h2>
            <form onSubmit={handleEdit} className="space-y-4">
              {editError && (
                <div className="p-3 rounded-lg bg-red-500/10 border border-red-500/20 text-sm text-red-400">{editError}</div>
              )}
              <div>
                <label className="block text-sm font-medium text-[var(--muted-text)] mb-1.5">
                  {t("workgroups.nameLabel")}
                </label>
                <input
                  type="text" maxLength={64}
                  value={editingName}
                  onChange={(e) => setEditingName(e.target.value)}
                  placeholder={t("workgroups.namePlaceholder")}
                  autoFocus
                  disabled={editing}
                  className="w-full px-3 py-2.5 bg-[var(--surface-raised)] border border-[var(--border-color)] rounded-lg text-[var(--body-text)] text-sm focus:outline-none focus:ring-1 focus:border-brand-500/50 focus:ring-brand-500/20 disabled:opacity-50"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-[var(--muted-text)] mb-1.5">
                  {t("workgroups.descriptionLabel")}
                </label>
                <input
                  type="text" maxLength={256}
                  value={editingDesc}
                  onChange={(e) => setEditingDesc(e.target.value)}
                  placeholder={t("workgroups.descriptionPlaceholder")}
                  disabled={editing}
                  className="w-full px-3 py-2.5 bg-[var(--surface-raised)] border border-[var(--border-color)] rounded-lg text-[var(--body-text)] text-sm focus:outline-none focus:ring-1 focus:border-brand-500/50 focus:ring-brand-500/20 disabled:opacity-50"
                />
              </div>
              <div className="flex items-center justify-end gap-3 pt-2">
                <button
                  type="button"
                  onClick={() => setEditTarget(null)}
                  disabled={editing}
                  className="px-4 py-2 text-sm text-[var(--muted-text)] hover:text-[var(--body-text)] transition-colors disabled:opacity-50"
                >
                  {t("common.cancel")}
                </button>
                <button
                  type="submit"
                  disabled={editing}
                  className="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-brand-600 hover:bg-brand-700 disabled:bg-neutral-600 text-white text-sm font-medium transition-colors"
                >
                  {editing && <Loader2 className="h-4 w-4 animate-spin" />}
                  {t("common.save")}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Delete Modal */}
      {deleteTarget && (
        <div className="fixed inset-0 z-50 flex items-center justify-center">
          <div className="absolute inset-0 bg-black/60" onClick={() => setDeleteTarget(null)} />
          <div className="relative bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] w-full max-w-md mx-4 p-6 shadow-2xl">
            <div className="flex items-center gap-3 mb-4">
              <div className="p-2 rounded-full bg-red-500/10">
                <Trash2 className="h-5 w-5 text-red-400" />
              </div>
              <h2 className="text-lg font-semibold text-[var(--body-text)]">{t("workgroups.deleteTitle")}</h2>
            </div>
            {deleteError && (
              <div className="p-3 rounded-lg bg-red-500/10 border border-red-500/20 text-sm text-red-400 mb-4">{deleteError}</div>
            )}
            <p className="text-sm text-[var(--muted-text)] mb-1">
              {t("workgroups.deleteConfirm", { name: deleteTarget.name })}
            </p>
            {deleteTarget.key_count > 0 && (
              <p className="text-sm text-amber-400 mb-4">
                {t("workgroups.deleteWarning")}
              </p>
            )}
            <div className="flex items-center justify-end gap-3 pt-4">
              <button
                onClick={() => setDeleteTarget(null)}
                disabled={deleting}
                className="px-4 py-2 text-sm text-[var(--muted-text)] hover:text-[var(--body-text)] transition-colors disabled:opacity-50"
              >
                {t("common.cancel")}
              </button>
              <button
                onClick={handleDelete}
                disabled={deleting}
                className="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-red-600 hover:bg-red-700 disabled:bg-neutral-600 text-white text-sm font-medium transition-colors"
              >
                {deleting && <Loader2 className="h-4 w-4 animate-spin" />}
                {t("common.delete")}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
