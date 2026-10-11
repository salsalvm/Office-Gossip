import React, { useEffect, useState } from 'react';
import { ACCESS_TOKEN_KEY, ApiError, api, clearStoredSession, hasAuthMessage, storeSession } from './api';
import { SUPPORT_EMAIL } from './legal';
import './account.css';

// Public URL for app-store listings and the legal pages; signed-in members also find it under Profile.
export const DELETE_ACCOUNT_PATH = 'delete-account';
export const DELETE_ACCOUNT_ALIASES = ['account-deletion', 'delete'];

const DELETE_REASONS = ['I don’t use Office Gossip anymore', 'I have privacy concerns', 'I changed jobs', 'Too many notifications', 'Something else'];
const longDate = (iso: string | null) => iso ? new Date(iso).toLocaleDateString([], { month: 'long', day: 'numeric', year: 'numeric' }) : '';
const daysUntil = (iso: string | null) => iso ? Math.max(0, Math.ceil((Date.parse(iso) - Date.now()) / 86_400_000)) : 0;

export type DeactivatedAccount = { message: string; canRestore: boolean; email: string | null; deactivatedAt: string | null; purgeAfter: string | null };
type AuthResult = { accessToken: string; refreshToken?: string };
type DeletionResult = { purgeAfter: string | null; graceDays: number };

// Sign-in with valid credentials for a deleted account answers 403 + data.code instead of a session.
export function deactivatedAccountFrom(error: unknown): DeactivatedAccount | null {
  if (!(error instanceof ApiError) || error.status !== 403 || error.data.code !== 'ACCOUNT_DEACTIVATED') return null;
  const text = (value: unknown) => typeof value === 'string' ? value : null;
  return { message: error.message, canRestore: error.data.canRestore === true, email: text(error.data.email), deactivatedAt: text(error.data.deactivatedAt), purgeAfter: text(error.data.purgeAfter) };
}

function useGraceDays() {
  const [days, setDays] = useState(30);
  useEffect(() => { api<{ graceDays: number }>('/api/public/account-policy').then(policy => setDays(policy.graceDays)).catch(() => {}); }, []);
  return days;
}

const requestDeletion = (password: string, reason: string, accessToken?: string) => api<DeletionResult>('/api/me/account', {
  method: 'DELETE',
  body: JSON.stringify({ password, ...(reason ? { reason } : {}) }),
  ...(accessToken ? { headers: { Authorization: `Bearer ${accessToken}` } } : {}),
});

function DeletionFields({ password, setPassword, reason, setReason, acknowledged, setAcknowledged, graceDays, disabled }: {
  password: string; setPassword: (value: string) => void; reason: string; setReason: (value: string) => void;
  acknowledged: boolean; setAcknowledged: (value: boolean) => void; graceDays: number; disabled: boolean;
}) {
  return <>
    <label className="account-field">Password<input type="password" autoComplete="current-password" value={password} onChange={e => setPassword(e.target.value)} placeholder="Confirm it’s you" disabled={disabled} required/></label>
    <label className="account-field">Why are you leaving? <small>Optional</small><select value={reason} onChange={e => setReason(e.target.value)} disabled={disabled}><option value="">Prefer not to say</option>{DELETE_REASONS.map(item => <option key={item}>{item}</option>)}</select></label>
    <label className="account-ack"><input type="checkbox" checked={acknowledged} onChange={e => setAcknowledged(e.target.checked)} disabled={disabled}/><span>I understand my account will be hidden right away and permanently deleted after {graceDays} days unless I sign in again to restore it.</span></label>
  </>;
}

function Consequences({ graceDays }: { graceDays: number }) {
  return <ul className="account-consequences">
    <li><b>Right away</b> your profile, posts and comments are hidden and you’re signed out on every device.</li>
    <li><b>For {graceDays} days</b> you can change your mind — just sign in again and choose <i>Restore account</i>.</li>
    <li><b>After that</b> your profile, posts, comments, reactions and followers are permanently erased.</li>
  </ul>;
}

export function DeleteAccountDialog({ email, onDeleted, onClose }: { email: string; onDeleted: (result: DeletionResult) => void; onClose: () => void }) {
  const graceDays = useGraceDays();
  const [password, setPassword] = useState('');
  const [reason, setReason] = useState('');
  const [acknowledged, setAcknowledged] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => { if (event.key === 'Escape' && !busy) onClose(); };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [busy, onClose]);
  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true); setError('');
    try { onDeleted(await requestDeletion(password, reason)); }
    catch (failure) { setError(hasAuthMessage(failure) ? failure.message : 'Could not delete your account. Please try again.'); setBusy(false); }
  }
  return <div className="modal-shade" onMouseDown={e => { if (e.currentTarget === e.target && !busy) onClose(); }}>
    <form className="confirm-dialog account-dialog" role="alertdialog" aria-modal="true" aria-labelledby="delete-account-title" onSubmit={submit}>
      <span className="confirm-dialog-icon" aria-hidden="true">⊘</span>
      <h2 id="delete-account-title">Delete your account?</h2>
      <p>You’re signed in as <b>{email}</b>.</p>
      <Consequences graceDays={graceDays}/>
      <DeletionFields password={password} setPassword={setPassword} reason={reason} setReason={setReason} acknowledged={acknowledged} setAcknowledged={setAcknowledged} graceDays={graceDays} disabled={busy}/>
      {error && <p className="verify-error" role="alert">{error}</p>}
      <div className="confirm-dialog-actions"><button type="button" className="confirm-cancel" autoFocus disabled={busy} onClick={onClose}>Keep account</button><button type="submit" className="confirm-danger" disabled={busy || !password || !acknowledged}>{busy ? 'Deleting…' : 'Delete account'}</button></div>
    </form>
  </div>;
}

export function RestoreAccountDialog({ account, email, password, onRestored, onClose }: { account: DeactivatedAccount; email: string; password: string; onRestored: (result: AuthResult) => void; onClose: () => void }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const daysLeft = daysUntil(account.purgeAfter);
  async function restore() {
    setBusy(true); setError('');
    try { onRestored(await api<AuthResult>('/api/auth/restore', { method: 'POST', body: JSON.stringify({ email, password }) })); }
    catch (failure) { setError(hasAuthMessage(failure) ? failure.message : 'Could not restore your account. Please try again.'); setBusy(false); }
  }
  return <div className="modal-shade" onMouseDown={e => { if (e.currentTarget === e.target && !busy) onClose(); }}>
    <div className="confirm-dialog account-dialog" role="alertdialog" aria-modal="true" aria-labelledby="restore-title">
      <span className={`confirm-dialog-icon ${account.canRestore ? 'restore-icon' : ''}`} aria-hidden="true">{account.canRestore ? '↺' : '⊘'}</span>
      {account.canRestore ? <>
        <h2 id="restore-title">Welcome back! Restore your account?</h2>
        <p><b>{account.email ?? email}</b> was deleted{account.deactivatedAt ? ` on ${longDate(account.deactivatedAt)}` : ''}. It will be permanently erased on <b>{longDate(account.purgeAfter)}</b> — {daysLeft} {daysLeft === 1 ? 'day' : 'days'} from now.</p>
        <p className="account-note">Restoring brings back your profile, posts, comments and company membership exactly as you left them.</p>
      </> : <>
        <h2 id="restore-title">Account deactivated</h2>
        <p>{account.message}</p>
        <p className="account-note">Reach us at <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>.</p>
      </>}
      {error && <p className="verify-error" role="alert">{error}</p>}
      <div className="confirm-dialog-actions">
        <button type="button" className="confirm-cancel" disabled={busy} onClick={onClose}>{account.canRestore ? 'Not now' : 'Close'}</button>
        {account.canRestore && <button type="button" className="confirm-primary" autoFocus disabled={busy} onClick={() => void restore()}>{busy ? 'Restoring…' : 'Restore account'}</button>}
      </div>
    </div>
  </div>;
}

// Standalone page: works signed in (this browser's session) or with email + password.
export function DeleteAccountPage() {
  const graceDays = useGraceDays();
  const [signedInEmail, setSignedInEmail] = useState<string | null>(null);
  const [checking, setChecking] = useState(() => Boolean(localStorage.getItem(ACCESS_TOKEN_KEY)));
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [reason, setReason] = useState('');
  const [acknowledged, setAcknowledged] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [deactivated, setDeactivated] = useState<DeactivatedAccount | null>(null);
  const [done, setDone] = useState<DeletionResult | null>(null);
  useEffect(() => {
    if (!checking) return;
    api<{ email: string }>('/api/me').then(me => setSignedInEmail(me.email)).catch(() => {}).finally(() => setChecking(false));
  }, [checking]);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true); setError('');
    try {
      if (signedInEmail) setDone(await requestDeletion(password, reason));
      else {
        const session = await api<AuthResult>('/api/auth/login', { method: 'POST', body: JSON.stringify({ email: email.trim(), password }) });
        setDone(await requestDeletion(password, reason, session.accessToken));
      }
      clearStoredSession();
    } catch (failure) {
      const account = deactivatedAccountFrom(failure);
      if (account) setDeactivated(account);
      else setError(hasAuthMessage(failure) ? failure.message : 'Could not delete the account. Please try again.');
    } finally { setBusy(false); }
  }

  const deletionDate = done?.purgeAfter ? longDate(done.purgeAfter) : null;
  return <div className="legal-page">
    <header className="legal-top"><a className="legal-brand" href="/"><span className="member-mark"><img src="/brand-mark.svg" alt="" /></span><span>office<span>gossip</span></span></a><nav><a href="/privacy">Privacy</a><a href="/contact">Help &amp; contact</a></nav></header>
    <main className="legal-body">
      <span className="overline">ACCOUNT DELETION</span>
      <h1>Delete your Office Gossip account</h1>
      <p className="legal-intro">You can delete your account here, from <b>Profile → Delete account</b> in the app, or by emailing <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a> from the address on your account.</p>
      {done ? <section className="delete-page-card done" role="status">
        <span className="delete-page-icon" aria-hidden="true">✓</span>
        <h2>Your account is scheduled for deletion</h2>
        <p>It’s hidden from the community and signed out everywhere. {deletionDate ? <>It will be permanently erased on <b>{deletionDate}</b>.</> : 'It will be permanently erased soon.'}</p>
        <p>Changed your mind? Sign in with the same email and password before then and choose <b>Restore account</b>.</p>
        <a className="delete-page-link" href="/">Back to Office Gossip</a>
      </section> : <section className="delete-page-card">
        <h2>What happens when you delete</h2>
        <Consequences graceDays={graceDays}/>
        {checking ? <p className="account-note">Checking your session…</p> : <form className="delete-page-form" onSubmit={submit}>
          {signedInEmail
            ? <p className="account-note">Signed in on this browser as <b>{signedInEmail}</b>. <button type="button" className="account-link" onClick={() => setSignedInEmail(null)}>Use a different account</button></p>
            : <label className="account-field">Email address<input type="email" autoComplete="email" value={email} onChange={e => setEmail(e.target.value)} placeholder="you@company.com" disabled={busy} required/></label>}
          <DeletionFields password={password} setPassword={setPassword} reason={reason} setReason={setReason} acknowledged={acknowledged} setAcknowledged={setAcknowledged} graceDays={graceDays} disabled={busy}/>
          {error && <p className="verify-error" role="alert">{error}</p>}
          <button type="submit" className="confirm-danger delete-page-submit" disabled={busy || !password || !acknowledged || (!signedInEmail && !email.trim())}>{busy ? 'Deleting…' : 'Delete my account'}</button>
        </form>}
      </section>}
      <section><h2>What we keep</h2><p>After the permanent deletion we keep only a minimal audit record — your account ID, email address and the dates it was deleted — plus anything the law requires us to retain.</p></section>
    </main>
    <footer className="legal-foot">Office Gossip · A kinder corner of the internet</footer>
    {deactivated && <RestoreAccountDialog account={deactivated} email={signedInEmail ?? email.trim()} password={password} onClose={() => setDeactivated(null)} onRestored={session => { storeSession(session.accessToken, session.refreshToken); window.location.replace('/'); }}/>}
  </div>;
}
