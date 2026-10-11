export const API_URL = (() => {
  const url = new URL(import.meta.env.VITE_API_URL || 'https://office-gossip-api.vercel.app');
  // On other LAN devices "localhost" is the device itself, so target the host serving this page.
  if (['localhost', '127.0.0.1'].includes(url.hostname)) url.hostname = window.location.hostname;
  return url.toString().replace(/\/$/, '');
})();
export const TOKEN_KEY = 'officegossip-admin-token';

export class UnauthorizedError extends Error {}
export async function api<T>(path: string, options: { method?: string; body?: unknown } = {}): Promise<T> {
  const token = sessionStorage.getItem(TOKEN_KEY);
  const response = await fetch(`${API_URL}${path}`, {
    method: options.method ?? 'GET',
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  });
  const data = await response.json().catch(() => ({}));
  if (response.status === 401) throw new UnauthorizedError(data.message ?? 'Please sign in again.');
  if (!response.ok) throw new Error(data.message ?? 'Request failed');
  return data as T;
}

export function formatDate(value: string) {
  const date = new Date(value);
  const days = Math.floor((new Date().setHours(0, 0, 0, 0) - new Date(value).setHours(0, 0, 0, 0)) / 86400000);
  const time = date.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
  if (days === 0) return `Today, ${time}`;
  if (days === 1) return 'Yesterday';
  return date.toLocaleDateString([], { month: 'short', day: 'numeric', year: 'numeric' });
}
