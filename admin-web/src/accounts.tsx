import React, { useCallback, useEffect, useRef, useState } from 'react';
import { api, formatDate, UnauthorizedError } from './api';
import './accounts.css';

type AccountStatus = 'active' | 'deactivated';
type Account = {
  id: string; email: string; name: string; company: string | null; status: AccountStatus;
  deactivatedAt: string | null; deactivatedBy: 'self' | 'admin' | null; reason: string | null;
  purgeAfter: string | null; createdAt: string; lastSignInAt: string | null;
};
type AccountCounts = { all: number; active: number; deactivated: number; dueForPurge: number };
type AccountPage = { items: Account[]; total: number; page: number; pageSize: number; counts: AccountCounts; graceDays: number };
type Filter = 'all' | AccountStatus;
type Dialog = { type: 'deactivate' | 'restore' | 'delete'; account: Account } | { type: 'purge-due' };

const FILTERS: { id: Filter; label: string; count: (counts: AccountCounts) => number }[] = [
  { id: 'all', label: 'All', count: c => c.all },
  { id: 'active', label: 'Active', count: c => c.active },
  { id: 'deactivated', label: 'Deleted', count: c => c.deactivated },
];
const SEARCH_DEBOUNCE_MS = 300;
const DAY_MS = 86_400_000;

function purgeLabel(purgeAfter: string | null) {
  if (!purgeAfter) return '—';
  const days = Math.ceil((Date.parse(purgeAfter) - Date.now()) / DAY_MS);
  return days <= 0 ? 'Due now' : `In ${days} ${days === 1 ? 'day' : 'days'}`;
}
const initials = (name: string) => name.split(' ').map(part => part[0]).slice(0, 2).join('').toUpperCase() || '?';

export function AccountsPage({ flash, onUnauthorized }: { flash: (message: string) => void; onUnauthorized: () => void }) {
  const [filter, setFilter] = useState<Filter>('all');
  const [search, setSearch] = useState('');
  const [query, setQuery] = useState('');
  const [page, setPage] = useState(1);
  const [data, setData] = useState<AccountPage | null>(null);
  const [loading, setLoading] = useState(true);
  const [dialog, setDialog] = useState<Dialog | null>(null);
  const [reason, setReason] = useState('');
  const [confirmText, setConfirmText] = useState('');
  const [busy, setBusy] = useState(false);
  // App re-creates these every render; refs keep the loaders stable.
  const handlers = useRef({ flash, onUnauthorized });
  handlers.current = { flash, onUnauthorized };
  const request = useRef(0);

  useEffect(() => {
    const timer = window.setTimeout(() => { setQuery(search.trim()); setPage(1); }, SEARCH_DEBOUNCE_MS);
    return () => window.clearTimeout(timer);
  }, [search]);

  const load = useCallback(async (announce = false) => {
    const id = ++request.current;
    setLoading(true);
    const params = new URLSearchParams({ page: String(page) });
    if (filter !== 'all') params.set('status', filter);
    if (query) params.set('q', query);
    try {
      const result = await api<AccountPage>(`/api/admin/accounts?${params}`);
      if (id !== request.current) return;
      setData(result);
      if (announce) handlers.current.flash(`Accounts updated · ${result.total} shown`);
    } catch (error) {
      if (id !== request.current) return;
      if (error instanceof UnauthorizedError) handlers.current.onUnauthorized();
      else handlers.current.flash(error instanceof Error ? error.message : 'Could not load accounts');
    } finally { if (id === request.current) setLoading(false); }
  }, [filter, query, page]);
  useEffect(() => { void load(); }, [load]);

  function open(next: Dialog) { setDialog(next); setReason(''); setConfirmText(''); }
  async function confirm(event: React.FormEvent) {
    event.preventDefault();
    if (!dialog || busy) return;
    setBusy(true);
    try {
      if (dialog.type === 'purge-due') {
        const { purged, failed } = await api<{ purged: number; failed: number }>('/api/admin/accounts/purge-due', { method: 'POST' });
        flash(`${purged} ${purged === 1 ? 'account' : 'accounts'} permanently deleted${failed ? ` · ${failed} failed` : ''}`);
      } else if (dialog.type === 'delete') {
        await api(`/api/admin/accounts/${dialog.account.id}`, { method: 'DELETE', body: { reason: reason.trim() || undefined } });
        flash(`${dialog.account.email} permanently deleted`);
      } else {
        await api(`/api/admin/accounts/${dialog.account.id}/${dialog.type}`, { method: 'POST', body: { reason: reason.trim() || undefined } });
        flash(dialog.type === 'restore' ? `${dialog.account.email} restored` : `${dialog.account.email} deactivated`);
      }
      setDialog(null);
      await load();
    } catch (error) {
      if (error instanceof UnauthorizedError) { onUnauthorized(); return; }
      flash(error instanceof Error ? error.message : 'Something went wrong');
    } finally { setBusy(false); }
  }

  const counts = data?.counts;
  const items = data?.items ?? [];
  const totalPages = data ? Math.max(1, Math.ceil(data.total / data.pageSize)) : 1;
  const firstRow = data && data.total ? (data.page - 1) * data.pageSize + 1 : 0;
  const lastRow = data ? firstRow + items.length - Math.min(1, items.length) : 0;

  return <>
    <div className="page-heading"><div><span className="eyebrow">PEOPLE</span><h1>Account manager</h1><p>Review deleted accounts, restore them within the {data?.graceDays ?? 30}-day grace period, or remove them permanently.</p></div>
      <div className="company-heading-actions"><button className="button button-subtle refresh-button" onClick={() => void load(true)} disabled={loading} aria-busy={loading}><span className={loading ? 'spinning' : ''}>↻</span> {loading ? 'Refreshing…' : 'Refresh'}</button>{(counts?.dueForPurge ?? 0) > 0 && <button className="button button-danger" onClick={() => open({ type: 'purge-due' })}>Purge {counts!.dueForPurge} due</button>}</div></div>
    <div className="toolbar"><div className="account-filters" role="tablist">{FILTERS.map(item => <button key={item.id} role="tab" aria-selected={filter === item.id} className={filter === item.id ? 'active' : ''} onClick={() => { setFilter(item.id); setPage(1); }}>{item.label}{counts && <em>{item.count(counts).toLocaleString()}</em>}</button>)}</div>
      <label className="search"><span>⌕</span><input placeholder="Search name or email…" value={search} onChange={e => setSearch(e.target.value)} /></label>
      <span className="toolbar-hint">{data ? `${firstRow}–${lastRow} of ${data.total.toLocaleString()}` : ''}</span></div>
    <section className="panel table-panel"><table><thead><tr><th>MEMBER</th><th>COMPANY</th><th>STATUS</th><th>PERMANENT DELETION</th><th>JOINED</th><th>LAST SIGN-IN</th><th></th></tr></thead><tbody>{items.map(account => <tr key={account.id}>
      <td><div className="person-cell"><span className="company-monogram">{initials(account.name)}</span><div className="account-identity"><b>{account.name}</b><a className="member-email" href={`mailto:${account.email}`}>{account.email}</a></div></div></td>
      <td>{account.company ?? '—'}</td>
      <td>{account.status === 'active' ? <span className="status-pill status-active"><i/>Active</span> : <span className="status-pill status-deleted" title={account.reason ?? undefined}><i/>{account.deactivatedBy === 'admin' ? 'Deactivated by admin' : 'Deleted by member'}</span>}{account.deactivatedAt && <small className="account-sub">{formatDate(account.deactivatedAt)}{account.reason ? ` · “${account.reason}”` : ''}</small>}</td>
      <td>{account.status === 'deactivated' ? <span className={purgeLabel(account.purgeAfter) === 'Due now' ? 'purge-due' : ''}>{purgeLabel(account.purgeAfter)}</span> : '—'}</td>
      <td>{formatDate(account.createdAt)}</td>
      <td>{account.lastSignInAt ? formatDate(account.lastSignInAt) : 'Never'}</td>
      <td className="account-actions">{account.status === 'active'
        ? <button className="row-action" onClick={() => open({ type: 'deactivate', account })}>Deactivate</button>
        : <button className="row-action" onClick={() => open({ type: 'restore', account })}>Restore</button>}
        <button className="row-action danger" onClick={() => open({ type: 'delete', account })}>Delete</button></td>
    </tr>)}</tbody></table>
      {!loading && items.length === 0 && <div className="empty-state"><span>✳</span><b>{query ? 'No accounts found' : filter === 'deactivated' ? 'No deleted accounts' : 'No accounts yet'}</b><p>{query ? 'Try a different name or email.' : filter === 'deactivated' ? 'Accounts members delete show up here until they are purged.' : 'Registered members will appear here.'}</p></div>}
    </section>
    {totalPages > 1 && <div className="account-pager"><button className="button button-subtle" disabled={page <= 1 || loading} onClick={() => setPage(p => p - 1)}>← Previous</button><span>Page {page} of {totalPages}</span><button className="button button-subtle" disabled={page >= totalPages || loading} onClick={() => setPage(p => p + 1)}>Next →</button></div>}
    {dialog && <div className="modal-backdrop" onMouseDown={e => { if (e.target === e.currentTarget && !busy) setDialog(null); }}><form className="modal manual-company-form" role="alertdialog" onSubmit={confirm}>
      <button type="button" className="modal-close" onClick={() => setDialog(null)} disabled={busy}>×</button>
      <span className="upload-icon">{dialog.type === 'restore' ? '↺' : '⊘'}</span><span className="eyebrow">ACCOUNT MANAGER</span>
      {dialog.type === 'purge-due' && <><h2>Purge due accounts?</h2><p>{counts?.dueForPurge ?? 0} deleted {counts?.dueForPurge === 1 ? 'account has' : 'accounts have'} passed the grace period. Their profiles, posts, comments and reactions will be erased permanently. This can’t be undone.</p></>}
      {dialog.type === 'deactivate' && <><h2>Deactivate account?</h2><p><b>{dialog.account.email}</b> will be signed out everywhere and hidden from the community. It is permanently deleted in {data?.graceDays ?? 30} days unless you restore it. The member can’t restore it themselves.</p><label>Reason <small>(optional, visible to admins)</small><textarea value={reason} onChange={e => setReason(e.target.value)} maxLength={500} placeholder="e.g. Repeated community guideline violations" /></label></>}
      {dialog.type === 'restore' && <><h2>Restore account?</h2><p><b>{dialog.account.email}</b> becomes active again and its posts reappear. The member can sign in right away.</p></>}
      {dialog.type === 'delete' && <><h2>Delete permanently?</h2><p>Everything for <b>{dialog.account.email}</b> — profile, posts, comments and reactions — is erased right now. This can’t be undone.</p><label>Type the email to confirm<input autoFocus value={confirmText} onChange={e => setConfirmText(e.target.value)} placeholder={dialog.account.email} /></label></>}
      <div className="modal-actions"><button type="button" className="button button-subtle" onClick={() => setDialog(null)} disabled={busy}>Cancel</button>
        <button type="submit" className={`button ${dialog.type === 'restore' ? 'button-primary' : 'button-danger'}`} disabled={busy || (dialog.type === 'delete' && confirmText.trim().toLowerCase() !== dialog.account.email.toLowerCase())}>{busy ? 'Working…' : dialog.type === 'restore' ? 'Restore account' : dialog.type === 'deactivate' ? 'Deactivate' : dialog.type === 'delete' ? 'Delete permanently' : 'Purge now'}</button></div>
    </form></div>}
  </>;
}
