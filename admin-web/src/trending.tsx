import { useCallback, useEffect, useRef, useState } from 'react';
import { api, formatDate, UnauthorizedError } from './api';
import './trending.css';

type AdminPost = { id: string; body: string; author: string; company: string; likes: number; comments: number; trending: boolean; trendingAt: string | null; createdAt: string };
type Filter = 'all' | 'pinned';

const SEARCH_DEBOUNCE_MS = 300;
const TRENDING_MAX = 10;

export function TrendingPage({ flash, onUnauthorized }: { flash: (message: string) => void; onUnauthorized: () => void }) {
  const [filter, setFilter] = useState<Filter>('all');
  const [search, setSearch] = useState('');
  const [query, setQuery] = useState('');
  const [posts, setPosts] = useState<AdminPost[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [saving, setSaving] = useState<string | null>(null);
  // App re-creates these every render; refs keep the loader stable.
  const handlers = useRef({ flash, onUnauthorized });
  handlers.current = { flash, onUnauthorized };
  const request = useRef(0);

  useEffect(() => {
    const timer = window.setTimeout(() => setQuery(search.trim()), SEARCH_DEBOUNCE_MS);
    return () => window.clearTimeout(timer);
  }, [search]);

  const load = useCallback(async (announce = false) => {
    const id = ++request.current;
    setLoading(true);
    try {
      const result = await api<AdminPost[]>(`/api/admin/posts${query ? `?${new URLSearchParams({ q: query })}` : ''}`);
      if (id !== request.current) return;
      setPosts(result); setError('');
      if (announce) handlers.current.flash(`Posts updated · ${result.filter(post => post.trending).length} pinned`);
    } catch (err) {
      if (id !== request.current) return;
      if (err instanceof UnauthorizedError) handlers.current.onUnauthorized();
      else setError(err instanceof Error ? err.message : 'Could not load posts');
    } finally { if (id === request.current) setLoading(false); }
  }, [query]);
  useEffect(() => { void load(); }, [load]);

  async function toggle(post: AdminPost) {
    if (saving) return;
    setSaving(post.id);
    try {
      await api(`/api/admin/posts/${post.id}/trending`, { method: 'POST', body: { trending: !post.trending } });
      flash(post.trending ? 'Removed from Trending' : 'Pinned to Trending');
      await load();
    } catch (err) {
      if (err instanceof UnauthorizedError) { onUnauthorized(); return; }
      flash(err instanceof Error ? err.message : 'Something went wrong');
    } finally { setSaving(null); }
  }

  const pinnedCount = posts.filter(post => post.trending).length;
  const shown = filter === 'pinned' ? posts.filter(post => post.trending) : posts;

  return <>
    <div className="page-heading"><div><span className="eyebrow">COMMUNITY</span><h1>Trending</h1><p>Pin posts to the top of the app’s Trending tab. The rest of the top {TRENDING_MAX} is filled automatically by recent likes and comments.</p></div>
      <button className="button button-subtle refresh-button" onClick={() => void load(true)} disabled={loading} aria-busy={loading}><span className={loading ? 'spinning' : ''}>↻</span> {loading ? 'Refreshing…' : 'Refresh'}</button></div>
    {error && <div className="panel otp-banner"><b>Trending pins aren’t available</b><p>{error}</p></div>}
    <div className="toolbar"><div className="account-filters" role="tablist">
      <button role="tab" aria-selected={filter === 'all'} className={filter === 'all' ? 'active' : ''} onClick={() => setFilter('all')}>Recent posts<em>{posts.length}</em></button>
      <button role="tab" aria-selected={filter === 'pinned'} className={filter === 'pinned' ? 'active' : ''} onClick={() => setFilter('pinned')}>Pinned<em>{pinnedCount}</em></button></div>
      <label className="search"><span>⌕</span><input placeholder="Search post text…" value={search} onChange={e => setSearch(e.target.value)} /></label>
      {pinnedCount > TRENDING_MAX && <span className="toolbar-hint">Only the {TRENDING_MAX} newest pins are shown in the app</span>}</div>
    <section className="panel table-panel"><table><thead><tr><th>POST</th><th>COMPANY</th><th>LIKES</th><th>COMMENTS</th><th>POSTED</th><th></th></tr></thead><tbody>{shown.map(post => <tr key={post.id} className={post.trending ? 'trending-row' : ''}>
      <td><div className="trending-post">{post.trending && <span className="trending-badge">🔥 Pinned</span>}<p>{post.body}</p><small>{post.author}{post.trending && post.trendingAt ? ` · pinned ${formatDate(post.trendingAt)}` : ''}</small></div></td>
      <td>{post.company || '—'}</td>
      <td>{post.likes}</td>
      <td>{post.comments}</td>
      <td>{formatDate(post.createdAt)}</td>
      <td className="account-actions"><button className={`row-action ${post.trending ? 'danger' : ''}`} disabled={saving !== null} onClick={() => void toggle(post)}>{saving === post.id ? 'Saving…' : post.trending ? 'Unpin' : 'Pin to Trending'}</button></td>
    </tr>)}</tbody></table>
      {!loading && !error && shown.length === 0 && <div className="empty-state"><span>✳</span><b>{filter === 'pinned' ? 'Nothing pinned' : query ? 'No posts found' : 'No posts yet'}</b><p>{filter === 'pinned' ? 'Pin a post from Recent posts to feature it in Trending.' : query ? 'Try different words.' : 'Active posts will appear here.'}</p></div>}
    </section>
  </>;
}
