"use client";

import {
  createContext,
  useContext,
  useState,
  useEffect,
  useCallback,
  type ReactNode,
} from "react";

// ── Types ──────────────────────────────────────────────

interface User {
  id: number;
  email: string;
  role: string;
  quota: number;
  created_at: number;
  updated_at: number;
}

interface AuthState {
  user: User | null;
  loading: boolean; // true while initial /auth/me is in flight
  error: string | null;
}

interface AuthActions {
  login(email: string, password: string): Promise<void>;
  register(email: string, password: string): Promise<void>;
  logout(): void;
  refreshUser(): Promise<void>;
}

type AuthContextValue = AuthState & AuthActions;

// ── Constants ──────────────────────────────────────────

const TOKEN_KEY = "ai_api_agg_token";

// 运行时检测：本地 dev → localhost:8082，生产 → 同源（Nginx 代理）
function getApiBase(): string {
  if (typeof window === "undefined") return "http://localhost:8082";
  return window.location.hostname === "localhost"
    ? "http://localhost:8082"
    : window.location.origin;
}

// ── Helpers ────────────────────────────────────────────

function getStoredToken(): string | null {
  if (typeof window === "undefined") return null;
  const stored = localStorage.getItem(TOKEN_KEY);
  if (stored) return stored;
  const match = document.cookie
    .split("; ")
    .find((row) => row.startsWith(TOKEN_KEY + "="));
  return match ? decodeURIComponent(match.slice(TOKEN_KEY.length + 1)) : null;
}

function setStoredToken(token: string) {
  localStorage.setItem(TOKEN_KEY, token);
  // Also set cookie for middleware route guard
  document.cookie = `${TOKEN_KEY}=${encodeURIComponent(token)}; path=/; max-age=86400; SameSite=Lax`;
}

function clearStoredToken() {
  localStorage.removeItem(TOKEN_KEY);
  // Clear cookie
  document.cookie = `${TOKEN_KEY}=; path=/; max-age=0`;
}

async function apiFetch<T>(
  path: string,
  options: RequestInit = {},
): Promise<T> {
  const token = getStoredToken();
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    ...(options.headers as Record<string, string> | undefined),
  };
  if (token) headers["Authorization"] = `Bearer ${token}`;

  const res = await fetch(`${getApiBase()}${path}`, {
    ...options,
    headers,
    signal: AbortSignal.timeout(10_000),
  });

  let body: any;
  try {
    body = await res.json();
  } catch {
    body = {};
  }

  if (!res.ok) {
    // 401 → token expired, trigger logout downstream
    if (res.status === 401) {
      clearStoredToken();
      throw new AuthError(
        body.message ?? body.error ?? "Unauthorized",
        res.status,
      );
    }
    throw new AuthError(
      body.message ?? body.error ?? `Request failed (${res.status})`,
      res.status,
    );
  }

  return (body.data ?? body) as T;
}

// ── Error class ────────────────────────────────────────

export class AuthError extends Error {
  status: number;
  constructor(message: string, status: number) {
    super(message);
    this.name = "AuthError";
    this.status = status;
  }
}

// ── Context ────────────────────────────────────────────

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<AuthState>({
    user: null,
    loading: true,
    error: null,
  });

  // 初始化：有 token 则 fetch /auth/me 验证
  useEffect(() => {
    const token = getStoredToken();
    if (!token) {
      setState({ user: null, loading: false, error: null });
      return;
    }

    let cancelled = false;
    (async () => {
      try {
        const user = await apiFetch<User>("/auth/me");
        if (!cancelled) setState({ user, loading: false, error: null });
      } catch (_err) {
        clearStoredToken();
        if (!cancelled)
          setState({ user: null, loading: false, error: null });
      }
    })();

    return () => {
      cancelled = true;
    };
  }, []);

  // ── Actions ────────────────────────────────────────

  const login = useCallback(async (email: string, password: string) => {
    setState((s) => ({ ...s, loading: true, error: null }));
    try {
      const data = await apiFetch<{ user_id: number; email: string; token: string }>(
        "/auth/login",
        {
          method: "POST",
          body: JSON.stringify({ email, password }),
        },
      );
      setStoredToken(data.token);
      const user = await apiFetch<User>("/auth/me");
      setState({ user, loading: false, error: null });
    } catch (err) {
      setState((s) => ({
        ...s,
        loading: false,
        error: err instanceof AuthError ? err.message : "Network error",
      }));
      throw err;
    }
  }, []);

  const register = useCallback(
    async (email: string, password: string) => {
      setState((s) => ({ ...s, loading: true, error: null }));
      try {
        const data = await apiFetch<{ user_id: number; email: string; token: string }>(
          "/auth/register",
          {
            method: "POST",
            body: JSON.stringify({ email, password }),
          },
        );
        setStoredToken(data.token);
        const user = await apiFetch<User>("/auth/me");
        setState({ user, loading: false, error: null });
      } catch (err) {
        setState((s) => ({
          ...s,
          loading: false,
          error: err instanceof AuthError ? err.message : "Network error",
        }));
        throw err;
      }
    },
    [],
  );

  const logout = useCallback(() => {
    clearStoredToken();
    setState({ user: null, loading: false, error: null });
  }, []);

  const refreshUser = useCallback(async () => {
    try {
      const user = await apiFetch<User>("/auth/me");
      setState((s) => ({ ...s, user, error: null }));
    } catch (err) {
      if (err instanceof AuthError && err.status === 401) {
        clearStoredToken();
        setState({ user: null, loading: false, error: null });
      }
    }
  }, []);

  return (
    <AuthContext.Provider
      value={{ ...state, login, register, logout, refreshUser }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used within AuthProvider");
  return ctx;
}
