import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import './style.css';
import './login.css';
import './updates.css';
import './otp.css';

type View = 'Overview' | 'Company requests' | 'Companies' | 'Memberships' | 'Updates' | 'Moderation' | 'OTP codes';
type OtpStatus = 'active' | 'used' | 'expired' | 'locked';
type OtpCode = { email: string; name: string | null; code: string; status: OtpStatus; attempts: number; createdAt: string; expiresAt: string; usedAt: string | null };
type OtpList = { mode: 'off' | 'fixed' | 'dynamic'; fixedCode: string | null; codes: OtpCode[] };
type Request = { id: string; name: string; domain: string; requester: string; email: string; createdAt: string; others: number };
type Company = { id: string; name: string; domain: string; members: number; status: 'Active' | 'Disabled' };
type Member = { id: string; name: string; email: string; company: string; method: string; createdAt: string };
type Reporter = { name: string; email: string; reason: string; createdAt: string };
type Report = { id: string; company: string; author: string; body: string; reason: string; createdAt: string; reports: number; reporters: Reporter[] };
type Dashboard = { companies: Company[]; requests: Request[]; members: Member[]; reports: Report[] };
type UpdateAudience = 'Everyone' | 'One user' | 'One company';
type AdminUpdate = { id: string; message: string; audience: UpdateAudience; target?: string; createdAt: string };

const API_URL = (() => {
  const url = new URL(import.meta.env.VITE_API_URL || 'http://localhost:4000');
  // On other LAN devices "localhost" is the device itself, so target the host serving this page.
  if (['localhost', '127.0.0.1'].includes(url.hostname)) url.hostname = window.location.hostname;
  return url.toString().replace(/\/$/, '');
})();
const TOKEN_KEY = 'officegossip-admin-token';
const joinMethods: Record<string, string> = { request: 'Request', invite: 'Invite', admin_approved: 'Admin approval', verified_domain: 'Verified domain' };

class UnauthorizedError extends Error {}
async function api<T>(path: string, options: { method?: string; body?: unknown } = {}): Promise<T> {
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
const normalizeName = (value: string) => value.trim().replace(/\s+/g, ' ');
function formatDate(value: string) {
  const date = new Date(value);
  const days = Math.floor((new Date().setHours(0, 0, 0, 0) - new Date(value).setHours(0, 0, 0, 0)) / 86400000);
  const time = date.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
  if (days === 0) return `Today, ${time}`;
  if (days === 1) return 'Yesterday';
  return date.toLocaleDateString([], { month: 'short', day: 'numeric', year: 'numeric' });
}
const navItems: { name: View; icon: string }[] = [
  { name: 'Overview', icon: '◫' }, { name: 'Company requests', icon: '↗' }, { name: 'Companies', icon: '▦' }, { name: 'Memberships', icon: '♙' }, { name: 'Updates', icon: '◉' }, { name: 'Moderation', icon: '⚑' }, { name: 'OTP codes', icon: '⌗' },
];
const otpStatusLabels: Record<OtpStatus, string> = { active: 'Active', used: 'Used', expired: 'Expired', locked: 'Locked' };
const OTP_REFRESH_MS = 10_000;

function App() {
  const [loggedIn, setLoggedIn] = useState(() => Boolean(sessionStorage.getItem(TOKEN_KEY)));
  const [loginEmail, setLoginEmail] = useState('');
  const [loginPassword, setLoginPassword] = useState('');
  const [loginError, setLoginError] = useState('');
  const [view, setView] = useState<View>('Overview');
  const [requests, setRequests] = useState<Request[]>([]);
  const [companies, setCompanies] = useState<Company[]>([]);
  const [members, setMembers] = useState<Member[]>([]);
  const [reports, setReports] = useState<Report[]>([]);
  const [updateMessage, setUpdateMessage] = useState('');
  const [updateAudience, setUpdateAudience] = useState<UpdateAudience>('Everyone');
  const [targetRecipient, setTargetRecipient] = useState('');
  const [sentUpdates, setSentUpdates] = useState<AdminUpdate[]>([]);
  const [sendingUpdate, setSendingUpdate] = useState(false);
  const [signingIn, setSigningIn] = useState(false);
  const pendingActions = useRef(new Set<string>());
  const [working, setWorking] = useState(0);
  const [query, setQuery] = useState('');
  const [notice, setNotice] = useState('');
  const [fileRows, setFileRows] = useState<string[][]>([]);
  const [importOpen, setImportOpen] = useState(false);
  const [manualAddOpen, setManualAddOpen] = useState(false);
  const [logoutOpen, setLogoutOpen] = useState(false);
  const [csvSkipped, setCsvSkipped] = useState(0);
  const [editingCompany, setEditingCompany] = useState<Company | null>(null);
  const [editName, setEditName] = useState('');
  const [editDomain, setEditDomain] = useState('');
  const [newCompanyName, setNewCompanyName] = useState('');
  const [newCompanyDomain, setNewCompanyDomain] = useState('');
  const fileRef = useRef<HTMLInputElement>(null);
  const filteredCompanies = useMemo(() => companies.filter(c => `${c.name} ${c.domain}`.toLowerCase().includes(query.toLowerCase())), [companies, query]);
  const filteredMembers = useMemo(() => members.filter(m => `${m.name} ${m.email} ${m.company}`.toLowerCase().includes(query.toLowerCase())), [members, query]);
  const pending = requests.length;
  const openReports = reports.length;
  function flash(message: string) { setNotice(message); window.setTimeout(() => setNotice(''), 3200); }
  const signOut = useCallback(() => { sessionStorage.removeItem(TOKEN_KEY); setLoggedIn(false); }, []);
  const loadDashboard = useCallback(async () => {
    try {
      const data = await api<Dashboard>('/api/admin/dashboard');
      setCompanies(data.companies); setRequests(data.requests); setMembers(data.members); setReports(data.reports);
    } catch (error) {
      if (error instanceof UnauthorizedError) signOut();
      else flash(error instanceof Error ? error.message : 'Could not load dashboard');
    }
  }, [signOut]);
  useEffect(() => { if (loggedIn) void loadDashboard(); }, [loggedIn, loadDashboard]);
  const [refreshingCompanies, setRefreshingCompanies] = useState(false);
  const loadCompanies = useCallback(async (announce = false) => {
    setRefreshingCompanies(true);
    try {
      const list = await api<Company[]>('/api/admin/companies');
      setCompanies(list);
      if (announce) flash(`Company list updated · ${list.length} ${list.length === 1 ? 'company' : 'companies'}`);
    } catch (error) {
      if (error instanceof UnauthorizedError) signOut();
      else flash(error instanceof Error ? error.message : 'Could not load companies');
    } finally { setRefreshingCompanies(false); }
  }, [signOut]);
  useEffect(() => { if (loggedIn && view === 'Companies') void loadCompanies(); }, [loggedIn, view, loadCompanies]);
  useEffect(() => {
    if (!loggedIn || view !== 'Updates') return;
    api<AdminUpdate[]>('/api/admin/announcements').then(setSentUpdates).catch(error => {
      if (error instanceof UnauthorizedError) signOut();
      else flash(error instanceof Error ? error.message : 'Could not load sent updates');
    });
  }, [loggedIn, view, signOut]);
  const [otps, setOtps] = useState<OtpList | null>(null);
  const [refreshingOtps, setRefreshingOtps] = useState(false);
  const loadOtps = useCallback(async (announce = false) => {
    setRefreshingOtps(true);
    try {
      const list = await api<OtpList>('/api/admin/otps');
      setOtps(list);
      if (announce) flash(`Codes updated · ${list.codes.filter(c => c.status === 'active').length} active`);
    } catch (error) {
      if (error instanceof UnauthorizedError) signOut();
      else flash(error instanceof Error ? error.message : 'Could not load sign-up codes');
    } finally { setRefreshingOtps(false); }
  }, [signOut]);
  useEffect(() => {
    if (!loggedIn || view !== 'OTP codes') return;
    void loadOtps();
    const timer = window.setInterval(() => void loadOtps(), OTP_REFRESH_MS);
    return () => window.clearInterval(timer);
  }, [loggedIn, view, loadOtps]);
  const filteredOtps = useMemo(() => { const q = query.trim().toLowerCase(); return (otps?.codes ?? []).filter(c => c.email.includes(q) || (c.name ?? '').toLowerCase().includes(q)); }, [otps, query]);
  function copyOtp(item: OtpCode) {
    navigator.clipboard.writeText(item.code).then(() => flash(`Code for ${item.email} copied`), () => flash('Could not copy the code'));
  }
  async function revokeOtp(item: OtpCode) {
    const key = `otp:${item.email}`;
    if (pendingActions.current.has(key)) return;
    pendingActions.current.add(key); setWorking(n => n + 1);
    try {
      await api(`/api/admin/otps/${encodeURIComponent(item.email)}`, { method: 'DELETE' });
      flash(`Code for ${item.email} revoked`);
    } catch (error) {
      if (error instanceof UnauthorizedError) { signOut(); return; }
      flash(error instanceof Error ? error.message : 'Could not revoke the code');
    } finally { pendingActions.current.delete(key); setWorking(n => n - 1); }
    await loadOtps();
  }
  // One request per key at a time; action buttons are dimmed while any action is saving.
  async function run(action: () => Promise<unknown>, success: string, key = success) {
    if (pendingActions.current.has(key)) return;
    pendingActions.current.add(key); setWorking(n => n + 1);
    try { await action(); flash(success); }
    catch (error) {
      if (error instanceof UnauthorizedError) { signOut(); return; }
      flash(error instanceof Error ? error.message : 'Something went wrong');
    } finally { pendingActions.current.delete(key); setWorking(n => n - 1); }
    await loadDashboard();
  }
  function approveRequest(item: Request) { void run(() => api(`/api/admin/requests/${item.id}/approve`, { method: 'POST' }), `${item.name} approved and added to the directory`, `request:${item.id}`); }
  function rejectRequest(item: Request) { void run(() => api(`/api/admin/requests/${item.id}/reject`, { method: 'POST' }), `${item.name} request declined`, `request:${item.id}`); }
  function approveAllRequests() {
    if (!requests.length) return;
    const count = requests.length;
    void run(() => api('/api/admin/requests/approve-all', { method: 'POST' }), `${count} company ${count === 1 ? 'request' : 'requests'} approved`, 'approve-all');
  }
  async function signIn(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (signingIn) return;
    setSigningIn(true);
    try {
      const { token } = await api<{ token: string }>('/api/admin/login', { method: 'POST', body: { email: loginEmail, password: loginPassword } });
      sessionStorage.setItem(TOKEN_KEY, token);
      setLoggedIn(true); setLoginError(''); setLoginPassword('');
    } catch (error) { setLoginError(error instanceof Error ? error.message : 'Email or password is incorrect.'); }
    finally { setSigningIn(false); }
  }
  async function sendUpdate(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const message = updateMessage.trim();
    const target = targetRecipient.trim();
    if (!message || sendingUpdate) return;
    if (updateAudience !== 'Everyone' && !target) { flash(updateAudience === 'One user' ? 'Enter the user email or username' : 'Choose a company'); return; }
    setSendingUpdate(true);
    try {
      const sent = await api<AdminUpdate>('/api/admin/announcements', { method: 'POST', body: { message, audience: updateAudience, target: updateAudience === 'Everyone' ? undefined : target } });
      setSentUpdates(list => [sent, ...list]);
      flash(updateAudience === 'Everyone' ? 'Update published to all users' : `Update sent to ${sent.target ?? target}`);
      setUpdateMessage(''); setTargetRecipient('');
    } catch (error) {
      if (error instanceof UnauthorizedError) signOut();
      else flash(error instanceof Error ? error.message : 'Could not send the update');
    } finally { setSendingUpdate(false); }
  }
  function importCsv(file?: File) {
    if (!file) return;
    if (!file.name.toLowerCase().endsWith('.csv')) { flash('Choose a .csv file to import'); return; }
    const reader = new FileReader();
    reader.onload = () => {
      const rows = String(reader.result ?? '').trim().split(/\r?\n/).map(row => row.split(',').map(cell => cell.trim().replace(/^"|"$/g, ''))).filter(row => row.length > 1);
      const parsed = rows.slice(1).map(row => [normalizeName(row[0] ?? ''), ...row.slice(1)]).filter(row => row[0]);
      const taken = new Set(companies.map(c => c.name.toLowerCase()));
      const unique = parsed.filter(row => !taken.has(row[0].toLowerCase()) && Boolean(taken.add(row[0].toLowerCase())));
      setFileRows(unique); setCsvSkipped(parsed.length - unique.length); setImportOpen(true);
    };
    reader.readAsText(file);
  }
  async function confirmImport() {
    const rows = fileRows.map(row => ({ name: row[0], domain: row[1] ?? '' }));
    const skippedLocally = csvSkipped;
    setImportOpen(false); setFileRows([]); setCsvSkipped(0); setView('Companies'); setQuery('');
    try {
      const { added, skipped } = await api<{ added: number; skipped: number }>('/api/admin/companies', { method: 'POST', body: { companies: rows } });
      const totalSkipped = skipped + skippedLocally;
      flash(`${added} ${added === 1 ? 'company' : 'companies'} imported${totalSkipped ? ` · ${totalSkipped} duplicate${totalSkipped === 1 ? '' : 's'} skipped` : ''}`);
    } catch (error) {
      if (error instanceof UnauthorizedError) { signOut(); return; }
      flash(error instanceof Error ? error.message : 'Import failed');
    }
    await loadDashboard();
  }
  function addCompanyManually(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const name = normalizeName(newCompanyName);
    const domain = newCompanyDomain.trim();
    if (name.length < 2) { flash('Company name must be at least 2 characters'); return; }
    setNewCompanyName(''); setNewCompanyDomain(''); setManualAddOpen(false);
    const existing = companies.find(company => company.name.toLowerCase() === name.toLowerCase());
    if (existing) { flash(`${existing.name} already exists · skipped`); return; }
    void (async () => {
      try {
        const { added } = await api<{ added: number }>('/api/admin/companies', { method: 'POST', body: { name, domain } });
        flash(added ? `${name} added to the company directory` : `${name} already exists · skipped`);
      } catch (error) {
        if (error instanceof UnauthorizedError) { signOut(); return; }
        flash(error instanceof Error ? error.message : 'Something went wrong');
      }
      await loadDashboard();
    })();
  }
  function toggleCompany(company: Company) {
    void run(() => api(`/api/admin/companies/${company.id}`, { method: 'PATCH', body: { status: company.status === 'Active' ? 'disabled' : 'active' } }), `${company.name} ${company.status === 'Active' ? 'disabled' : 'activated'}`, `company:${company.id}`);
  }
  function openEditCompany(company: Company) { setEditingCompany(company); setEditName(company.name); setEditDomain(company.domain); }
  function saveCompanyEdit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!editingCompany) return;
    const company = editingCompany;
    const name = editName.trim().replace(/\s+/g, ' ');
    if (name.length < 2) { flash('Company name must be at least 2 characters'); return; }
    if (companies.some(c => c.id !== company.id && c.name.toLowerCase() === name.toLowerCase())) { flash('A company with this name already exists'); return; }
    setEditingCompany(null);
    void run(() => api(`/api/admin/companies/${company.id}`, { method: 'PATCH', body: { name, domain: editDomain.trim() } }), `${name} updated`, `company:${company.id}`);
  }
  function moderate(report: Report, action: 'dismiss' | 'remove') {
    void run(() => api(`/api/admin/reports/${report.id}/${action}`, { method: 'POST' }), action === 'remove' ? 'Post removed and report resolved' : 'Report dismissed', `report:${report.id}`);
  }
  const weekBars = useMemo(() => {
    const today = new Date().setHours(0, 0, 0, 0);
    const counts = Array.from({ length: 7 }, (_, i) => members.filter(m => new Date(m.createdAt).setHours(0, 0, 0, 0) === today - (6 - i) * 86400000).length);
    const max = Math.max(1, ...counts);
    return counts.map((count, i) => ({ count, height: Math.max(6, Math.round(count / max * 100)), label: new Date(today - (6 - i) * 86400000).toLocaleDateString([], { weekday: 'short' }) }));
  }, [members]);
  const joinedThisWeek = weekBars.reduce((sum, bar) => sum + bar.count, 0);
  function renderPage() {
    if (view === 'Overview') return <>
      <div className="welcome"><div><span className="eyebrow">MONDAY, SEPTEMBER 28, 2026</span><h1>Good morning, Honai <span>☀</span></h1><p>Here’s what’s happening across your community today.</p></div><button className="button button-primary" onClick={() => { setView('Companies'); setImportOpen(true); }}>＋ Add companies</button></div>
      <div className="stat-grid">
        <Stat label="Total companies" value={String(companies.filter(c => c.status === 'Active').length).padStart(2, '0')} hint="Across your workspace" icon="▦" tone="lavender" />
        <Stat label="Active members" value={members.length.toLocaleString()} hint={`${joinedThisWeek} joined this week`} icon="♙" tone="mint" onClick={() => setView('Memberships')} />
        <Stat label="Requests to review" value={String(pending).padStart(2, '0')} hint={pending ? 'Needs your attention' : 'You’re all caught up'} icon="↗" tone="peach" onClick={() => setView('Company requests')} />
        <Stat label="Open reports" value={String(openReports).padStart(2, '0')} hint={openReports ? 'Keep the community safe' : 'No open reports'} icon="⚑" tone="blue" onClick={() => setView('Moderation')} />
      </div>
      <div className="overview-grid"><section className="panel activity-panel"><div className="panel-heading"><div><span className="eyebrow">NEEDS YOUR ATTENTION</span><h2>Review queue</h2></div><button className="text-button" onClick={() => setView('Company requests')}>View all <span>→</span></button></div>
        {requests.length ? requests.slice(0, 2).map(r => <RequestRow key={r.id} item={r} approve={approveRequest} reject={rejectRequest} compact />) : <Empty title="All clear" detail="No company requests need review." />}
        {reports.length > 0 && <div className="queue-report"><span className="report-icon">⚑</span><div><b>{reports[0].reports} reports need attention</b><small>{reports[0].reason} · {reports[0].company}</small></div><button className="icon-button" onClick={() => setView('Moderation')}>→</button></div>}
      </section><section className="panel snapshot"><div className="panel-heading"><div><span className="eyebrow">YOUR COMMUNITY</span><h2>At a glance</h2></div><span className="live-dot">Live</span></div><div className="snapshot-figure"><strong>{members.length.toLocaleString()}</strong><span>members across active companies</span></div><div className="bar-chart" aria-label="Members joining this week">{weekBars.map(bar => <i key={bar.label} style={{height:`${bar.height}%`}} title={`${bar.count} joined`}/>)}</div><div className="chart-labels">{weekBars.map(bar => <span key={bar.label}>{bar.label}</span>)}</div><p className="chart-note"><span>{joinedThisWeek}</span> {joinedThisWeek === 1 ? 'member' : 'members'} joined this week</p></section></div>
      <section className="panel recent-panel"><div className="panel-heading"><div><span className="eyebrow">LATEST</span><h2>Recently added companies</h2></div><button className="text-button" onClick={() => setView('Companies')}>Company directory <span>→</span></button></div><CompanyTable companies={companies.slice(0, 3)} toggle={toggleCompany} edit={openEditCompany} compact /></section>
    </>;
    if (view === 'Company requests') return <><PageHeading eyebrow="COMPANY ACCESS" title="Company requests" detail="Review requests from members who want to bring their company to Office Gossip." /><div className="toolbar"><span className="count-pill">{requests.length} pending</span><span className="toolbar-hint">Approve all requests with one click</span>{requests.length > 0 && <button className="button button-primary" onClick={approveAllRequests}>✓ Approve all ({requests.length})</button>}</div><section className="panel request-list">{requests.length ? requests.map(r => <RequestRow key={r.id} item={r} approve={approveRequest} reject={rejectRequest} />) : <Empty title="You’re all caught up" detail="New company requests will show up here." />}</section></>;
    if (view === 'Companies') return <><PageHeading eyebrow="WORKSPACE" title="Company directory" detail="Manage the companies and communities in your workspace." action={<div className="company-heading-actions"><button className="button button-subtle refresh-button" onClick={() => void loadCompanies(true)} disabled={refreshingCompanies} aria-busy={refreshingCompanies}><span className={refreshingCompanies ? 'spinning' : ''}>↻</span> {refreshingCompanies ? 'Refreshing…' : 'Refresh'}</button><button className="button button-subtle" onClick={() => setManualAddOpen(true)}>＋ Add one manually</button><button className="button button-primary" onClick={() => { setImportOpen(true); setFileRows([]); setCsvSkipped(0); }}>＋ Import companies</button></div>} /><div className="toolbar"><label className="search"><span>⌕</span><input placeholder="Search companies…" value={query} onChange={e => setQuery(e.target.value)} /></label><span className="toolbar-hint">{companies.length} companies</span></div><section className="panel table-panel"><CompanyTable companies={filteredCompanies} toggle={toggleCompany} edit={openEditCompany} /></section></>;
    if (view === 'Memberships') return <><PageHeading eyebrow="PEOPLE" title="Memberships" detail="Review member access and see how people joined their company community." /><div className="toolbar"><label className="search"><span>⌕</span><input placeholder="Search people or companies…" value={query} onChange={e => setQuery(e.target.value)} /></label><span className="toolbar-hint">{members.length} members</span></div><section className="panel table-panel"><table><thead><tr><th>MEMBER</th><th>EMAIL</th><th>COMPANY</th><th>JOINED VIA</th><th>DATE</th></tr></thead><tbody>{filteredMembers.map(m => <tr key={m.id}><td><div className="person-cell"><Avatar name={m.name}/><b>{m.name}</b></div></td><td>{m.email ? <a className="member-email" href={`mailto:${m.email}`}>{m.email}</a> : '—'}</td><td>{m.company}</td><td><span className="method-pill">{joinMethods[m.method] ?? m.method}</span></td><td>{formatDate(m.createdAt)}</td></tr>)}</tbody></table>{filteredMembers.length === 0 && <Empty title="No members found" detail="Try a different search." />}</section></>;
    if (view === 'Updates') return <><PageHeading eyebrow="ANNOUNCEMENTS" title="Flash updates" detail="Send an update to everyone, one user, or one company." /><div className="updates-layout"><form className="panel update-composer" onSubmit={e => void sendUpdate(e)}><span className="compose-kicker">NEW UPDATE</span><label className="update-message-label" htmlFor="update-message">Message</label><textarea id="update-message" value={updateMessage} onChange={e => setUpdateMessage(e.target.value)} maxLength={500} placeholder="What would you like people to know?" required/><div className="compose-bottom"><span>{updateMessage.length}/500</span><span>Keep it clear and helpful</span></div><div className="audience-control"><div><b>Send to</b><small>Choose who should receive this update</small></div><select value={updateAudience} onChange={e => { setUpdateAudience(e.target.value as UpdateAudience); setTargetRecipient(''); }}><option>Everyone</option><option>One user</option><option>One company</option></select></div>{updateAudience === 'One user' && <label className="target-user-field">Target user<input value={targetRecipient} onChange={e => setTargetRecipient(e.target.value)} placeholder="Email address or username" required/><small>Use the account email or username of the recipient.</small></label>}{updateAudience === 'One company' && <label className="target-user-field">Target company<select value={targetRecipient} onChange={e => setTargetRecipient(e.target.value)} required><option value="">Choose a company</option>{companies.filter(company => company.status === 'Active').map(company => <option key={company.name} value={company.name}>{company.name}</option>)}</select><small>Only members of this active company will receive the update.</small></label>}<div className="audience-preview"><span>{updateAudience === 'Everyone' ? '◎' : updateAudience === 'One company' ? '▦' : '♙'}</span><div><b>{updateAudience === 'Everyone' ? 'All active users' : targetRecipient.trim() || (updateAudience === 'One user' ? 'One selected user' : 'One selected company')}</b><small>{updateAudience === 'Everyone' ? 'This announcement will be visible to the whole community.' : updateAudience === 'One company' ? 'Only members of the selected company will receive it.' : 'Only the selected user will receive this update.'}</small></div></div><button className="button button-primary publish-update" type="submit" disabled={sendingUpdate || !updateMessage.trim() || (updateAudience !== 'Everyone' && !targetRecipient.trim())}>↗ &nbsp;{updateAudience === 'Everyone' ? 'Publish to everyone' : updateAudience === 'One company' ? 'Send to company' : 'Send to user'}</button></form><section className="updates-history"><div className="panel-heading"><div><span className="eyebrow">RECENT ACTIVITY</span><h2>Sent updates</h2></div><span className="history-count">{sentUpdates.length}</span></div>{sentUpdates.length ? sentUpdates.map(item => <article className="panel sent-update" key={item.id}><div><span className="update-audience-pill">{item.audience === 'Everyone' ? '◎ Everyone' : item.audience === 'One company' ? '▦ One company' : '♙ One user'}</span><small>{formatDate(item.createdAt)}</small></div><p>{item.message}</p>{item.target && <small className="sent-target">To: {item.target}</small>}</article>) : <div className="panel"><Empty title="No updates yet" detail="Your published announcements will appear here." /></div>}</section></div></>;
    if (view === 'OTP codes') {
      const activeCount = otps?.codes.filter(c => c.status === 'active').length ?? 0;
      return <><PageHeading eyebrow="SIGN-UP SUPPORT" title="OTP codes" detail="Sign-up verification codes, for members whose code email didn’t arrive. Share a code only with the person who owns that email." action={<button className="button button-subtle refresh-button" onClick={() => void loadOtps(true)} disabled={refreshingOtps} aria-busy={refreshingOtps}><span className={refreshingOtps ? 'spinning' : ''}>↻</span> {refreshingOtps ? 'Refreshing…' : 'Refresh'}</button>} />
        {otps?.mode === 'off' && <div className="panel otp-banner"><b>Fallback codes are turned off</b><p>Set <code>DEV_MASTER_OTP=dynamic</code> in the backend config and redeploy to issue a code per sign-up that appears here.</p></div>}
        {otps?.mode === 'fixed' && <div className="panel otp-banner"><b>One fixed code is in use for every sign-up</b><p>Code: <span className="otp-code">{otps.fixedCode}</span> · Set <code>DEV_MASTER_OTP=dynamic</code> for a separate single-use code per email.</p></div>}
        {otps?.mode === 'dynamic' && <><div className="toolbar"><label className="search"><span>⌕</span><input placeholder="Search by name or email…" value={query} onChange={e => setQuery(e.target.value)} /></label><span className="count-pill">{activeCount} active</span><span className="toolbar-hint">Codes expire 10 minutes after they’re sent · refreshes every 10 seconds</span></div>
          <section className="panel table-panel"><table><thead><tr><th>NAME</th><th>EMAIL</th><th>CODE</th><th>STATUS</th><th>REQUESTED</th><th>EXPIRES</th><th></th></tr></thead><tbody>{filteredOtps.map(item => <tr key={item.email}><td>{item.name || <small className="otp-attempts">—</small>}</td><td>{item.email}</td><td><span className={`otp-code ${item.status === 'active' ? '' : 'otp-code-dim'}`}>{item.code}</span></td><td><span className={`status-pill otp-status-${item.status}`}><i/>{otpStatusLabels[item.status]}</span>{item.attempts > 0 && <small className="otp-attempts">{item.attempts} wrong {item.attempts === 1 ? 'try' : 'tries'}</small>}</td><td>{formatDate(item.createdAt)}</td><td>{item.status === 'used' && item.usedAt ? `Used ${formatDate(item.usedAt)}` : formatDate(item.expiresAt)}</td><td>{item.status === 'active' && <><button className="row-action" onClick={() => copyOtp(item)}>Copy</button><button className="row-action" onClick={() => void revokeOtp(item)}>Revoke</button></>}</td></tr>)}</tbody></table>{filteredOtps.length === 0 && <Empty title={query ? 'No codes found' : 'No codes yet'} detail={query ? 'Try a different name or email.' : 'Codes appear here as soon as someone requests one at sign-up.'} />}</section></>}
      </>;
    }
    return <><PageHeading eyebrow="COMMUNITY SAFETY" title="Moderation queue" detail="Review reported posts and keep workplace conversations respectful." /><div className="toolbar"><span className="count-pill">{reports.length} open reports</span><span className="toolbar-hint">Reporter details are visible to admins only</span></div><div className="moderation-list">{reports.length ? reports.map(report => <article className="panel moderation-card" key={report.id}><div className="moderation-meta"><span className="company-chip">{report.company}</span><span>{formatDate(report.createdAt)}</span><span className="report-count">⚑ {report.reports} {report.reports === 1 ? 'report' : 'reports'}</span></div><div className="post-author"><Avatar name={report.author}/><div><b>{report.author}</b><small>Posted in {report.company}</small></div></div><blockquote>{report.body}</blockquote><div className="reason-line"><span>REPORTED FOR</span><b>{report.reason}</b></div><div className="reporter-list"><span>REPORTED BY</span>{report.reporters.map((r, i) => <div className="reporter-row" key={`${r.email}-${i}`}><b>{r.name}</b>{r.email ? <a className="member-email" href={`mailto:${r.email}`}>{r.email}</a> : <small>—</small>}{r.reason !== report.reason && <small>{r.reason}</small>}</div>)}</div><div className="moderation-actions"><button className="button button-subtle" onClick={() => moderate(report, 'dismiss')}>Dismiss report</button><button className="button button-danger" onClick={() => moderate(report, 'remove')}>Remove post</button></div></article>) : <section className="panel"><Empty title="No open reports" detail="Reported posts will appear here for review." /></section>}</div></>;
  }
  if (!loggedIn) return <Login email={loginEmail} setEmail={setLoginEmail} password={loginPassword} setPassword={setLoginPassword} error={loginError} busy={signingIn} onSubmit={signIn} />;
  return <div className={`app-shell ${working ? 'working' : ''}`} aria-busy={working > 0}>
    <aside className="sidebar">
      <a className="brand" href="#overview" onClick={e => { e.preventDefault(); setView('Overview'); }}><span className="brand-mark"><img src="/brand-mark.svg" alt="" /></span><span className="brand-name">office<span>gossip</span><small>ADMIN CONSOLE</small></span></a>
      <div className="workspace-switch"><span className="workspace-mark"><img src="/brand-mark.svg" alt="" /></span><span><b>Office Gossip</b><small>Workspace</small></span><span className="chevron">⌄</span></div>
      <div className="nav-label">WORKSPACE</div>
      <nav>{navItems.map(item => <button key={item.name} className={`nav-item ${view === item.name ? 'active' : ''}`} onClick={() => { setView(item.name); setQuery(''); }}><span className="nav-icon">{item.icon}</span>{item.name}{item.name === 'Company requests' && pending > 0 && <em>{pending}</em>}{item.name === 'Moderation' && openReports > 0 && <em className="nav-alert">{openReports}</em>}</button>)}</nav>
      <div className="sidebar-bottom"><div className="help-card"><div className="help-symbol">✳</div><b>Need a hand?</b><p>Find tips for managing your community.</p><button onClick={() => flash('Help center is coming soon')}>Visit help center <span>↗</span></button></div>
        <button className="profile-button" onClick={() => setLogoutOpen(true)}><span className="profile-avatar">H</span><span><b>Honai</b><small>Administrator · Sign out</small></span><span className="profile-dots">···</span></button>
      </div>
    </aside>
    <main className="main-area"><header className="topbar"><div className="breadcrumbs"><span>Workspace</span><span className="crumb-slash">/</span><b>{view}</b></div><div className="topbar-right"><span className="secure-label"><span>●</span> Admin workspace</span><button className="bell" aria-label="Notifications" onClick={() => flash('You’re all caught up')}>♧<i/></button><Avatar name="Honai"/></div></header>
      <div className="content">{renderPage()}<footer>Office Gossip Admin <span>·</span> Built for better workdays</footer></div>
    </main>
    {editingCompany && <div className="modal-backdrop" onMouseDown={e => { if (e.target === e.currentTarget) setEditingCompany(null); }}><form className="modal manual-company-form" onSubmit={saveCompanyEdit}><button type="button" className="modal-close" onClick={() => setEditingCompany(null)}>×</button><span className="upload-icon">✎</span><span className="eyebrow">COMPANY DIRECTORY</span><h2>Edit company</h2><p>Update how this company appears to members and in the signup list.</p><label>Company name<input autoFocus value={editName} onChange={e => setEditName(e.target.value)} maxLength={100} required/></label><label>Website domain<input value={editDomain} onChange={e => setEditDomain(e.target.value)} placeholder="e.g. acme.com"/></label><div className="modal-actions"><button type="button" className="button button-subtle" onClick={() => setEditingCompany(null)}>Cancel</button><button type="submit" className="button button-primary" disabled={!editName.trim() || (editName.trim().replace(/\s+/g, ' ') === editingCompany.name && editDomain.trim() === editingCompany.domain)}>Save changes</button></div></form></div>}
    {logoutOpen && <div className="modal-backdrop" onMouseDown={e => { if (e.target === e.currentTarget) setLogoutOpen(false); }}><section className="modal" role="alertdialog" aria-labelledby="logout-title"><button className="modal-close" onClick={() => setLogoutOpen(false)}>×</button><span className="upload-icon">⏻</span><span className="eyebrow">ADMIN SESSION</span><h2 id="logout-title">Sign out?</h2><p>You’ll need to enter your administrator credentials again to get back in.</p><div className="modal-actions"><button className="button button-subtle" autoFocus onClick={() => setLogoutOpen(false)}>Cancel</button><button className="button button-danger" onClick={() => { setLogoutOpen(false); signOut(); }}>Sign out</button></div></section></div>}
    {notice && <div className="toast"><span>✓</span>{notice}</div>}
    {manualAddOpen && <div className="modal-backdrop" onMouseDown={e => { if (e.target === e.currentTarget) setManualAddOpen(false); }}><form className="modal manual-company-form" onSubmit={addCompanyManually}><button type="button" className="modal-close" onClick={() => setManualAddOpen(false)}>×</button><span className="upload-icon">＋</span><span className="eyebrow">COMPANY DIRECTORY</span><h2>Add one company</h2><p>Enter the company name and website domain to add it to your directory.</p><label>Company name<input autoFocus value={newCompanyName} onChange={e => setNewCompanyName(e.target.value)} placeholder="e.g. Acme Technologies" required/></label><label>Website domain<input value={newCompanyDomain} onChange={e => setNewCompanyDomain(e.target.value)} placeholder="e.g. acme.com" required/></label><div className="modal-actions"><button type="button" className="button button-subtle" onClick={() => setManualAddOpen(false)}>Cancel</button><button type="submit" className="button button-primary">Add company</button></div></form></div>}
    {importOpen && <div className="modal-backdrop" onMouseDown={e => { if (e.target === e.currentTarget) setImportOpen(false); }}><section className="modal"><button className="modal-close" onClick={() => setImportOpen(false)}>×</button><span className="upload-icon">⇧</span><span className="eyebrow">COMPANY DIRECTORY</span><h2>Import companies</h2><p>Upload a CSV to add companies to your workspace. We’ll skip names already in your directory.</p><button className="dropzone" onClick={() => fileRef.current?.click()}><span>＋</span><b>{fileRows.length ? `${fileRows.length} new ${fileRows.length === 1 ? 'company' : 'companies'} ready to import` : csvSkipped ? 'No new companies in this file' : 'Choose a CSV file'}</b>{csvSkipped > 0 && <small>{csvSkipped} duplicate {csvSkipped === 1 ? 'name' : 'names'} will be skipped</small>}<small>company_name, website_domain, approved_email_domains</small></button><input ref={fileRef} type="file" accept=".csv,text/csv" hidden onChange={e => importCsv(e.target.files?.[0])}/>{fileRows.length > 0 && <div className="import-preview">{fileRows.slice(0, 3).map((r, i) => <div key={i}><span>{r[0]}</span><small>{r[1] || 'No website domain'}</small></div>)}</div>}<div className="modal-actions"><button className="button button-subtle" onClick={() => setImportOpen(false)}>Cancel</button><button className="button button-primary" disabled={!fileRows.length} onClick={confirmImport}>Import {fileRows.length || ''} companies</button></div></section></div>}
  </div>;
}
function Login({ email, setEmail, password, setPassword, error, busy, onSubmit }: { busy:boolean; email:string; setEmail:(value:string)=>void; password:string; setPassword:(value:string)=>void; error:string; onSubmit:(event:React.FormEvent<HTMLFormElement>)=>void }) { return <div className="login-shell"><div className="login-decoration"><div className="decor-orb orb-one"/><div className="decor-orb orb-two"/><div className="decor-grid"/><div className="login-quote"><span>✳</span><h2>Make work<br/>a little more <i>human.</i></h2><p>A better place for the conversations<br/>that make work, work.</p></div><div className="login-footer">Office Gossip · ADMIN CONSOLE</div></div><main className="login-main"><a className="login-brand" href="#login"><span className="brand-mark"><img src="/brand-mark.svg" alt="" /></span><span className="brand-name">office<span>gossip</span><small>ADMIN CONSOLE</small></span></a><form className="login-form" onSubmit={onSubmit}><span className="eyebrow">WELCOME BACK</span><h1>Sign in to your<br/>admin workspace</h1><p className="login-subtitle">Enter your administrator credentials to continue.</p><label>Email address<input type="email" autoComplete="username" placeholder="you@company.com" value={email} onChange={e => setEmail(e.target.value)} required/></label><label>Password<input type="password" autoComplete="current-password" placeholder="Enter your password" value={password} onChange={e => setPassword(e.target.value)} required/></label>{error && <div className="login-error" role="alert">{error}</div>}<button className="button button-primary login-submit" type="submit" disabled={busy}>{busy ? 'Signing in…' : 'Sign in'} <span>→</span></button><div className="login-secure"><span>◆</span> Secure administrator access</div></form><div className="login-bottom">© 2026 Office Gossip <span>·</span> Made for better workdays</div></main></div>; }
function Stat({ label, value, hint, icon, tone, onClick }: { label:string; value:string; hint:string; icon:string; tone:string; onClick?:()=>void }) { return <button className="stat-card" onClick={onClick}><span className={`stat-icon ${tone}`}>{icon}</span><span className="stat-label">{label}</span><strong>{value}</strong><small>{hint}</small></button>; }
function PageHeading({ eyebrow, title, detail, action }: { eyebrow:string; title:string; detail:string; action?:React.ReactNode }) { return <div className="page-heading"><div><span className="eyebrow">{eyebrow}</span><h1>{title}</h1><p>{detail}</p></div>{action}</div>; }
function Avatar({ name }: { name:string }) { const initials = name === 'Anonymous' ? 'AN' : name.split(' ').map(s => s[0]).slice(0,2).join('').toUpperCase(); return <span className={`avatar avatar-${(initials.charCodeAt(0) % 5) + 1}`}>{initials}</span>; }
function RequestRow({ item, approve, reject, compact = false }: { item:Request; approve:(r:Request)=>void; reject:(r:Request)=>void; compact?:boolean }) { return <div className={`request-row ${compact ? 'compact' : ''}`}><span className="company-monogram">{item.name.split(' ').map(w => w[0]).slice(0,2).join('').toUpperCase()}</span><div className="request-info"><b>{item.name}</b>{item.domain && <span>{item.domain}</span>}<small>Requested by {item.requester}{item.email && ` (${item.email})`}{item.others > 0 && ` and ${item.others} ${item.others === 1 ? 'other' : 'others'}`} · {formatDate(item.createdAt)}</small></div><div className="request-actions"><button className="button button-subtle" onClick={() => reject(item)}>Decline</button><button className="button button-primary" onClick={() => approve(item)}>Approve</button></div></div>; }
function CompanyTable({ companies, toggle, edit, compact = false }: { companies:Company[]; toggle:(c:Company)=>void; edit:(c:Company)=>void; compact?:boolean }) { return <table><thead><tr><th>COMPANY</th><th>MEMBERS</th><th>STATUS</th>{!compact && <th>WEBSITE DOMAIN</th>}<th></th></tr></thead><tbody>{companies.map(c => <tr key={c.id}><td><div className="company-cell"><span className="company-monogram">{c.name.split(' ').map(w=>w[0]).slice(0,2).join('').toUpperCase()}</span><b>{c.name}</b></div></td><td>{c.members.toLocaleString()}</td><td><span className={`status-pill ${c.status === 'Active' ? 'status-active' : 'status-disabled'}`}><i/>{c.status}</span></td>{!compact && <td>{c.domain}</td>}<td><button className="row-action" onClick={() => edit(c)}>Edit</button><button className="row-action" onClick={() => toggle(c)}>{c.status === 'Active' ? 'Disable' : 'Activate'} <span>⌄</span></button></td></tr>)}</tbody>{companies.length === 0 && <tfoot><tr><td colSpan={5}>No companies found.</td></tr></tfoot>}</table>; }
function Empty({ title, detail }: { title:string; detail:string }) { return <div className="empty-state"><span>✳</span><b>{title}</b><p>{detail}</p></div>; }

// Captured on document so repeat taps are dropped before React's root listeners run.
const REPEAT_GUARD_MS = 500;
const lastActivation = new WeakMap<EventTarget, number>();
function dropRepeatActivation(event: Event) {
  const target = event.type === 'submit' ? event.target : (event.target as Element | null)?.closest?.('button, a, [role="button"]');
  if (!target) return;
  const now = Date.now();
  if (now - (lastActivation.get(target) ?? 0) < REPEAT_GUARD_MS) { event.preventDefault(); event.stopImmediatePropagation(); return; }
  lastActivation.set(target, now);
}
document.addEventListener('click', dropRepeatActivation, true);
document.addEventListener('submit', dropRepeatActivation, true);

createRoot(document.getElementById('root')!).render(<React.StrictMode><App /></React.StrictMode>);
