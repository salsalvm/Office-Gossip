export const API_URL = (() => {
  const url = new URL(import.meta.env.VITE_API_URL || 'https://office-gossip-api.vercel.app');
  // On other LAN devices "localhost" is the device itself, so target the host serving this page.
  if (['localhost', '127.0.0.1'].includes(url.hostname)) url.hostname = window.location.hostname;
  return url.toString().replace(/\/$/, '');
})();
export const ACCESS_TOKEN_KEY = 'officegossip_access_token';
export const REFRESH_TOKEN_KEY = 'officegossip_refresh_token';

export class ApiError extends Error { constructor(message: string, readonly status: number, readonly data: Record<string, unknown> = {}) { super(message); } }
// The API rejects sessions it won't serve (expired, deleted, or the admin account) with 401/403.
export const isRejectedSession = (error: unknown): error is ApiError => error instanceof ApiError && (error.status === 401 || error.status === 403);
// Auth endpoints return user-safe copy for these, e.g. "Email or password is incorrect."
export const hasAuthMessage = (error: unknown): error is ApiError => error instanceof ApiError && [400, 401, 403, 409, 422].includes(error.status);
export function storeSession(accessToken: string, refreshToken?: string | null) { localStorage.setItem(ACCESS_TOKEN_KEY, accessToken); if (refreshToken) localStorage.setItem(REFRESH_TOKEN_KEY, refreshToken); }
export function clearStoredSession() { localStorage.removeItem(ACCESS_TOKEN_KEY); localStorage.removeItem(REFRESH_TOKEN_KEY); }

export async function api<T>(path: string, init?: RequestInit): Promise<T> {
  const send = (token: string | null) => fetch(`${API_URL}${path}`, { ...init, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}), ...init?.headers } });
  let response = await send(localStorage.getItem(ACCESS_TOKEN_KEY));
  if (response.status === 401 && path !== '/api/auth/refresh') {
    const refreshToken = localStorage.getItem(REFRESH_TOKEN_KEY);
    if (refreshToken) {
      const refreshed = await fetch(`${API_URL}/api/auth/refresh`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ refreshToken }) });
      if (refreshed.ok) {
        const session = await refreshed.json() as { accessToken: string; refreshToken: string };
        storeSession(session.accessToken, session.refreshToken);
        response = await send(session.accessToken);
      }
    }
  }
  if (!response.ok) {
    const payload = await response.json().catch(() => null) as { message?: string; error?: string; data?: Record<string, unknown> } | null;
    throw new ApiError(payload?.message || payload?.error || `Request failed (${response.status})`, response.status, payload?.data ?? {});
  }
  return response.json() as Promise<T>;
}
