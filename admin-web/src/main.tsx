import React, { useMemo, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import './style.css';
import './login.css';
import './updates.css';

type View = 'Overview' | 'Company requests' | 'Companies' | 'Memberships' | 'Updates' | 'Moderation';
type Request = { id: number; name: string; domain: string; requester: string; email: string; date: string };
type Company = { name: string; domain: string; members: number; status: 'Active' | 'Disabled' };
type Member = { name: string; email: string; company: string; method: string; date: string };
type Report = { id: number; company: string; author: string; initials: string; body: string; reason: string; date: string; reports: number };
type UpdateAudience = 'Everyone' | 'One user' | 'One company';
type AdminUpdate = { id: number; message: string; audience: UpdateAudience; target?: string; date: string };

const initialRequests: Request[] = [
  { id: 1, name: 'Northstar Studio', domain: 'northstar.design', requester: 'Maya Chen', email: 'maya@northstar.design', date: 'Today, 9:42 AM' },
  { id: 2, name: 'Fieldwork', domain: 'fieldwork.co', requester: 'Jordan Lee', email: 'jordan@fieldwork.co', date: 'Yesterday' },
  { id: 3, name: 'Monument Health', domain: 'monument.health', requester: 'Avery Brooks', email: 'avery@monument.health', date: 'Sep 25, 2026' },
];
const initialCompanies: Company[] = [
  { name: 'Acme Technologies', domain: 'acme.example', members: 284, status: 'Active' },
  { name: 'Brightside Labs', domain: 'brightside.io', members: 156, status: 'Active' },
  { name: 'Cedar & Co.', domain: 'cedar.co', members: 92, status: 'Active' },
  { name: 'Common Ground', domain: 'commonground.org', members: 68, status: 'Disabled' },
];
const initialMembers: Member[] = [
  { name: 'Sofia Patel', email: 'sofia.patel@acme.example', company: 'Acme Technologies', method: 'Admin approval', date: 'Today' },
  { name: 'Noah Williams', email: 'noah.w@brightside.io', company: 'Brightside Labs', method: 'Invite', date: 'Today' },
  { name: 'Isabella Kim', email: 'isabella.kim@cedar.co', company: 'Cedar & Co.', method: 'Request', date: 'Yesterday' },
];
const initialReports: Report[] = [
  { id: 1, company: 'Brightside Labs', author: 'Anonymous', initials: 'AN', body: 'A tough week on the launch, but the team pulled together and got it over the line. Proud of this crew. 🙌', reason: 'Harassment or bullying', date: '18 min ago', reports: 3 },
  { id: 2, company: 'Acme Technologies', author: 'Sam Rivera', initials: 'SR', body: 'Has anyone else had trouble getting reimbursed for travel expenses this month?', reason: 'Spam or misleading', date: '2 hours ago', reports: 1 },
  { id: 3, company: 'Cedar & Co.', author: 'Anonymous', initials: 'AN', body: 'Sharing a concern about how feedback was handled in our team meeting today.', reason: 'Inappropriate content', date: 'Yesterday', reports: 2 },
];
const navItems: { name: View; icon: string }[] = [
  { name: 'Overview', icon: '◫' }, { name: 'Company requests', icon: '↗' }, { name: 'Companies', icon: '▦' }, { name: 'Memberships', icon: '♙' }, { name: 'Updates', icon: '◉' }, { name: 'Moderation', icon: '⚑' },
];

function App() {
  const [loggedIn, setLoggedIn] = useState(() => sessionStorage.getItem('officegossip-admin-session') === 'active');
  const [loginEmail, setLoginEmail] = useState('');
  const [loginPassword, setLoginPassword] = useState('');
  const [loginError, setLoginError] = useState('');
  const [view, setView] = useState<View>('Overview');
  const [requests, setRequests] = useState(initialRequests);
  const [companies, setCompanies] = useState(initialCompanies);
  const [members, setMembers] = useState(initialMembers);
  const [reports, setReports] = useState(initialReports);
  const [updateMessage, setUpdateMessage] = useState('');
  const [updateAudience, setUpdateAudience] = useState<UpdateAudience>('Everyone');
  const [targetRecipient, setTargetRecipient] = useState('');
  const [sentUpdates, setSentUpdates] = useState<AdminUpdate[]>([]);
  const [query, setQuery] = useState('');
  const [notice, setNotice] = useState('');
  const [fileRows, setFileRows] = useState<string[][]>([]);
  const [importOpen, setImportOpen] = useState(false);
  const [manualAddOpen, setManualAddOpen] = useState(false);
  const [newCompanyName, setNewCompanyName] = useState('');
  const [newCompanyDomain, setNewCompanyDomain] = useState('');
  const fileRef = useRef<HTMLInputElement>(null);
  const filteredCompanies = useMemo(() => companies.filter(c => `${c.name} ${c.domain}`.toLowerCase().includes(query.toLowerCase())), [companies, query]);
  const filteredMembers = useMemo(() => members.filter(m => `${m.name} ${m.email} ${m.company}`.toLowerCase().includes(query.toLowerCase())), [members, query]);
  const pending = requests.length;
  const openReports = reports.length;
  function flash(message: string) { setNotice(message); window.setTimeout(() => setNotice(''), 3200); }
  function approveRequest(item: Request) {
    setRequests(list => list.filter(r => r.id !== item.id));
    setCompanies(list => [...list, { name: item.name, domain: item.domain, members: 1, status: 'Active' }]);
    flash(`${item.name} approved and added to the directory`);
  }
  function rejectRequest(item: Request) { setRequests(list => list.filter(r => r.id !== item.id)); flash(`${item.name} request declined`); }
  function approveAllRequests() {
    if (!requests.length) return;
    setCompanies(list => [...list, ...requests.filter(r => !list.some(c => c.name.toLowerCase() === r.name.toLowerCase())).map(r => ({ name: r.name, domain: r.domain, members: 1, status: 'Active' as const }))]);
    const count = requests.length;
    setRequests([]);
    flash(`${count} company ${count === 1 ? 'request' : 'requests'} approved`);
  }
  function signIn(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (loginEmail.trim().toLowerCase() === 'gossip@gmail.com' && loginPassword === '123456') {
      sessionStorage.setItem('officegossip-admin-session', 'active');
      setLoggedIn(true); setLoginError('');
    } else setLoginError('Email or password is incorrect.');
  }
  function signOut() { sessionStorage.removeItem('officegossip-admin-session'); setLoggedIn(false); }
  function sendUpdate(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const message = updateMessage.trim();
    const target = targetRecipient.trim();
    if (!message) return;
    if (updateAudience !== 'Everyone' && !target) { flash(updateAudience === 'One user' ? 'Enter the user email or username' : 'Choose a company'); return; }
    setSentUpdates(list => [{ id: Date.now(), message, audience: updateAudience, target: updateAudience === 'Everyone' ? undefined : target, date: 'Just now' }, ...list]);
    flash(updateAudience === 'Everyone' ? 'Update published to all users' : updateAudience === 'One company' ? `Update sent to ${target}` : `Update sent to ${target}`);
    setUpdateMessage(''); setTargetRecipient('');
  }
  if (!loggedIn) return <Login email={loginEmail} setEmail={setLoginEmail} password={loginPassword} setPassword={setLoginPassword} error={loginError} onSubmit={signIn} />;
  function importCsv(file?: File) {
    if (!file) return;
    if (!file.name.toLowerCase().endsWith('.csv')) { flash('Choose a .csv file to import'); return; }
    const reader = new FileReader();
    reader.onload = () => {
      const rows = String(reader.result ?? '').trim().split(/\r?\n/).map(row => row.split(',').map(cell => cell.trim().replace(/^"|"$/g, ''))).filter(row => row.length > 1);
      setFileRows(rows.slice(1).filter(row => row[0])); setImportOpen(true);
    };
    reader.readAsText(file);
  }
  function confirmImport() {
    const additions = fileRows.filter(row => !companies.some(company => company.name.toLowerCase() === row[0].toLowerCase())).map(row => ({ name: row[0], domain: row[1] || '—', members: 0, status: 'Active' as const }));
    setCompanies(list => [...list, ...additions]); setImportOpen(false); setFileRows([]); setView('Companies'); setQuery(''); flash(`${additions.length} ${additions.length === 1 ? 'company' : 'companies'} imported`);
  }
  function addCompanyManually(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const name = newCompanyName.trim();
    const domain = newCompanyDomain.trim().replace(/^https?:\/\//i, '').replace(/\/$/, '');
    if (companies.some(company => company.name.toLowerCase() === name.toLowerCase())) { flash('A company with this name already exists'); return; }
    setCompanies(list => [...list, { name, domain, members: 0, status: 'Active' }]);
    setNewCompanyName(''); setNewCompanyDomain(''); setManualAddOpen(false);
    flash(`${name} added to the company directory`);
  }
  function toggleCompany(company: Company) {
    setCompanies(list => list.map(c => c.name === company.name ? { ...c, status: c.status === 'Active' ? 'Disabled' : 'Active' } : c));
    flash(`${company.name} ${company.status === 'Active' ? 'disabled' : 'activated'}`);
  }
  function renderPage() {
    if (view === 'Overview') return <>
      <div className="welcome"><div><span className="eyebrow">MONDAY, SEPTEMBER 28, 2026</span><h1>Good morning, Honai <span>☀</span></h1><p>Here’s what’s happening across your community today.</p></div><button className="button button-primary" onClick={() => { setView('Companies'); setImportOpen(true); }}>＋ Add companies</button></div>
      <div className="stat-grid">
        <Stat label="Total companies" value={String(companies.filter(c => c.status === 'Active').length).padStart(2, '0')} hint="Across your workspace" icon="▦" tone="lavender" />
        <Stat label="Active members" value="1,248" hint="↑ 8.2% this month" icon="♙" tone="mint" />
        <Stat label="Requests to review" value={String(pending).padStart(2, '0')} hint={pending ? 'Needs your attention' : 'You’re all caught up'} icon="↗" tone="peach" onClick={() => setView('Company requests')} />
        <Stat label="Open reports" value={String(openReports).padStart(2, '0')} hint={openReports ? 'Keep the community safe' : 'No open reports'} icon="⚑" tone="blue" onClick={() => setView('Moderation')} />
      </div>
      <div className="overview-grid"><section className="panel activity-panel"><div className="panel-heading"><div><span className="eyebrow">NEEDS YOUR ATTENTION</span><h2>Review queue</h2></div><button className="text-button" onClick={() => setView('Company requests')}>View all <span>→</span></button></div>
        {requests.length ? requests.slice(0, 2).map(r => <RequestRow key={r.id} item={r} approve={approveRequest} reject={rejectRequest} compact />) : <Empty title="All clear" detail="No company requests need review." />}
        {reports.length > 0 && <div className="queue-report"><span className="report-icon">⚑</span><div><b>{reports[0].reports} reports need attention</b><small>{reports[0].reason} · {reports[0].company}</small></div><button className="icon-button" onClick={() => setView('Moderation')}>→</button></div>}
      </section><section className="panel snapshot"><div className="panel-heading"><div><span className="eyebrow">YOUR COMMUNITY</span><h2>At a glance</h2></div><span className="live-dot">Live</span></div><div className="snapshot-figure"><strong>1,248</strong><span>members across active companies</span></div><div className="bar-chart" aria-label="Members joining this week"><i style={{height:'36%'}}/><i style={{height:'54%'}}/><i style={{height:'45%'}}/><i style={{height:'68%'}}/><i style={{height:'58%'}}/><i style={{height:'83%'}}/><i style={{height:'100%'}}/></div><div className="chart-labels"><span>Mon</span><span>Tue</span><span>Wed</span><span>Thu</span><span>Fri</span><span>Sat</span><span>Sun</span></div><p className="chart-note"><span>↑ 12%</span> more members joined this week</p></section></div>
      <section className="panel recent-panel"><div className="panel-heading"><div><span className="eyebrow">LATEST</span><h2>Recently added companies</h2></div><button className="text-button" onClick={() => setView('Companies')}>Company directory <span>→</span></button></div><CompanyTable companies={companies.slice(0, 3)} toggle={toggleCompany} compact /></section>
    </>;
    if (view === 'Company requests') return <><PageHeading eyebrow="COMPANY ACCESS" title="Company requests" detail="Review requests from members who want to bring their company to OfficeGossip." /><div className="toolbar"><span className="count-pill">{requests.length} pending</span><span className="toolbar-hint">Approve all requests with one click</span>{requests.length > 0 && <button className="button button-primary" onClick={approveAllRequests}>✓ Approve all ({requests.length})</button>}</div><section className="panel request-list">{requests.length ? requests.map(r => <RequestRow key={r.id} item={r} approve={approveRequest} reject={rejectRequest} />) : <Empty title="You’re all caught up" detail="New company requests will show up here." />}</section></>;
    if (view === 'Companies') return <><PageHeading eyebrow="WORKSPACE" title="Company directory" detail="Manage the companies and communities in your workspace." action={<div className="company-heading-actions"><button className="button button-subtle" onClick={() => setManualAddOpen(true)}>＋ Add one manually</button><button className="button button-primary" onClick={() => { setImportOpen(true); setFileRows([]); }}>＋ Import companies</button></div>} /><div className="toolbar"><label className="search"><span>⌕</span><input placeholder="Search companies…" value={query} onChange={e => setQuery(e.target.value)} /></label><span className="toolbar-hint">{companies.length} companies</span></div><section className="panel table-panel"><CompanyTable companies={filteredCompanies} toggle={toggleCompany} /></section></>;
    if (view === 'Memberships') return <><PageHeading eyebrow="PEOPLE" title="Memberships" detail="Review member access and see how people joined their company community." /><div className="toolbar"><label className="search"><span>⌕</span><input placeholder="Search people or companies…" value={query} onChange={e => setQuery(e.target.value)} /></label><span className="toolbar-hint">{members.length} members</span></div><section className="panel table-panel"><table><thead><tr><th>MEMBER</th><th>COMPANY</th><th>JOINED VIA</th><th>DATE</th></tr></thead><tbody>{filteredMembers.map(m => <tr key={m.email}><td><div className="person-cell"><Avatar name={m.name}/><span><b>{m.name}</b><small>{m.email}</small></span></div></td><td>{m.company}</td><td><span className="method-pill">{m.method}</span></td><td>{m.date}</td></tr>)}</tbody></table>{filteredMembers.length === 0 && <Empty title="No members found" detail="Try a different search." />}</section></>;
    if (view === 'Updates') return <><PageHeading eyebrow="ANNOUNCEMENTS" title="Flash updates" detail="Send an update to everyone, one user, or one company." /><div className="updates-layout"><form className="panel update-composer" onSubmit={sendUpdate}><span className="compose-kicker">NEW UPDATE</span><label className="update-message-label" htmlFor="update-message">Message</label><textarea id="update-message" value={updateMessage} onChange={e => setUpdateMessage(e.target.value)} maxLength={500} placeholder="What would you like people to know?" required/><div className="compose-bottom"><span>{updateMessage.length}/500</span><span>Keep it clear and helpful</span></div><div className="audience-control"><div><b>Send to</b><small>Choose who should receive this update</small></div><select value={updateAudience} onChange={e => { setUpdateAudience(e.target.value as UpdateAudience); setTargetRecipient(''); }}><option>Everyone</option><option>One user</option><option>One company</option></select></div>{updateAudience === 'One user' && <label className="target-user-field">Target user<input value={targetRecipient} onChange={e => setTargetRecipient(e.target.value)} placeholder="Email address or username" required/><small>Use the account email or username of the recipient.</small></label>}{updateAudience === 'One company' && <label className="target-user-field">Target company<select value={targetRecipient} onChange={e => setTargetRecipient(e.target.value)} required><option value="">Choose a company</option>{companies.filter(company => company.status === 'Active').map(company => <option key={company.name} value={company.name}>{company.name}</option>)}</select><small>Only members of this active company will receive the update.</small></label>}<div className="audience-preview"><span>{updateAudience === 'Everyone' ? '◎' : updateAudience === 'One company' ? '▦' : '♙'}</span><div><b>{updateAudience === 'Everyone' ? 'All active users' : targetRecipient.trim() || (updateAudience === 'One user' ? 'One selected user' : 'One selected company')}</b><small>{updateAudience === 'Everyone' ? 'This announcement will be visible to the whole community.' : updateAudience === 'One company' ? 'Only members of the selected company will receive it.' : 'Only the selected user will receive this update.'}</small></div></div><button className="button button-primary publish-update" type="submit" disabled={!updateMessage.trim() || (updateAudience !== 'Everyone' && !targetRecipient.trim())}>↗ &nbsp;{updateAudience === 'Everyone' ? 'Publish to everyone' : updateAudience === 'One company' ? 'Send to company' : 'Send to user'}</button><p className="demo-note">Demo mode: updates appear in this dashboard only until the notification API is connected.</p></form><section className="updates-history"><div className="panel-heading"><div><span className="eyebrow">RECENT ACTIVITY</span><h2>Sent updates</h2></div><span className="history-count">{sentUpdates.length}</span></div>{sentUpdates.length ? sentUpdates.map(item => <article className="panel sent-update" key={item.id}><div><span className="update-audience-pill">{item.audience === 'Everyone' ? '◎ Everyone' : item.audience === 'One company' ? '▦ One company' : '♙ One user'}</span><small>{item.date}</small></div><p>{item.message}</p>{item.target && <small className="sent-target">To: {item.target}</small>}</article>) : <div className="panel"><Empty title="No updates yet" detail="Your published announcements will appear here." /></div>}</section></div></>;
    return <><PageHeading eyebrow="COMMUNITY SAFETY" title="Moderation queue" detail="Review reported posts and keep workplace conversations respectful." /><div className="toolbar"><span className="count-pill">{reports.length} open reports</span><span className="toolbar-hint">Reporter identities are kept private</span></div><div className="moderation-list">{reports.length ? reports.map(report => <article className="panel moderation-card" key={report.id}><div className="moderation-meta"><span className="company-chip">{report.company}</span><span>{report.date}</span><span className="report-count">⚑ {report.reports} {report.reports === 1 ? 'report' : 'reports'}</span></div><div className="post-author"><Avatar name={report.initials === 'AN' ? 'Anonymous' : report.author}/><div><b>{report.author}</b><small>Posted in {report.company}</small></div></div><blockquote>{report.body}</blockquote><div className="reason-line"><span>REPORTED FOR</span><b>{report.reason}</b></div><div className="moderation-actions"><button className="button button-subtle" onClick={() => { setReports(list => list.filter(x => x.id !== report.id)); flash('Report dismissed'); }}>Dismiss report</button><button className="button button-danger" onClick={() => { setReports(list => list.filter(x => x.id !== report.id)); flash('Post removed and report resolved'); }}>Remove post</button></div></article>) : <section className="panel"><Empty title="No open reports" detail="Reported posts will appear here for review." /></section>}</div></>;
  }
  return <div className="app-shell">
    <aside className="sidebar">
      <a className="brand" href="#overview" onClick={e => { e.preventDefault(); setView('Overview'); }}><span className="brand-mark">og</span><span className="brand-name">office<span>gossip</span><small>ADMIN CONSOLE</small></span></a>
      <div className="workspace-switch"><span className="workspace-mark">O</span><span><b>OfficeGossip</b><small>Workspace</small></span><span className="chevron">⌄</span></div>
      <div className="nav-label">WORKSPACE</div>
      <nav>{navItems.map(item => <button key={item.name} className={`nav-item ${view === item.name ? 'active' : ''}`} onClick={() => { setView(item.name); setQuery(''); }}><span className="nav-icon">{item.icon}</span>{item.name}{item.name === 'Company requests' && pending > 0 && <em>{pending}</em>}{item.name === 'Moderation' && openReports > 0 && <em className="nav-alert">{openReports}</em>}</button>)}</nav>
      <div className="sidebar-bottom"><div className="help-card"><div className="help-symbol">✳</div><b>Need a hand?</b><p>Find tips for managing your community.</p><button onClick={() => flash('Help center is coming soon')}>Visit help center <span>↗</span></button></div>
        <button className="profile-button" onClick={signOut}><span className="profile-avatar">H</span><span><b>Honai</b><small>Administrator · Sign out</small></span><span className="profile-dots">···</span></button>
      </div>
    </aside>
    <main className="main-area"><header className="topbar"><div className="breadcrumbs"><span>Workspace</span><span className="crumb-slash">/</span><b>{view}</b></div><div className="topbar-right"><span className="secure-label"><span>●</span> Admin workspace</span><button className="bell" aria-label="Notifications" onClick={() => flash('You’re all caught up')}>♧<i/></button><Avatar name="Honai"/></div></header>
      <div className="content">{renderPage()}<footer>OfficeGossip Admin <span>·</span> Built for better workdays</footer></div>
    </main>
    {notice && <div className="toast"><span>✓</span>{notice}</div>}
    {manualAddOpen && <div className="modal-backdrop" onMouseDown={e => { if (e.target === e.currentTarget) setManualAddOpen(false); }}><form className="modal manual-company-form" onSubmit={addCompanyManually}><button type="button" className="modal-close" onClick={() => setManualAddOpen(false)}>×</button><span className="upload-icon">＋</span><span className="eyebrow">COMPANY DIRECTORY</span><h2>Add one company</h2><p>Enter the company name and website domain to add it to your directory.</p><label>Company name<input autoFocus value={newCompanyName} onChange={e => setNewCompanyName(e.target.value)} placeholder="e.g. Acme Technologies" required/></label><label>Website domain<input value={newCompanyDomain} onChange={e => setNewCompanyDomain(e.target.value)} placeholder="e.g. acme.com" required/></label><div className="modal-actions"><button type="button" className="button button-subtle" onClick={() => setManualAddOpen(false)}>Cancel</button><button type="submit" className="button button-primary">Add company</button></div></form></div>}
    {importOpen && <div className="modal-backdrop" onMouseDown={e => { if (e.target === e.currentTarget) setImportOpen(false); }}><section className="modal"><button className="modal-close" onClick={() => setImportOpen(false)}>×</button><span className="upload-icon">⇧</span><span className="eyebrow">COMPANY DIRECTORY</span><h2>Import companies</h2><p>Upload a CSV to add companies to your workspace. We’ll skip names already in your directory.</p><button className="dropzone" onClick={() => fileRef.current?.click()}><span>＋</span><b>{fileRows.length ? `${fileRows.length} companies ready to import` : 'Choose a CSV file'}</b><small>company_name, website_domain, approved_email_domains</small></button><input ref={fileRef} type="file" accept=".csv,text/csv" hidden onChange={e => importCsv(e.target.files?.[0])}/>{fileRows.length > 0 && <div className="import-preview">{fileRows.slice(0, 3).map((r, i) => <div key={i}><span>{r[0]}</span><small>{r[1] || 'No website domain'}</small></div>)}</div>}<div className="modal-actions"><button className="button button-subtle" onClick={() => setImportOpen(false)}>Cancel</button><button className="button button-primary" disabled={!fileRows.length} onClick={confirmImport}>Import {fileRows.length || ''} companies</button></div></section></div>}
  </div>;
}
function Login({ email, setEmail, password, setPassword, error, onSubmit }: { email:string; setEmail:(value:string)=>void; password:string; setPassword:(value:string)=>void; error:string; onSubmit:(event:React.FormEvent<HTMLFormElement>)=>void }) { return <div className="login-shell"><div className="login-decoration"><div className="decor-orb orb-one"/><div className="decor-orb orb-two"/><div className="decor-grid"/><div className="login-quote"><span>✳</span><h2>Make work<br/>a little more <i>human.</i></h2><p>A better place for the conversations<br/>that make work, work.</p></div><div className="login-footer">OFFICEGOSSIP · ADMIN CONSOLE</div></div><main className="login-main"><a className="login-brand" href="#login"><span className="brand-mark">og</span><span className="brand-name">office<span>gossip</span><small>ADMIN CONSOLE</small></span></a><form className="login-form" onSubmit={onSubmit}><span className="eyebrow">WELCOME BACK</span><h1>Sign in to your<br/>admin workspace</h1><p className="login-subtitle">Enter your administrator credentials to continue.</p><label>Email address<input type="email" autoComplete="username" placeholder="you@company.com" value={email} onChange={e => setEmail(e.target.value)} required/></label><label>Password<input type="password" autoComplete="current-password" placeholder="Enter your password" value={password} onChange={e => setPassword(e.target.value)} required/></label>{error && <div className="login-error" role="alert">{error}</div>}<button className="button button-primary login-submit" type="submit">Sign in <span>→</span></button><div className="login-secure"><span>◆</span> Secure administrator access</div></form><div className="login-bottom">© 2026 OfficeGossip <span>·</span> Made for better workdays</div></main></div>; }
function Stat({ label, value, hint, icon, tone, onClick }: { label:string; value:string; hint:string; icon:string; tone:string; onClick?:()=>void }) { return <button className="stat-card" onClick={onClick}><span className={`stat-icon ${tone}`}>{icon}</span><span className="stat-label">{label}</span><strong>{value}</strong><small>{hint}</small></button>; }
function PageHeading({ eyebrow, title, detail, action }: { eyebrow:string; title:string; detail:string; action?:React.ReactNode }) { return <div className="page-heading"><div><span className="eyebrow">{eyebrow}</span><h1>{title}</h1><p>{detail}</p></div>{action}</div>; }
function Avatar({ name }: { name:string }) { const initials = name === 'Anonymous' ? 'AN' : name.split(' ').map(s => s[0]).slice(0,2).join('').toUpperCase(); return <span className={`avatar avatar-${(initials.charCodeAt(0) % 5) + 1}`}>{initials}</span>; }
function RequestRow({ item, approve, reject, compact = false }: { item:Request; approve:(r:Request)=>void; reject:(r:Request)=>void; compact?:boolean }) { return <div className={`request-row ${compact ? 'compact' : ''}`}><span className="company-monogram">{item.name.split(' ').map(w => w[0]).slice(0,2).join('').toUpperCase()}</span><div className="request-info"><b>{item.name}</b><span>{item.domain}</span><small>Requested by {item.requester} · {item.date}</small></div><div className="request-actions"><button className="button button-subtle" onClick={() => reject(item)}>Decline</button><button className="button button-primary" onClick={() => approve(item)}>Approve</button></div></div>; }
function CompanyTable({ companies, toggle, compact = false }: { companies:Company[]; toggle:(c:Company)=>void; compact?:boolean }) { return <table><thead><tr><th>COMPANY</th><th>MEMBERS</th><th>STATUS</th>{!compact && <th>WEBSITE DOMAIN</th>}<th></th></tr></thead><tbody>{companies.map(c => <tr key={c.name}><td><div className="company-cell"><span className="company-monogram">{c.name.split(' ').map(w=>w[0]).slice(0,2).join('').toUpperCase()}</span><b>{c.name}</b></div></td><td>{c.members.toLocaleString()}</td><td><span className={`status-pill ${c.status === 'Active' ? 'status-active' : 'status-disabled'}`}><i/>{c.status}</span></td>{!compact && <td>{c.domain}</td>}<td><button className="row-action" onClick={() => toggle(c)}>{c.status === 'Active' ? 'Disable' : 'Activate'} <span>⌄</span></button></td></tr>)}</tbody>{companies.length === 0 && <tfoot><tr><td colSpan={5}>No companies found.</td></tr></tfoot>}</table>; }
function Empty({ title, detail }: { title:string; detail:string }) { return <div className="empty-state"><span>✳</span><b>{title}</b><p>{detail}</p></div>; }

createRoot(document.getElementById('root')!).render(<React.StrictMode><App /></React.StrictMode>);
