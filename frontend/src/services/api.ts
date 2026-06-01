/**
 * AiFlowHub 前端 API 服务层
 *
 * 后端统一返回 { code: 0, data: ..., message: "ok" }
 * code === 0 表示成功，否则抛异常
 */

const TOKEN_KEY = "ai_api_agg_token";

/** 运行时检测 API 地址：本地 → localhost:8082，生产 → 同源（Nginx 代理）*/
function getApiBase(): string {
  if (typeof window === "undefined") return "http://localhost:8082";
  return window.location.hostname === "localhost"
    ? "http://localhost:8082"
    : window.location.origin;
}

/** 从 localStorage / cookie 读取 JWT token */
export function getToken(): string | null {
  if (typeof window === "undefined") return null;
  const stored = localStorage.getItem(TOKEN_KEY);
  if (stored) return stored;
  const match = document.cookie
    .split("; ")
    .find((row) => row.startsWith(TOKEN_KEY + "="));
  return match ? decodeURIComponent(match.slice(TOKEN_KEY.length + 1)) : null;
}

/** 保存 token 到 localStorage */
export function setToken(token: string): void {
  localStorage.setItem(TOKEN_KEY, token);
}

/** 清除 token */
export function clearToken(): void {
  localStorage.removeItem(TOKEN_KEY);
}

/** 后端统一响应 */
interface ApiResponse<T> {
  code: number;
  data: T;
  message: string;
}

class ApiError extends Error {
  code: number;
  constructor(code: number, message: string) {
    super(message);
    this.code = code;
    this.name = "ApiError";
  }
}

/** 通用 fetch 封装，自动带 Authorization header */
async function request<T>(
  path: string,
  options: RequestInit = {}
): Promise<T> {
  const token = getToken();
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    ...(options.headers as Record<string, string>),
  };
  if (token) {
    headers["Authorization"] = `Bearer ${token}`;
  }

  const res = await fetch(`${getApiBase()}${path}`, {
    ...options,
    headers,
  });

  let json: ApiResponse<T>;
  try {
    json = await res.json();
  } catch {
    throw new ApiError(res.status, res.statusText || "Failed to parse response");
  }

  if (json.code !== 0) {
    throw new ApiError(json.code, json.message || "Unknown error");
  }

  return json.data;
}

/** GET 请求 */
export function apiGet<T = unknown>(path: string): Promise<T> {
  return request<T>(path, { method: "GET" });
}

/** POST 请求 */
export function apiPost<T = unknown>(
  path: string,
  body?: unknown
): Promise<T> {
  return request<T>(path, {
    method: "POST",
    body: body ? JSON.stringify(body) : undefined,
  });
}

/** DELETE 请求 */
export function apiDelete<T = unknown>(path: string): Promise<T> {
  return request<T>(path, { method: "DELETE" });
}

export { ApiError };
