import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import './style.css';
import { listenForPushMessages, removeWebPushToken, requestWebPushToken } from './push';
import { LEGAL_ALIASES, LEGAL_PATHS, LegalPage } from './legal';
import { API_URL, api, clearStoredSession, hasAuthMessage, isRejectedSession } from './api';
import { DELETE_ACCOUNT_ALIASES, DELETE_ACCOUNT_PATH, DeleteAccountDialog, DeleteAccountPage, RestoreAccountDialog, deactivatedAccountFrom, type DeactivatedAccount } from './account';

type Tab = 'Home' | 'Trending' | 'People' | 'Profile';
type Post = { id: string | number; person: string; role: string; company: string; time: string; body: string; likes: number; comments: number; anonymous?: boolean; liked?: boolean; tag?: string; isOwner?: boolean; isDeleted?: boolean; isArchived?: boolean; isAdmin?: boolean; isPending?: boolean; createdAt?: string };
type PostOptionId = 'copy' | 'edit' | 'archive' | 'delete' | 'report';
type PostDialog = { type: 'edit' | 'delete' | 'report'; post: Post };
// Entries in a post's three-dot menu. Add one here, then handle its id in App's `handlePostOption`.
const POST_OPTIONS: { id: PostOptionId; label: string | ((post: Post) => string); icon: string; danger?: boolean; visible: (post: Post) => boolean }[] = [
  { id: 'copy', label: 'Copy text', icon: '⧉', visible: () => true },
  { id: 'edit', label: 'Edit post', icon: '✎', visible: post => Boolean(post.isOwner) },
  { id: 'archive', label: post => post.isArchived ? 'Unarchive post' : 'Archive post', icon: '▤', visible: post => Boolean(post.isOwner) },
  { id: 'delete', label: 'Delete post', icon: '🗑', danger: true, visible: post => Boolean(post.isOwner) },
  { id: 'report', label: 'Report post', icon: '⚑', danger: true, visible: () => true },
];
const REPORT_REASONS = ['Harassment or bullying', 'Hate speech', 'Spam or misleading', 'Shares private information', 'Something else'];
const POST_STARTERS = [{ label: '✨ A team win', text: 'A small win from my team this week: ' }, { label: '💬 A question', text: 'Quick question for everyone: ' }, { label: '👏 A shoutout', text: 'Shoutout to ' }, { label: '💡 An idea', text: 'An idea I’d love your thoughts on: ' }];
type Person = { id: string; name: string; role: string; team: string; color?: string; following?: boolean };
type MemberUser = { id: string; name: string; emailVerified?: boolean; company: { id: string; name: string; website: string | null } | null; companyVerified?: boolean; companyRequestPending: boolean; pendingCompanyName: string | null; requestedCompany?: { name: string; website: string | null } | null };
type MemberData = { email: string; profile: { display_name: string; role_title: string | null; bio: string | null; theme_preference: 'system'|'light'|'dark'; created_at: string }; company: { name: string } | null; preferences: { comments: boolean; reactions: boolean; company_updates: boolean }; stats: { posts: number; reactions: number; comments: number }; user?: MemberUser };
type ActivityItem = { id: string; type: 'reaction' | 'comment' | 'follow'; actorName: string; postId: string | null; postExcerpt: string; comment: string | null; time: string; unread: boolean };
type Announcement = { id: string; message: string; audience: 'everyone' | 'company' | 'user'; time: string };
const ANNOUNCEMENT_AUDIENCE: Record<Announcement['audience'], string> = { everyone: 'For everyone', company: 'For your company', user: 'Just for you' };
const ANDROID_APP_URL = import.meta.env.VITE_ANDROID_APP_URL || 'https://play.google.com/store/apps/details?id=com.tabletalk.officegossip';
const IOS_APP_URL = import.meta.env.VITE_IOS_APP_URL || 'https://apps.apple.com/search?term=office%20gossip';
const APP_PROMO_KEY = 'officegossip_app_promo_dismissed';
const WEB_URL = (import.meta.env.VITE_WEB_URL || window.location.origin).replace(/\/$/, '');
type Webpage = { title: string; url: string };
const WEBPAGES = [
  { path: 'contact', title: 'Help & contact', short: 'Help & contact', detail: 'FAQs and get in touch with our team', icon: '?' },
  { path: 'privacy', title: 'Privacy policy', short: 'Privacy', detail: 'How we handle your data', icon: '⛉' },
  { path: 'terms', title: 'Terms & conditions', short: 'Terms', detail: 'Rules for using Office Gossip', icon: '▤' },
].map(page => ({ ...page, url: `${WEB_URL}/${page.path}` }));
// Mirrors the API default for requested companies: "Acme Labs" → "acmelabs.com".
const defaultCompanyDomain = (name: string) => { const slug = name.trim().toLowerCase().replace(/[^a-z0-9]/g, ''); return slug ? `${slug}.com` : ''; };
// A pending company request still allows posting; the API holds those posts until approval.
const canPost = (user?: MemberUser) => !user || (Boolean(user.name.trim()) && (Boolean(user.company) || Boolean(user.companyRequestPending)));
const companyVerified = (user?: MemberUser) => Boolean(user?.companyVerified ?? user?.company);
const companyStatusText = (user: MemberUser) => user.company?.name || (user.companyRequestPending ? `${user.pendingCompanyName} · awaiting approval` : 'Choose your company');
const FEED_PAGE_SIZE = 20;
// Email OTP verification UI (sign-up + Profile).
const EMAIL_OTP_ENABLED = true;
// Comment button on posts; hidden until comments are built.
const COMMENTS_ENABLED = false;
const GOOGLE_AUTH_ENABLED = false;
type FeedPage = { posts: Post[]; cursor: string | null; hasMore: boolean };
type FeedSort = 'latest' | 'trending';
// Soft-deleted posts still come back from the feed (flagged), so hide them here but keep them for the cursor.
// Latest pages by the last post's `createdAt`; Trending is a single top list ranked on the server.
async function fetchFeedPage(scope: string, sort: FeedSort, cursor?: string | null): Promise<FeedPage> {
  if (sort === 'trending') {
    const top = await api<Post[]>(`/api/community/feed?scope=${scope}&sort=trending&limit=${TRENDING_LIMIT}`);
    return { posts: top.filter(post => !post.isDeleted), cursor: null, hasMore: false };
  }
  const page = await api<Post[]>(`/api/community/feed?scope=${scope}&limit=${FEED_PAGE_SIZE}${cursor ? `&before=${encodeURIComponent(cursor)}` : ''}`);
  return { posts: page.filter(post => !post.isDeleted), cursor: page.at(-1)?.createdAt ?? cursor ?? null, hasMore: page.length === FEED_PAGE_SIZE };
}

const nav: { tab: Tab; icon: string }[] = [{ tab: 'Home', icon: '⌂' }, { tab: 'Trending', icon: '↗' }, { tab: 'People', icon: '♧' }, { tab: 'Profile', icon: '◉' }];
const MIN_TREND_INTERACTIONS = 2;
const TRENDING_WINDOW_DAYS = 3;
const TRENDING_LIMIT = 10;
function FeedPager({ hasMore, loading, onLoadMore }: { hasMore: boolean; loading: boolean; onLoadMore: () => void }) {
  const sentinel = useRef<HTMLDivElement>(null);
  const latest = useRef(onLoadMore);
  latest.current = onLoadMore;
  useEffect(() => {
    const node = sentinel.current;
    if (!node || !hasMore || loading || typeof IntersectionObserver === 'undefined') return;
    const observer = new IntersectionObserver(entries => { if (entries.some(entry => entry.isIntersecting)) latest.current(); }, { rootMargin: '400px 0px' });
    observer.observe(node);
    return () => observer.disconnect();
  }, [hasMore, loading]);
  if (!hasMore) return <p className="feed-end">You’re all caught up ✨</p>;
  return <div ref={sentinel} className="feed-pager">{loading ? <span className="feed-pager-spinner" aria-label="Loading more posts"/> : <button type="button" onClick={onLoadMore}>Load more posts</button>}</div>;
}
function BellIcon() {
  return <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/></svg>;
}
function GlobeIcon() {
  return <svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true"><path fill="currentColor" d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 17.93c-3.95-.49-7-3.85-7-7.93 0-.62.08-1.21.21-1.79L9 15v1c0 1.1.9 2 2 2v1.93zm6.9-2.54c-.26-.81-1-1.39-1.9-1.39h-1v-3c0-.55-.45-1-1-1H8v-2h2c.55 0 1-.45 1-1V7h2c1.1 0 2-.9 2-2v-.41c2.93 1.19 5 4.06 5 7.41 0 2.08-.8 3.97-2.1 5.39z"/></svg>;
}
function BusinessIcon() {
  return <svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true"><path fill="currentColor" d="M12 7V3H2v18h20V7H12zM6 19H4v-2h2v2zm0-4H4v-2h2v2zm0-4H4V9h2v2zm0-4H4V5h2v2zm4 12H8v-2h2v2zm0-4H8v-2h2v2zm0-4H8V9h2v2zm0-4H8V5h2v2zm10 12h-8v-2h2v-2h-2v-2h2v-2h-2V9h8v10zm-2-8h-2v2h2v-2zm0 4h-2v2h2v-2z"/></svg>;
}
const NAV_ICON_PATHS: Record<Tab, string> = {
  Home: 'M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z',
  Trending: 'M13.5.67s.74 2.65.74 4.8c0 2.06-1.35 3.73-3.41 3.73-2.07 0-3.63-1.67-3.63-3.73l.03-.36C5.21 7.51 4 10.62 4 14c0 4.42 3.58 8 8 8s8-3.58 8-8C20 8.61 17.41 3.8 13.5.67z',
  People: 'M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5s-3 1.34-3 3 1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5zm8 0c-.29 0-.62.02-.97.05 1.16.84 1.97 1.97 1.97 3.45V19h6v-2.5c0-2.33-4.67-3.5-7-3.5z',
  Profile: 'M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z',
};
function NavIcon({ tab, filled }: { tab: Tab; filled: boolean }) {
  return <svg viewBox="-1 -1 26 26" width="22" height="22" aria-hidden="true"><path d={NAV_ICON_PATHS[tab]} fill={filled ? 'currentColor' : 'none'} stroke="currentColor" strokeWidth={filled ? 0 : 1.8} strokeLinejoin="round"/></svg>;
}
// Runs one request per key at a time; repeat calls while it is pending are ignored.
function useInFlight() {
  const pending = useRef(new Set<string>());
  const [, rerender] = useState(0);
  const run = useCallback(async (key: string, task: () => Promise<void>) => {
    if (pending.current.has(key)) return;
    pending.current.add(key); rerender(n => n + 1);
    try { await task(); } finally { pending.current.delete(key); rerender(n => n + 1); }
  }, []);
  const busy = useCallback((key: string) => pending.current.has(key), []);
  return { run, busy };
}

function App() {
  const { run, busy } = useInFlight();
  const [accessToken, setAccessToken] = useState<string | null>(() => window.location.pathname === '/reset-password' ? null : localStorage.getItem('officegossip_access_token'));
  const [tab, setTab] = useState<Tab>('Home');
  const [feedScope, setFeedScope] = useState<'global' | 'company'>('global');
  const [scopeMenuOpen, setScopeMenuOpen] = useState(false);
  const [posts, setPosts] = useState<Post[]>([]);
  const [feedSort, setFeedSort] = useState<FeedSort>('latest');
  const [people, setPeople] = useState<Person[]>([]);
  const [feedState, setFeedState] = useState<'loading'|'ready'|'error'>('loading');
  const [feedCursor, setFeedCursor] = useState<string | null>(null);
  const [hasMorePosts, setHasMorePosts] = useState(false);
  const [loadingMorePosts, setLoadingMorePosts] = useState(false);
  const feedRequest = useRef(0);
  const [peopleState, setPeopleState] = useState<'loading'|'ready'|'error'>('loading');
  const [search, setSearch] = useState('');
  const [draft, setDraft] = useState('');
  const [anonymous, setAnonymous] = useState(true);
  const [composerOpen, setComposerOpen] = useState(false);
  const [notice, setNotice] = useState('');
  const [pushEnabled, setPushEnabled] = useState(false);
  const [memberData, setMemberData] = useState<MemberData | null>(null);
  const [profileEditing, setProfileEditing] = useState(false);
  const [profileDraft, setProfileDraft] = useState({ displayName: '', roleTitle: '', bio: '' });
  const [profileSaving, setProfileSaving] = useState(false);
  const [postDialog, setPostDialog] = useState<PostDialog | null>(null);
  const [editDraft, setEditDraft] = useState('');
  const [reportReason, setReportReason] = useState(REPORT_REASONS[0]);
  const [postActionBusy, setPostActionBusy] = useState(false);
  const [announcements, setAnnouncements] = useState<Announcement[]>([]);
  const [activity, setActivity] = useState<ActivityItem[]>([]);
  const [activityState, setActivityState] = useState<'loading' | 'ready' | 'error'>('loading');
  const [unreadCount, setUnreadCount] = useState(0);
  const [activityOpen, setActivityOpen] = useState(false);
  const [dismissedAnnouncements, setDismissedAnnouncements] = useState<string[]>([]);
  const [postingGateOpen, setPostingGateOpen] = useState(false);
  const [companyPickerOpen, setCompanyPickerOpen] = useState(false);
  const [checkingProfile, setCheckingProfile] = useState(false);
  const [showAppPromo, setShowAppPromo] = useState(() => localStorage.getItem(APP_PROMO_KEY) !== '1');
  function dismissAppPromo() { localStorage.setItem(APP_PROMO_KEY, '1'); setShowAppPromo(false); }
  // Set when a setup step starts from the posting gate, so finishing it continues to the composer.
  const gateStarter = useRef<string | undefined>(undefined);
  const resumeCompose = useRef<{ starter?: string } | null>(null);
  useEffect(() => { if (!profileEditing && !companyPickerOpen) resumeCompose.current = null; }, [profileEditing, companyPickerOpen]);
  function takeResume() { const resume = resumeCompose.current; resumeCompose.current = null; return resume; }
  const [webpage, setWebpage] = useState<Webpage | null>(null);
  const [signOutOpen, setSignOutOpen] = useState(false);
  const [deleteAccountOpen, setDeleteAccountOpen] = useState(false);
  const [authNotice, setAuthNotice] = useState('');
  const [verifyOpen, setVerifyOpen] = useState(false);
  const [verifyCode, setVerifyCode] = useState('');
  const [verifyBusy, setVerifyBusy] = useState<'sending' | 'checking' | null>(null);
  const [verifyError, setVerifyError] = useState('');
  const [resendIn, setResendIn] = useState(0);
  const [verifyNudge, setVerifyNudge] = useState(false);
  const emailUnverified = Boolean(memberData?.user) && memberData?.user?.emailVerified !== true;
  useEffect(() => {
    if (!EMAIL_OTP_ENABLED || tab !== 'Profile' || !emailUnverified) { setVerifyNudge(false); return; }
    setVerifyNudge(true);
    const timer = window.setTimeout(() => setVerifyNudge(false), 15000);
    return () => window.clearTimeout(timer);
  }, [tab, emailUnverified]);
  const [signingOut, setSigningOut] = useState(false);
  useEffect(() => {
    if (!signOutOpen) return;
    const onKey = (event: KeyboardEvent) => { if (event.key === 'Escape' && !signingOut) setSignOutOpen(false); };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [signOutOpen, signingOut]);
  async function confirmSignOut() { setSigningOut(true); try { await signOut(); } finally { setSigningOut(false); setSignOutOpen(false); } }
  const composerRef = useRef<HTMLTextAreaElement>(null);
  const likesInFlight = useRef(new Set<Post['id']>());
  function applyStarter(text: string) {
    setDraft(text);
    requestAnimationFrame(() => { const field = composerRef.current; if (field) { field.focus(); field.setSelectionRange(text.length, text.length); } });
  }
  useEffect(() => {
    if (!accessToken) return;
    api<Announcement[]>('/api/announcements').then(setAnnouncements).catch(() => setAnnouncements([]));
    api<Person[]>('/api/community/people').then(data => { setPeople(data); setPeopleState('ready'); }).catch(() => setPeopleState('error'));
    api<MemberData>('/api/me').then(data => { setMemberData(data); }).catch(error => { if (isRejectedSession(error)) { clearStoredSession(); setAccessToken(null); return; } flash('Could not load your saved profile and preferences.'); });
    api<Array<{platform:string}>>('/api/me/devices').then(devices => setPushEnabled(devices.some(device => device.platform === 'web'))).catch(() => {});
  }, [accessToken, feedScope]);
  useEffect(() => { if (tab === 'Home') setFeedSort('latest'); else if (tab === 'Trending') setFeedSort('trending'); }, [tab]);
  useEffect(() => { if (accessToken) void loadFirstPage(); }, [accessToken, feedScope, feedSort]);
  useEffect(() => {
    if (!accessToken || !pushEnabled) return;
    let unsubscribe = () => {};
    void listenForPushMessages(message => { flash(message.title ? `${message.title}: ${message.body || ''}` : 'You have a new community notification.'); void loadActivity(); void refreshMemberData().catch(() => {}); })
      .then(stop => { unsubscribe = stop; })
      .catch(() => {});
    return () => unsubscribe();
  }, [accessToken, pushEnabled]);
  useEffect(() => {
    if (!accessToken) return;
    void loadActivity();
  }, [accessToken]);
  async function loadActivity() {
    try { const data = await api<{ items: ActivityItem[]; unreadCount: number }>('/api/notifications'); setActivity(data.items); setUnreadCount(data.unreadCount); setActivityState('ready'); }
    catch { setActivityState(state => state === 'ready' ? state : 'error'); }
  }
  function toggleActivity() {
    const opening = !activityOpen;
    setActivityOpen(opening);
    if (opening) { void loadActivity(); }
    if (opening && unreadCount) { setUnreadCount(0); void api('/api/notifications/read', { method: 'POST' }).catch(() => {}); }
    if (!opening) setActivity(items => items.map(item => ({ ...item, unread: false })));
  }
  useEffect(() => {
    if (resendIn <= 0) return;
    const timer = window.setTimeout(() => setResendIn(seconds => seconds - 1), 1000);
    return () => window.clearTimeout(timer);
  }, [resendIn]);
  function markEmailVerified() { setMemberData(data => data?.user ? { ...data, user: { ...data.user, emailVerified: true } } : data); }
  async function sendVerifyCode() {
    setVerifyBusy('sending'); setVerifyError('');
    try {
      const result = await api<{ emailVerified: boolean }>('/api/me/email/send-otp', { method: 'POST' });
      if (result.emailVerified) { markEmailVerified(); setVerifyOpen(false); flash('Your email is already verified'); return; }
      setResendIn(60);
    } catch (error) { setVerifyError(error instanceof Error ? error.message : 'Could not send the code. Please try again.'); }
    finally { setVerifyBusy(null); }
  }
  function openVerify() { setVerifyOpen(true); setVerifyCode(''); setVerifyError(''); if (resendIn <= 0) void sendVerifyCode(); }
  async function submitVerifyCode(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const code = verifyCode.replace(/\s+/g, '');
    if (!/^\d{6}$/.test(code)) { setVerifyError('Enter the 6-digit code from your email.'); return; }
    setVerifyBusy('checking'); setVerifyError('');
    try {
      await api('/api/me/email/verify-otp', { method: 'POST', body: JSON.stringify({ code }) });
      markEmailVerified(); setVerifyOpen(false); flash('Email verified');
    } catch (error) { setVerifyError(error instanceof Error ? error.message : 'That code is invalid or has expired.'); }
    finally { setVerifyBusy(null); }
  }
  async function copyInviteLink() {
    const company = memberData?.company?.name;
    const text = `Join me${company ? ` at ${company}` : ''} on Office Gossip — a kinder corner of the internet for coworkers.`;
    const url = window.location.origin;
    if (navigator.share) { try { await navigator.share({ title: 'Join me on Office Gossip', text, url }); return; } catch (error) { if (error instanceof DOMException && error.name === 'AbortError') return; } }
    try { await navigator.clipboard.writeText(`${text} ${url}`); flash('Invite link copied — share it with your coworkers'); } catch { flash('Could not copy the link.'); }
  }
  async function loadFirstPage(showLoading = true) {
    const request = ++feedRequest.current;
    if (showLoading) setFeedState('loading');
    setLoadingMorePosts(false);
    try {
      const page = await fetchFeedPage(feedScope, feedSort);
      if (request !== feedRequest.current) return;
      setPosts(page.posts); setFeedCursor(page.cursor); setHasMorePosts(page.hasMore); setFeedState('ready');
    } catch { if (request === feedRequest.current && showLoading) setFeedState('error'); }
  }
  async function loadMorePosts() {
    if (!hasMorePosts || loadingMorePosts || !feedCursor || feedState !== 'ready') return;
    const request = feedRequest.current;
    setLoadingMorePosts(true);
    try {
      const page = await fetchFeedPage(feedScope, feedSort, feedCursor);
      if (request !== feedRequest.current) return;
      setPosts(list => [...list, ...page.posts.filter(post => !list.some(existing => existing.id === post.id))]);
      setFeedCursor(page.cursor); setHasMorePosts(page.hasMore);
    } catch { if (request === feedRequest.current) flash('Could not load more posts. Please try again.'); }
    finally { if (request === feedRequest.current) setLoadingMorePosts(false); }
  }
  function reloadFeed() { void loadFirstPage(); }
  function reloadPeople() { setPeopleState('loading'); api<Person[]>('/api/community/people').then(data => { setPeople(data); setPeopleState('ready'); }).catch(() => setPeopleState('error')); }
  const scopeLabel = feedScope === 'global' ? 'the Global community' : memberData?.company?.name || 'your company';
  const feedLoading = <Empty tone="loading" icon="◌" title="Loading posts" detail={`Getting the latest from ${scopeLabel}.`}/>;
  const feedError = <Empty tone="error" icon="!" title="Feed unavailable" detail="We couldn’t reach the community right now. Check your connection and try again." actions={[{ label: 'Try again', onClick: reloadFeed }]}/>;
  const filteredPeople = useMemo(() => people.filter(person => `${person.name} ${person.role} ${person.team}`.toLowerCase().includes(search.toLowerCase())), [people, search]);
  function flash(message: string) { setNotice(message); window.setTimeout(() => setNotice(''), 2800); }
  async function toggleFollow(person: Person) {
    const next = !person.following;
    const setFollowing = (following: boolean) => setPeople(list => list.map(p => p.id === person.id ? { ...p, following } : p));
    await run(`follow:${person.id}`, async () => {
      setFollowing(next);
      try { const result = await api<{ following: boolean }>(`/api/community/people/${person.id}/follow`, { method: next ? 'POST' : 'DELETE' }); setFollowing(result.following); }
      catch { setFollowing(!next); flash(next ? 'Could not follow. Please try again.' : 'Could not unfollow. Please try again.'); }
    });
  }
  async function likePost(post: Post) {
    if (likesInFlight.current.has(post.id)) return;
    likesInFlight.current.add(post.id);
    const setLiked = (liked: boolean) => setPosts(list => list.map(p => p.id === post.id ? { ...p, liked, likes: Math.max(0, p.likes + (liked === Boolean(p.liked) ? 0 : liked ? 1 : -1)) } : p));
    setLiked(!post.liked);
    try {
      const { liked } = await api<{ liked: boolean }>(`/api/community/posts/${post.id}/likes`, { method: 'POST' });
      setLiked(liked);
    } catch { setLiked(Boolean(post.liked)); flash('Could not update reaction. Please try again.'); }
    finally { likesInFlight.current.delete(post.id); }
  }
  async function sharePost(event: React.FormEvent<HTMLFormElement>) { event.preventDefault(); const body = draft.trim(); if (!body) return; await run('share', async () => { try { const result = await api<{ pending?: boolean }>('/api/community/posts', { method: 'POST', body: JSON.stringify({ body, anonymous }) }); await loadFirstPage(false); setDraft(''); setComposerOpen(false); flash(result?.pending ? 'Your post is saved. It will be shared once your company is approved' : 'Your post was shared'); } catch { flash('Could not publish. Please try again.'); } }); }
  async function refreshMemberData() { const latest = await api<MemberData>('/api/me'); setMemberData(latest); return latest; }
  // Changing tabs closes every open popup so none reappears when coming back.
  useEffect(() => {
    setComposerOpen(false); setPostDialog(null); setPostingGateOpen(false); setCompanyPickerOpen(false); setSignOutOpen(false);
    setDeleteAccountOpen(false); setVerifyOpen(false); setActivityOpen(false); setScopeMenuOpen(false); setWebpage(null);
  }, [tab]);
  // Admin approval happens elsewhere: re-check on focus, and every 30s while a company request is pending.
  const companyPending = Boolean(memberData?.user && !memberData.user.company && memberData.user.companyRequestPending);
  useEffect(() => {
    if (!accessToken) return;
    const refresh = () => { if (document.visibilityState === 'visible') void refreshMemberData().catch(() => {}); };
    window.addEventListener('focus', refresh);
    document.addEventListener('visibilitychange', refresh);
    const timer = companyPending ? window.setInterval(refresh, 30_000) : undefined;
    return () => { window.removeEventListener('focus', refresh); document.removeEventListener('visibilitychange', refresh); window.clearInterval(timer); };
  }, [accessToken, companyPending]);
  // Once the company is approved, held posts go live and coworkers appear, so reload both.
  const companyId = memberData?.user?.company?.id ?? null;
  const previousCompanyId = useRef<string | null | undefined>(undefined);
  useEffect(() => {
    const previous = previousCompanyId.current;
    previousCompanyId.current = companyId;
    if (previous === null && companyId) { void loadFirstPage(false); reloadPeople(); }
  }, [companyId]);
  function companyChosen(user: MemberUser) {
    setMemberData(data => data ? { ...data, user, company: user.company ? { name: user.company.name } : data.company } : data);
    setCompanyPickerOpen(false);
    flash(user.company ? `Welcome to ${user.company.name}` : `Request sent · “${user.pendingCompanyName}” is waiting for admin approval`);
    if (user.company) api<Person[]>('/api/community/people').then(data => { setPeople(data); setPeopleState('ready'); }).catch(() => {});
    const resume = takeResume();
    if (resume && canPost(user)) void openComposer(resume.starter);
  }
  // Re-fetches the profile so a just-approved company or newly added name unlocks posting.
  async function openComposer(starter?: string) {
    setCheckingProfile(true);
    let latest = memberData;
    try { latest = await api<MemberData>('/api/me'); setMemberData(latest); } catch { /* Fall back to the cached profile. */ } finally { setCheckingProfile(false); }
    if (!canPost(latest?.user)) { gateStarter.current = starter; setPostingGateOpen(true); return; }
    if (starter !== undefined) setDraft(starter);
    setComposerOpen(true);
  }
  function startProfileEdit() {
    setProfileDraft({ displayName: memberData?.profile.display_name || '', roleTitle: memberData?.profile.role_title || '', bio: memberData?.profile.bio || '' });
    setProfileEditing(true);
    setTab('Profile');
  }
  async function toggleArchive(post: Post) {
    const archived = !post.isArchived;
    await run(`archive:${post.id}`, async () => { try { await api(`/api/community/posts/${post.id}/archive`, { method: 'POST', body: JSON.stringify({ archived }) }); setPosts(list => list.map(p => p.id === post.id ? { ...p, isArchived: archived } : p)); flash(archived ? 'Post archived — only you can see it now' : 'Post is back in the feed'); }
    catch (error) { flash(error instanceof Error ? error.message : 'Could not update the post. Please try again.'); } });
  }
  const postCompany = (post: Post) => feedScope === 'global' ? post.company || 'Office Gossip' : memberData?.company?.name || 'Your community';
  function handlePostOption(option: PostOptionId, post: Post) {
    if (option === 'copy') { void navigator.clipboard?.writeText(post.body).then(() => flash('Post text copied'), () => flash('Could not copy the post text.')); return; }
    if (option === 'archive') { void toggleArchive(post); return; }
    if (option === 'edit') setEditDraft(post.body);
    if (option === 'report') setReportReason(REPORT_REASONS[0]);
    setPostDialog({ type: option, post });
  }
  async function submitPostDialog(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); if (!postDialog) return;
    const { type, post } = postDialog;
    setPostActionBusy(true);
    try {
      if (type === 'edit') { const body = editDraft.trim(); await api(`/api/community/posts/${post.id}`, { method: 'PATCH', body: JSON.stringify({ body }) }); setPosts(list => list.map(p => p.id === post.id ? { ...p, body } : p)); flash('Post updated'); }
      if (type === 'delete') { await api(`/api/community/posts/${post.id}`, { method: 'DELETE' }); setPosts(list => list.filter(p => p.id !== post.id)); flash('Post deleted'); }
      if (type === 'report') { await api(`/api/community/posts/${post.id}/report`, { method: 'POST', body: JSON.stringify({ reason: reportReason }) }); flash('Thanks — our team will review this post'); }
      setPostDialog(null);
    } catch (error) { flash(error instanceof Error ? error.message : 'Something went wrong. Please try again.'); } finally { setPostActionBusy(false); }
  }
  async function enablePush() { await run('push', async () => { try { const pushToken = await requestWebPushToken(); await api('/api/me/devices', { method: 'POST', body: JSON.stringify({ platform: 'web', pushToken }) }); setPushEnabled(true); flash('Push notifications enabled for this browser'); } catch (error) { flash(error instanceof Error ? error.message : 'Could not enable push notifications.'); } }); }
  async function saveProfile(event: React.FormEvent<HTMLFormElement>) { event.preventDefault(); setProfileSaving(true); try { await api('/api/me/profile', { method: 'PATCH', body: JSON.stringify(profileDraft) }); if (memberData) setMemberData({ ...memberData, profile: { ...memberData.profile, display_name: profileDraft.displayName, role_title: profileDraft.roleTitle, bio: profileDraft.bio } }); const resume = takeResume(); setProfileEditing(false); flash('Profile saved'); if (resume) void openComposer(resume.starter); } catch { flash('Could not save your profile. Please try again.'); } finally { setProfileSaving(false); } }
  function resetLocalSession() { clearStoredSession(); sessionStorage.removeItem('officegossip_google_company'); setMemberData(null); setPosts([]); setPeople([]); setAnnouncements([]); setDismissedAnnouncements([]); setFeedState('loading'); setPeopleState('loading'); setProfileEditing(false); setAccessToken(null); }
  async function signOut() { try { if (pushEnabled) { const pushToken = await removeWebPushToken(); if (pushToken) await api('/api/me/devices/current', { method: 'DELETE', body: JSON.stringify({ pushToken }) }); } await api('/api/auth/logout', { method: 'POST' }); } catch { /* Clear local session even if the server is unreachable. */ } finally { resetLocalSession(); } }
  // The API already revoked every session and push device; only this browser's state is left to clear.
  function accountDeleted({ purgeAfter }: { purgeAfter: string | null }) {
    setDeleteAccountOpen(false);
    if (pushEnabled) void removeWebPushToken().catch(() => {});
    const date = purgeAfter ? new Date(purgeAfter).toLocaleDateString([], { month: 'long', day: 'numeric', year: 'numeric' }) : null;
    setAuthNotice(`Your account was deleted${date ? ` and will be permanently erased on ${date}` : ''}. Changed your mind? Sign in again to restore it.`);
    resetLocalSession();
  }
  function renderContent() {
    const scopeTabs = <div className="mobile-scope" role="tablist" aria-label="Community feed scope"><button type="button" role="tab" aria-selected={feedScope === 'global'} className={feedScope === 'global' ? 'selected' : ''} onClick={() => setFeedScope('global')}><GlobeIcon/>Global</button><button type="button" role="tab" aria-selected={feedScope === 'company'} className={feedScope === 'company' ? 'selected' : ''} onClick={() => { if (memberData?.company) setFeedScope('company'); else if (memberData?.user) setCompanyPickerOpen(true); else flash('Join a company to see your company community.'); }}>{memberData?.company ? <BusinessIcon/> : <span aria-hidden="true">🔒</span>}{memberData?.company?.name || 'Company'}</button></div>;
    if (tab === 'Home') return <><div className="greeting"><section className={`home-hero ${feedScope}`}><div className="home-hero-copy"><span className="home-hero-eyebrow">{feedScope === 'global' ? '◎ GLOBAL COMMUNITY' : `▦ ${(memberData?.company?.name || 'YOUR COMPANY').toUpperCase()}`}</span><h1>{feedScope === 'global' ? <>One community,<br/><em>many voices.</em></> : <>Your work,<br/><em>out loud.</em></>}</h1><p>{feedScope === 'global' ? 'Meet people and ideas from across Office Gossip.' : 'A little more connected, one conversation at a time.'}</p></div><div className="home-hero-side"><div className="home-hero-stat"><b>{feedState === 'ready' ? posts.length : '—'}</b><span>{posts.length === 1 ? 'Post' : 'Posts'}</span></div><button type="button" className="home-hero-cta" disabled={checkingProfile} onClick={() => void openComposer()}>＋ New post</button></div><span className="home-hero-mark" aria-hidden="true">{feedScope === 'global' ? '◎' : memberData?.company?.name?.[0]?.toUpperCase() || '▦'}</span></section>{scopeTabs}</div><div className="feed-layout"><section className="feed-main"><button className="start-post" disabled={checkingProfile} onClick={() => void openComposer()}><Avatar name="You"/><span>Share something with your community…</span><b>＋</b></button><div className="feed-filter"><b>Latest from your team</b><button onClick={() => flash('Showing the latest posts')}>Latest <span>⌄</span></button></div>{announcements.filter(item => !dismissedAnnouncements.includes(item.id)).map(item => <article className="announcement-card" key={item.id}><span className="announcement-icon">📣</span><div><span className="announcement-meta"><span className="admin-tag"><VerifiedIcon/>Admin</span>{ANNOUNCEMENT_AUDIENCE[item.audience] || 'For everyone'} · {item.time}</span><p>{item.message}</p></div><button type="button" className="announcement-dismiss" aria-label="Dismiss announcement" onClick={() => setDismissedAnnouncements(list => [...list, item.id])}>×</button></article>)}{feedState === 'loading' && feedLoading}{feedState === 'error' && feedError}{feedState === 'ready' && posts.length === 0 && <section className="home-empty"><span className="empty-orbit">✳</span><span className="overline">A FRESH START</span><h2>{feedScope === 'global' ? 'The global community is quiet' : 'Your community starts here'}</h2><p>Celebrate a small win, ask your team a question, or share something that made you smile.</p><div className="empty-ideas">{POST_STARTERS.map(starter => <button type="button" key={starter.label} onClick={() => void openComposer(starter.text)}>{starter.label}</button>)}</div><button onClick={() => void openComposer()}>Write the first post <b>→</b></button></section>}{posts.map((post, index) => <React.Fragment key={post.id}><PostCard post={post} onLike={() => likePost(post)} onComment={() => flash('Comments are coming soon')} onOption={option => handlePostOption(option, post)} company={postCompany(post)} />{index === 1 && showAppPromo && <AppPromoCard onDismiss={dismissAppPromo}/>}</React.Fragment>)}{feedState === 'ready' && posts.length > 0 && <FeedPager hasMore={hasMorePosts} loading={loadingMorePosts} onLoadMore={() => void loadMorePosts()}/>}</section><aside className="right-rail"><div className="rail-card welcome-card"><span className="welcome-sparkle">✳</span><b>Good things happen<br/>when we talk.</b><p>Share a win, ask a question, or just say hello.</p><button onClick={() => void openComposer()}>Write a post <span>→</span></button></div><div className="rail-card prompt-card"><span className="overline">A LITTLE PROMPT</span><h3>What’s one thing<br/>your team did well?</h3><p>A small shoutout can make someone’s whole day.</p><button onClick={() => void openComposer('One thing my team did well this week was ')}>Share a shoutout ↗</button></div><div className="rail-foot">A kinder corner of the internet <span>✿</span></div></aside></div></>;
    if (tab === 'Trending') {
      // Ranked by the server; the Home feed's posts would only briefly show here while switching.
      const ranked = feedSort === 'trending' ? posts : [];
      const global = feedScope === 'global';
      const company = memberData?.company?.name || 'your company';
      const topHeat = ranked.length ? ranked[0].likes + ranked[0].comments : 0;
      return <><section className="trend-hero"><div className="trend-hero-copy"><span className="trend-hero-eyebrow">🔥 {global ? 'ACROSS OFFICE GOSSIP' : company.toUpperCase()}</span><h1>Trending conversations</h1><p>{global ? 'What people everywhere are reacting to right now.' : 'What your coworkers are talking about right now.'}</p></div><span className="trend-hero-flame" aria-hidden="true">🔥</span></section><div className="trend-toolbar">{scopeTabs}</div><div className="feed-section-head"><b>Trending now</b>{feedState === 'ready' && <span>{ranked.length}</span>}<button type="button" aria-label="Refresh trending" onClick={reloadFeed}>↻</button></div>{feedState === 'loading' && feedLoading}{feedState === 'error' && feedError}{feedState === 'ready' && ranked.length === 0 && <Empty icon="🔥" eyebrow="NOTHING HOT YET" title="Nothing is trending yet" detail={`Posts from the last ${TRENDING_WINDOW_DAYS} days start trending once they collect ${MIN_TREND_INTERACTIONS} or more likes and comments.`}/>}<div className="trend-list">{ranked.map((post, index) => <React.Fragment key={post.id}><PostCard post={post} rank={index + 1} topHeat={topHeat} onLike={() => likePost(post)} onComment={() => flash('Comments are coming soon')} onOption={option => handlePostOption(option, post)} company={postCompany(post)} />{index === 0 && showAppPromo && <AppPromoCard trending onDismiss={dismissAppPromo}/>}</React.Fragment>)}</div>{feedState === 'ready' && ranked.length > 0 && <FeedPager hasMore={hasMorePosts} loading={loadingMorePosts} onLoadMore={() => void loadMorePosts()}/>}</>;
    }
    if (tab === 'People') {
      const myId = memberData?.user?.id;
      const others = people.filter(person => person.id !== myId);
      const company = memberData?.company?.name;
      return <><PageHeading eyebrow="YOUR COMPANY" title="People" detail={company ? `Get to know the folks who make ${company} what it is.` : 'Meet the coworkers in your company community.'} />{company && peopleState === 'ready' && <div className="people-summary"><span className="people-summary-logo">{company[0]?.toUpperCase()}</span><div><b>{company}</b><small>{people.length} {people.length === 1 ? 'member' : 'members'}<span className="people-summary-extra"> · Company community</span></small></div><button type="button" className="people-invite" onClick={() => void copyInviteLink()} aria-label="Invite coworkers"><ShareIcon/><span>Invite</span></button></div>}{(people.length > 1 || search) && <label className="people-search"><span>⌕</span><input value={search} onChange={e => setSearch(e.target.value)} placeholder="Find someone by name, role, or team"/>{search ? <button type="button" className="people-search-clear" aria-label="Clear search" onClick={() => setSearch('')}>×</button> : <kbd>⌘ K</kbd>}</label>}{peopleState === 'loading' && <Empty tone="loading" icon="◌" title="Loading people" detail="Getting your company directory."/>}{peopleState === 'error' && <Empty tone="error" icon="!" title="People unavailable" detail="We couldn’t load your coworkers right now. Check your connection and try again." actions={[{ label: 'Try again', onClick: reloadPeople }]}/>}{peopleState === 'ready' && !company && <Empty icon="▦" title={memberData?.user?.companyRequestPending ? 'Your company is waiting for approval' : 'Join a company to meet your coworkers'} detail={memberData?.user?.companyRequestPending ? `Once “${memberData.user.pendingCompanyName}” is approved, your coworkers will show up here.` : 'The people directory lists members of your company community.'} actions={[{ label: memberData?.user?.companyRequestPending ? 'Check status' : 'Choose company', onClick: () => setCompanyPickerOpen(true) }, { label: 'Browse the Global community', onClick: () => { setFeedScope('global'); setTab('Home'); }, secondary: true }]}/>}{peopleState === 'ready' && search && filteredPeople.length === 0 && <Empty icon="⌕" title={`No matches for “${search}”`} detail="Try another name, role, or team." actions={[{ label: 'Clear search', onClick: () => setSearch('') }]}/>}<div className="people-grid">{filteredPeople.map(person => { const isMe = person.id === myId; const following = Boolean(person.following); return <article className={`person-card ${isMe ? 'me' : ''}`} key={person.id}><div className={`person-cover ${avatarColor(person.name)}`}/><Avatar name={person.name} color={avatarColor(person.name)}/><b>{person.name}{isMe && <span className="you-tag">You</span>}</b><span className={person.role ? '' : 'muted'}>{person.role || (isMe ? 'Add your role' : 'Role not added yet')}</span>{person.team && <small>{person.team}</small>}{isMe ? <button type="button" className="person-action" onClick={startProfileEdit}>Edit profile</button> : <button type="button" className={`person-action ${following ? 'following' : 'primary'}`} aria-pressed={following} disabled={busy(`follow:${person.id}`)} onClick={() => void toggleFollow(person)}>{following ? '✓ Following' : '＋ Follow'}</button>}</article>; })}</div>{peopleState === 'ready' && company && others.length === 0 && !search && <div className="invite-banner"><span className="invite-banner-icon" aria-hidden="true">＋</span><div><b>It’s just you for now</b><small>You’re one of the first from {company}. Invite your coworkers to join you.</small></div><button type="button" onClick={() => void copyInviteLink()}><ShareIcon/>Invite coworkers</button></div>}</>;
    }
    return <>{memberData ? <ProfileView data={memberData} pushEnabled={pushEnabled} pushBusy={busy('push')} onEnablePush={() => void enablePush()} onEdit={startProfileEdit} onInvite={() => void copyInviteLink()} onChooseCompany={() => setCompanyPickerOpen(true)} onVerifyEmail={openVerify} onOpen={setWebpage} onSignOut={() => setSignOutOpen(true)} onDelete={() => setDeleteAccountOpen(true)}/> : <Empty tone="loading" icon="◌" title="Loading your profile" detail="Getting your account details."/>}{profileEditing && <div className="modal-shade" onMouseDown={e => { if (e.currentTarget === e.target && !profileSaving) setProfileEditing(false); }}><form className="compose-modal post-dialog profile-edit-dialog" role="dialog" aria-modal="true" aria-labelledby="edit-profile-title" onSubmit={saveProfile}><button type="button" className="close-modal" aria-label="Close" onClick={() => setProfileEditing(false)}>×</button><span className="overline">YOUR PROFILE</span><h2 id="edit-profile-title">Edit profile</h2><label>Display name<input value={profileDraft.displayName} onChange={e => setProfileDraft({ ...profileDraft, displayName: e.target.value })} required autoFocus/></label><label>Role<input value={profileDraft.roleTitle} onChange={e => setProfileDraft({ ...profileDraft, roleTitle: e.target.value })} placeholder="Your role or title"/></label><label>Bio<textarea value={profileDraft.bio} onChange={e => setProfileDraft({ ...profileDraft, bio: e.target.value })} maxLength={500} placeholder="A little about you"/></label><div className="post-dialog-actions"><button type="button" className="outline-button" disabled={profileSaving} onClick={() => setProfileEditing(false)}>Cancel</button><button className="share-button" disabled={profileSaving}>{profileSaving ? 'Saving…' : 'Save profile'}</button></div></form></div>}</>;
  }
  if (!accessToken) return <AuthScreen notice={authNotice} onAuthenticated={(token, refreshToken) => { localStorage.setItem('officegossip_access_token', token); if (refreshToken) localStorage.setItem('officegossip_refresh_token', refreshToken); setAuthNotice(''); setAccessToken(token); }} />;
  return <div className="member-app"><aside className="member-sidebar"><a href="#home" className="member-brand" onClick={e => {e.preventDefault();setTab('Home')}}><span className="member-mark"><img src="/brand-mark.svg" alt="" /></span><span>office<span>gossip</span></span></a><div className="community-picker"><button className="member-company" type="button" aria-expanded={scopeMenuOpen} onClick={() => setScopeMenuOpen(open => !open)}><span className="company-logo">{feedScope === 'global' ? '◎' : memberData?.company?.name?.[0] || 'O'}</span><span><b>{feedScope === 'global' ? 'Global community' : memberData?.company?.name || 'Your company'}</b><small>{feedScope === 'global' ? 'All communities' : 'Company community'}</small></span><span className="down">⌄</span></button>{scopeMenuOpen && <div className="community-menu" role="menu"><button type="button" role="menuitem" className={feedScope === 'global' ? 'selected' : ''} onClick={() => {setFeedScope('global');setScopeMenuOpen(false);setTab('Home')}}><span className="community-menu-icon">◎</span><span><b>Global community</b><small>Posts from everyone</small></span>{feedScope === 'global' && <i>✓</i>}</button><button type="button" role="menuitem" className={feedScope === 'company' ? 'selected' : ''} disabled={!memberData?.company && !memberData?.user} onClick={() => {setScopeMenuOpen(false);if (!memberData?.company) {setCompanyPickerOpen(true);return;}setFeedScope('company');setTab('Home')}}><span className="community-menu-icon">{memberData?.company?.name?.[0] || (memberData?.user ? '🔒' : 'O')}</span><span><b>{memberData?.company?.name || 'Company community'}</b><small>{memberData?.user && !memberData.company ? companyStatusText(memberData.user) : 'Posts from your coworkers'}</small></span>{memberData?.user && <CompanyBadge user={memberData.user}/>}{feedScope === 'company' && <i>✓</i>}</button></div>}</div><span className="nav-section-label">YOUR SPACE</span><nav>{nav.map(item => <button key={item.tab} className={`member-nav ${tab === item.tab ? 'active' : ''}`} onClick={() => {setTab(item.tab);setSearch('')}}><span>{item.icon}</span>{item.tab}{item.tab === 'Trending' && <i className="hot-dot"/>}</button>)}</nav><div className="sidebar-bottom"><div className="kind-card"><span>✿</span><b>Make someone's<br/>day a little better.</b><small>A kind word goes a long way.</small></div><button className="member-account" onClick={() => setTab('Profile')}><Avatar name={memberData?.profile.display_name || "Member"} color="lilac"/><span><b>{memberData?.profile.display_name || "Member"}</b><small>{memberData?.profile.role_title || "Community member"}</small></span><span className="account-dots">···</span></button></div></aside><main className="member-main"><header className="member-topbar"><div className="mobile-brand"><span className="member-mark"><img src="/brand-mark.svg" alt="" /></span><b>office<span>gossip</span></b></div><div className="topbar-caption"><span>{feedScope === 'global' ? 'Global community' : memberData?.company?.name || 'Community'}</span><i>/</i><b>{tab}</b></div><div className="member-top-actions"><span className="community-live"><i/>Community is active</span><div className="activity-anchor"><button className={`notification-button ${activityOpen ? 'open' : ''}`} aria-label={unreadCount ? `Notifications, ${unreadCount} unread` : 'Notifications'} aria-expanded={activityOpen} onClick={toggleActivity}><BellIcon/>{unreadCount > 0 && <i className="activity-badge">{unreadCount > 9 ? '9+' : unreadCount}</i>}</button>{activityOpen && <><div className="activity-scrim" onClick={toggleActivity}/><section className="activity-panel" role="dialog" aria-label="Notifications"><header><div><b>Notifications</b><small>Likes, comments, and new followers</small></div><button type="button" className="activity-close" aria-label="Close notifications" onClick={toggleActivity}>×</button></header><div className="activity-list">{activityState === 'loading' && activity.length === 0 && <p className="activity-note">Loading…</p>}{activityState === 'error' && activity.length === 0 && <p className="activity-note">Couldn’t load notifications. <button type="button" onClick={() => void loadActivity()}>Try again</button></p>}{activityState === 'ready' && activity.length === 0 && <div className="activity-empty"><span><BellIcon/></span><b>No notifications yet</b><p>When someone likes or comments on your posts, or follows you, you’ll see it here.</p></div>}{activity.map(item => <button type="button" key={item.id} className={`activity-item ${item.unread ? 'unread' : ''}`} onClick={() => { toggleActivity(); setTab(item.type === 'follow' ? 'People' : 'Home'); }}><span className={`activity-icon ${item.type}`}>{item.type === 'reaction' ? <HeartIcon filled/> : item.type === 'follow' ? '＋' : <ChatIcon/>}</span><span className="activity-copy"><span><b>{item.actorName}</b> {item.type === 'reaction' ? 'liked your post' : item.type === 'follow' ? 'started following you' : 'commented on your post'}</span>{item.comment && <q>{item.comment}</q>}<small>{item.postExcerpt ? <>“{item.postExcerpt}” · </> : null}{item.time}</small></span>{item.unread && <i className="activity-dot" aria-label="Unread"/>}</button>)}</div></section></>}</div><Avatar name={memberData?.profile.display_name || "Member"} color="lilac" onClick={() => setTab('Profile')}/></div></header><div className="member-content">{renderContent()}<footer className="member-footer">Office Gossip <span>·</span> A kinder corner of the internet<nav className="footer-links" aria-label="Support and legal">{WEBPAGES.map(page => <button type="button" key={page.path} onClick={() => setWebpage(page)}>{page.short}</button>)}</nav></footer></div>{tab === 'Home' && <button type="button" className="mobile-fab" aria-label="New post" title="New post" disabled={checkingProfile} onClick={() => void openComposer()}>✎</button>}<nav className="mobile-nav">{nav.map(item => <button key={item.tab} className={tab === item.tab ? 'active' : ''} aria-current={tab === item.tab ? 'page' : undefined} aria-label={item.tab} onClick={() => { setTab(item.tab); setSearch(''); window.scrollTo({ top: 0 }); }}><span className="nav-pill"><NavIcon tab={item.tab} filled={tab === item.tab}/>{tab === item.tab && <small>{item.tab}</small>}</span></button>)}</nav></main>{composerOpen && <div className="modal-shade" onMouseDown={e => {if(e.currentTarget===e.target)setComposerOpen(false)}}><form className="compose-modal" onSubmit={sharePost}><button type="button" className="close-modal" onClick={() => setComposerOpen(false)}>×</button><span className="overline">{feedScope === 'global' ? 'GLOBAL COMMUNITY' : memberData?.company?.name || 'YOUR COMPANY'}</span><h2>Start a conversation</h2><p className="compose-scope">{feedScope === 'global' ? `Visible to everyone in the Global community and shared with ${memberData?.company?.name || 'your company'}.` : `Shared with ${memberData?.company?.name || 'your company'} coworkers and also visible in the Global community.`}</p><div className="compose-suggestions" role="group" aria-label="Post ideas"><span>Need an idea?</span>{POST_STARTERS.map(starter => <button type="button" key={starter.label} className={draft === starter.text ? 'selected' : ''} onClick={() => applyStarter(starter.text)}>{starter.label}</button>)}</div><textarea ref={composerRef} autoFocus value={draft} onChange={e => setDraft(e.target.value)} maxLength={500} placeholder="What’s happening at work? Share a thought, a win, or a question…" required/><div className="compose-meta"><span>{draft.length}/500</span><span>Text and emojis, just like you ☺</span></div><label className={`anonymous-option ${anonymous ? 'on' : ''}`}><span className="anon-icon">{anonymous ? <EyeOffIcon/> : <EyeIcon/>}</span><span className="anon-copy"><b>Post anonymously</b><small>{anonymous ? 'Your name and role stay hidden' : 'Coworkers will see your name and role'}</small></span><input type="checkbox" role="switch" className="switch" checked={anonymous} onChange={e => setAnonymous(e.target.checked)}/></label><button className="share-button" disabled={!draft.trim() || busy('share')}>{busy('share') ? 'Sharing…' : <>Share with your community <span>→</span></>}</button></form></div>}{postDialog && <div className="modal-shade" onMouseDown={e => {if(e.currentTarget===e.target && !postActionBusy)setPostDialog(null)}}><form className="compose-modal post-dialog" onSubmit={submitPostDialog}><button type="button" className="close-modal" aria-label="Close" onClick={() => setPostDialog(null)}>×</button>{postDialog.type === 'edit' && <><span className="overline">YOUR POST</span><h2>Edit post</h2><textarea autoFocus value={editDraft} onChange={e => setEditDraft(e.target.value)} maxLength={500} required/><div className="compose-meta"><span>{editDraft.length}/500</span></div><button className="share-button" disabled={postActionBusy || !editDraft.trim() || editDraft.trim() === postDialog.post.body.trim()}>{postActionBusy ? 'Saving…' : 'Save changes'}</button></>}{postDialog.type === 'delete' && <><span className="overline">YOUR POST</span><h2>Delete this post?</h2><p className="post-dialog-copy">It will be removed from the feed for everyone. This can’t be undone.</p><div className="post-dialog-actions"><button type="button" className="outline-button" onClick={() => setPostDialog(null)}>Cancel</button><button className="share-button danger" disabled={postActionBusy}>{postActionBusy ? 'Deleting…' : 'Delete post'}</button></div></>}{postDialog.type === 'report' && <><span className="overline">REPORT POST</span><h2>Why are you reporting this?</h2><p className="post-dialog-copy">Reports are anonymous and reviewed by our team.</p><div className="report-reasons" role="radiogroup">{REPORT_REASONS.map(reason => <label key={reason} className={reportReason === reason ? 'selected' : ''}><input type="radio" name="report-reason" value={reason} checked={reportReason === reason} onChange={() => setReportReason(reason)}/>{reason}</label>)}</div><button className="share-button danger" disabled={postActionBusy}>{postActionBusy ? 'Sending…' : 'Submit report'}</button></>}</form></div>}{webpage && <WebpageViewer page={webpage} onClose={() => setWebpage(null)}/>}{verifyNudge && !verifyOpen && <aside className="verify-nudge" role="status"><span className="verify-nudge-icon" aria-hidden="true">✉</span><div><b>Verify your email</b><p>Confirm <strong>{memberData?.email}</strong> with a quick one-time code.</p><button type="button" onClick={() => { setVerifyNudge(false); openVerify(); }}>Verify now</button></div><button type="button" className="verify-nudge-close" aria-label="Dismiss" onClick={() => setVerifyNudge(false)}>×</button><i className="verify-nudge-timer" aria-hidden="true"/></aside>}{verifyOpen && <div className="modal-shade" onMouseDown={e => { if (e.currentTarget === e.target && !verifyBusy) setVerifyOpen(false); }}><form className="confirm-dialog verify-dialog" role="dialog" aria-modal="true" aria-labelledby="verify-title" onSubmit={submitVerifyCode}><span className="confirm-dialog-icon verify-icon" aria-hidden="true">✉</span><h2 id="verify-title">Verify your email</h2><p>{verifyBusy === 'sending' ? 'Sending a code to ' : 'Enter the code we sent to '}<b>{memberData?.email}</b>.</p><input className="verify-code-input" value={verifyCode} onChange={e => setVerifyCode(e.target.value.replace(/[^\d]/g, '').slice(0, 6))} inputMode="numeric" autoComplete="one-time-code" placeholder="••••••" aria-label="Verification code" autoFocus/>{verifyError && <p className="verify-error" role="alert">{verifyError}</p>}<button type="button" className="verify-resend" disabled={resendIn > 0 || verifyBusy !== null} onClick={() => void sendVerifyCode()}>{resendIn > 0 ? `Resend code in ${resendIn}s` : 'Resend code'}</button><div className="confirm-dialog-actions"><button type="button" className="confirm-cancel" disabled={verifyBusy === 'checking'} onClick={() => setVerifyOpen(false)}>Cancel</button><button type="submit" className="confirm-primary" disabled={verifyBusy !== null || verifyCode.length < 6}>{verifyBusy === 'checking' ? 'Verifying…' : 'Verify'}</button></div></form></div>}{deleteAccountOpen && memberData && <DeleteAccountDialog email={memberData.email} onClose={() => setDeleteAccountOpen(false)} onDeleted={accountDeleted}/>}{signOutOpen && <div className="modal-shade" onMouseDown={e => { if (e.currentTarget === e.target && !signingOut) setSignOutOpen(false); }}><div className="confirm-dialog" role="alertdialog" aria-modal="true" aria-labelledby="signout-title" aria-describedby="signout-copy"><span className="confirm-dialog-icon" aria-hidden="true">↪</span><h2 id="signout-title">Sign out of Office Gossip?</h2><p id="signout-copy">You’ll need to sign in again to see your community.{memberData?.email && <> You’re signed in as <b>{memberData.email}</b>.</>}</p><div className="confirm-dialog-actions"><button type="button" className="confirm-cancel" autoFocus disabled={signingOut} onClick={() => setSignOutOpen(false)}>Cancel</button><button type="button" className="confirm-danger" disabled={signingOut} onClick={() => void confirmSignOut()}>{signingOut ? 'Signing out…' : 'Sign out'}</button></div></div></div>}{postingGateOpen && memberData?.user && <div className="modal-shade" onMouseDown={e => {if(e.currentTarget===e.target)setPostingGateOpen(false)}}><div className="compose-modal post-dialog" role="dialog" aria-modal="true"><button type="button" className="close-modal" aria-label="Close" onClick={() => setPostingGateOpen(false)}>×</button><span className="overline">BEFORE YOU POST</span><h2>Finish setting up to post</h2><p className="post-dialog-copy">Your company community needs these before you can share.</p>{(() => { const user = memberData.user; const needsName = !user.name.trim(); const pending = !user.company && user.companyRequestPending; const continueWith = (step: () => void) => { setPostingGateOpen(false); resumeCompose.current = { starter: gateStarter.current }; step(); }; return <><ul className="posting-requirements"><li className={needsName ? '' : 'done'}><i>{needsName ? '○' : '✓'}</i><span><b>Display name</b><small>{needsName ? 'Add the name coworkers will see' : user.name}</small></span></li><li className={user.company ? 'done' : pending ? 'pending' : ''}><i>{user.company ? '✓' : pending ? '◷' : '○'}</i><span><b>Active company membership</b><small>{user.company?.name || (user.pendingCompanyName ? `“${user.pendingCompanyName}” is waiting for admin approval` : 'Join your company to see and share posts')}</small></span></li></ul><div className="post-dialog-actions"><button type="button" className="outline-button" onClick={() => setPostingGateOpen(false)}>Not now</button><button type="button" className="share-button" onClick={() => continueWith(needsName ? startProfileEdit : () => setCompanyPickerOpen(true))}>{needsName ? 'Complete profile' : user.companyRequestPending ? 'Check status' : 'Choose company'}</button></div></>; })()}</div></div>}{companyPickerOpen && memberData?.user && <CompanyPicker user={memberData.user} onClose={() => setCompanyPickerOpen(false)} onRefresh={refreshMemberData} onSaved={companyChosen}/>}{notice && <div className="member-toast"><span>✓</span>{notice}</div>}</div>;
}
type AuthMode = 'login' | 'register' | 'forgot' | 'phone' | 'reset';
type CompanyOption = { id: string; name: string };
function AuthScreen({ notice = '', onAuthenticated }: { notice?: string; onAuthenticated: (token: string, refreshToken?: string) => void }) {
  const [deactivated, setDeactivated] = useState<DeactivatedAccount | null>(null);
  const [mode, setMode] = useState<AuthMode>(() => window.location.pathname === '/reset-password' ? 'reset' : 'login');
  const handledOAuth = useRef(false);
  const [webpage, setWebpage] = useState<Webpage | null>(null);
  const [resetTokenReady, setResetTokenReady] = useState(() => Boolean(localStorage.getItem('officegossip_access_token')));
  const [name, setName] = useState(''); const [email, setEmail] = useState(''); const [phone, setPhone] = useState('');
  const [password, setPassword] = useState(''); const [code, setCode] = useState(''); const [codeRequested, setCodeRequested] = useState(false); const [companies, setCompanies] = useState<CompanyOption[]>([]); const [companyId, setCompanyId] = useState(''); const [companyName, setCompanyName] = useState(''); const [companyWebsite, setCompanyWebsite] = useState(''); const [requestNewCompany, setRequestNewCompany] = useState(false); const [companiesLoading, setCompaniesLoading] = useState(false); const [message, setMessage] = useState(notice); const [messageIsError, setMessageIsError] = useState(false); const [busy, setBusy] = useState(false);
  const showError = (text: string) => { setMessage(text); setMessageIsError(true); };
  const showMessage = (text: string) => { setMessage(text); setMessageIsError(false); };
  const loadCompanies = useCallback(() => { setCompaniesLoading(true); setMessage(''); api<CompanyOption[]>('/api/public/companies').then(list => { setCompanies(list); setCompanyId(current => list.some(company => company.id === current) ? current : ''); }).catch(() => showError('Could not load the company list. Please try again.')).finally(() => setCompaniesLoading(false)); }, []);
  useEffect(() => { if (mode === 'register') loadCompanies(); }, [mode, loadCompanies]);
  const [otpStage, setOtpStage] = useState<'idle' | 'sent' | 'verified'>('idle');
  const [verificationToken, setVerificationToken] = useState('');
  const [otpEmailVerified, setOtpEmailVerified] = useState(true);
  const [otp, setOtp] = useState('');
  const [otpBusy, setOtpBusy] = useState<'sending' | 'checking' | null>(null);
  const [otpError, setOtpError] = useState('');
  const [otpResendIn, setOtpResendIn] = useState(0);
  useEffect(() => {
    if (otpResendIn <= 0) return;
    const timer = window.setTimeout(() => {
      setOtpResendIn(seconds => seconds - 1);
      if (otpResendIn === 1) { setOtpStage(stage => stage === 'sent' ? 'idle' : stage); setOtp(''); setOtpError(''); }
    }, 1000);
    return () => window.clearTimeout(timer);
  }, [otpResendIn]);
  const [otpNotice, setOtpNotice] = useState<{ code: string; expiresAt: number } | null>(null);
  useEffect(() => { if (mode !== 'register') setOtpNotice(null); }, [mode]);
  function resetEmailVerification() { setOtpStage('idle'); setVerificationToken(''); setOtp(''); setOtpError(''); setOtpNotice(null); }
  async function sendSignUpOtp() {
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) { setOtpError('Enter a valid email address first.'); return; }
    setOtpBusy('sending'); setOtpError('');
    try { const result = await api<{ code?: string; expiresInSeconds?: number }>('/api/auth/email/send-otp', { method: 'POST', body: JSON.stringify({ email: email.trim(), ...(name.trim() ? { name: name.trim() } : {}) }) }); setOtpStage('sent'); setOtp(''); setOtpResendIn(60); setOtpNotice(result.code ? { code: result.code, expiresAt: Date.now() + (result.expiresInSeconds ?? 600) * 1000 } : null); }
    catch (error) { setOtpError(error instanceof Error ? error.message : 'Could not send the code. Please try again.'); }
    finally { setOtpBusy(null); }
  }
  async function confirmSignUpOtp() {
    if (!/^\d{6}$/.test(otp)) { setOtpError('Enter the 6-digit code from your email.'); return; }
    setOtpBusy('checking'); setOtpError('');
    try { const result = await api<{ verificationToken: string; emailVerified?: boolean }>('/api/auth/email/verify-otp', { method: 'POST', body: JSON.stringify({ email: email.trim(), code: otp }) }); setVerificationToken(result.verificationToken); setOtpEmailVerified(result.emailVerified !== false); setOtpStage('verified'); setOtpNotice(null); }
    catch (error) { setOtpError(error instanceof Error ? error.message : 'That code is invalid or has expired.'); }
    finally { setOtpBusy(null); }
  }
  const newCompanyRequest = () => ({ companyName: companyName.trim(), ...(companyWebsite.trim() ? { companyWebsite: companyWebsite.trim() } : {}) });
  async function submit(e: React.FormEvent) { e.preventDefault(); setBusy(true); setMessage(''); try {
    if (mode === 'forgot') { await api('/api/auth/forgot-password', { method: 'POST', body: JSON.stringify({ email }) }); showMessage('If an account exists, password reset instructions have been sent.'); }
    else if (mode === 'reset') { await api('/api/auth/reset-password', { method: 'POST', body: JSON.stringify({ password }) }); localStorage.removeItem('officegossip_access_token'); localStorage.removeItem('officegossip_refresh_token'); window.history.replaceState({}, document.title, '/'); setMode('login'); setPassword(''); showMessage('Your password has been updated. You can sign in now.'); }
    else if (mode === 'phone' && !code) { await api('/api/auth/phone/send-code', { method: 'POST', body: JSON.stringify({ phone }) }); showMessage('Verification code sent.'); setCodeRequested(true); }
    else if (mode === 'phone') { const result = await api<{ accessToken: string; refreshToken?: string }>('/api/auth/phone/verify', { method: 'POST', body: JSON.stringify({ phone, code }) }); onAuthenticated(result.accessToken, result.refreshToken); }
    else { const result = await api<{ accessToken: string | null; refreshToken?: string; confirmationRequired?: boolean }>(mode === 'register' ? '/api/auth/register' : '/api/auth/login', { method: 'POST', body: JSON.stringify({ ...(mode === 'register' ? { name, ...(verificationToken ? { verificationToken } : {}), ...(requestNewCompany ? newCompanyRequest() : { companyId }) } : {}), email, password }) }); if (!result.accessToken) { showMessage(result.confirmationRequired ? 'Account created. Check your email to confirm it, then sign in.' : 'Account created, but no sign-in session was returned.'); return; } onAuthenticated(result.accessToken, result.refreshToken); }
  } catch (error) { const account = mode === 'login' ? deactivatedAccountFrom(error) : null; if (account) { setDeactivated(account); return; } showError(hasAuthMessage(error) ? error.message : 'Could not complete that request. Check your details or try again later.'); } finally { setBusy(false); } }
  useEffect(() => { if (handledOAuth.current) return; const params = new URLSearchParams(window.location.hash.slice(1)); const token = params.get('access_token'); if (!token) return; handledOAuth.current = true; const refreshToken = params.get('refresh_token') ?? undefined; window.history.replaceState({}, document.title, window.location.pathname + window.location.search); localStorage.setItem('officegossip_access_token', token); if (refreshToken) localStorage.setItem('officegossip_refresh_token', refreshToken); setResetTokenReady(true); if (mode === 'reset') return; void (async () => { try { const pending = sessionStorage.getItem('officegossip_google_company'); if (pending) { sessionStorage.removeItem('officegossip_google_company'); await api('/api/auth/complete-profile', { method: 'POST', body: pending }); } await api('/api/me'); onAuthenticated(token, refreshToken); } catch (error) { clearStoredSession(); showError(isRejectedSession(error) ? error.message : 'Google sign-in succeeded, but company setup failed. Please try again.'); } })(); }, [mode, onAuthenticated]);
  async function google() { setBusy(true); setMessage(''); try { if (mode === 'register') { if (!requestNewCompany && !companyId) throw new Error('Choose a company first.'); if (requestNewCompany && !companyName.trim()) throw new Error('Enter your company name first.'); sessionStorage.setItem('officegossip_google_company', JSON.stringify(requestNewCompany ? newCompanyRequest() : { companyId })); } const result = await api<{ url: string }>('/api/auth/google', { method: 'POST', body: JSON.stringify({ redirectTo: window.location.origin }) }); window.location.assign(result.url); } catch (error) { showError(error instanceof Error ? error.message : 'Google sign-in is not configured yet.'); setBusy(false); } }
  return <main className="auth-screen">{otpNotice && <OtpNotification code={otpNotice.code} expiresAt={otpNotice.expiresAt} onUse={() => { setOtp(otpNotice.code); setOtpError(''); }} onClose={() => setOtpNotice(null)}/>}<section className="auth-story"><a className="auth-brand" href="/"><span className="member-mark"><img src="/brand-mark.svg" alt="" /></span><span>office<span>gossip</span></span></a><div className="story-copy"><span className="story-pill"><i/> A little more human, every day</span><h2>Work is better<br/>when we <em>belong.</em></h2><p>A place for the small wins, kind words, and conversations that bring your people closer.</p><div className="story-note"><span>✳</span><div><b>Good things happen when we talk.</b><small>Your company community is waiting.</small></div></div></div><small className="story-footer">A kinder corner of the internet <span>✿</span></small></section><header className="auth-mobile-head"><a className="auth-mobile-brand" href="/"><span className="member-mark"><img src="/brand-mark.svg" alt="" /></span><span>office<span>gossip</span></span></a><p>Work is better when we <em>belong.</em></p></header><section className="auth-card"><span className="overline">A KINDER WORKPLACE COMMUNITY</span><h1>{mode === 'register' ? 'Create your account' : mode === 'forgot' || mode === 'reset' ? 'Reset your password' : mode === 'phone' ? 'Continue with phone' : 'Welcome back'}</h1><p className="auth-intro">{mode === 'register' ? 'Join your company community and start connecting.' : mode === 'forgot' ? 'We’ll send you a link to reset your password.' : mode === 'reset' ? 'Choose a new password for your account.' : 'Sign in to keep up with your community.'}</p>
    {GOOGLE_AUTH_ENABLED && (mode === 'login' || mode === 'register') && <button className="google-button" type="button" onClick={google} disabled={busy || (mode === 'register' && !requestNewCompany && !companyId) || (mode === 'register' && requestNewCompany && !companyName.trim())}><b>G</b> Continue with Google</button>}
    {GOOGLE_AUTH_ENABLED && (mode === 'login' || mode === 'register') && <div className="auth-divider"><span>or continue with email</span></div>}
    <form onSubmit={submit} className="auth-form">
      {mode === 'register' && <label>Full name<input autoComplete="name" value={name} onChange={e=>setName(e.target.value)} required placeholder="Your name"/></label>}
      {mode === 'phone' ? <>
        <label>Phone number<input type="tel" autoComplete="tel" value={phone} onChange={e=>setPhone(e.target.value)} required placeholder="+1 555 000 0000"/></label>
        {codeRequested && <label>Verification code<input inputMode="numeric" value={code} onChange={e=>setCode(e.target.value)} required placeholder="Enter the code"/></label>}
      </> : <>
        {mode === 'register' && (requestNewCompany ? <>
          <label><span className="field-label">Company name <em className="field-required">Required</em></span><input value={companyName} onChange={e=>setCompanyName(e.target.value)} required minLength={2} maxLength={100} autoComplete="organization" placeholder="Enter your company name"/></label>
          <label><span className="field-label">Company website <em className="field-optional">Optional</em></span><input value={companyWebsite} onChange={e=>setCompanyWebsite(e.target.value)} inputMode="url" autoComplete="url" placeholder={defaultCompanyDomain(companyName) || 'yourcompany.com'}/><small className="field-hint">{companyWebsite.trim() ? 'We’ll use this website for your company.' : defaultCompanyDomain(companyName) ? <>Leave blank to use <b>{defaultCompanyDomain(companyName)}</b>.</> : 'Leave blank and we’ll use your company name + .com.'}</small></label>
          <p className="company-request-note">We’ll send this company to the Office Gossip team for review.</p>
        </> : <label>Company<span className="company-select-row"><select value={companyId} onChange={e=>setCompanyId(e.target.value)} required disabled={companiesLoading || companies.length === 0}>
          <option value="">{companiesLoading ? 'Loading companies…' : companies.length ? 'Select your company' : 'No companies available'}</option>
          {companies.map(company=><option value={company.id} key={company.id}>{company.name}</option>)}
        </select><button type="button" className="company-refresh" onClick={loadCompanies} disabled={companiesLoading} aria-label="Refresh company list" title="Refresh company list"><span className={companiesLoading ? 'spinning' : ''}>↻</span></button></span></label>)}
        {mode === 'register' && <button type="button" className="company-choice-toggle" onClick={()=>{setRequestNewCompany(!requestNewCompany);setMessage('');}}>{requestNewCompany ? '← Choose a listed company' : 'My company isn’t listed'}</button>}
        {mode !== 'reset' && (mode !== 'register' || !EMAIL_OTP_ENABLED) && <label>Email address<input type="email" autoComplete="email" value={email} onChange={e=>setEmail(e.target.value)} required placeholder="you@company.com"/></label>}
        {mode === 'register' && EMAIL_OTP_ENABLED && <div className="email-verify-field"><label>Email address<span className={`email-verify-row ${otpStage}`}><input type="email" autoComplete="email" value={email} readOnly={otpStage === 'verified'} onChange={e=>{setEmail(e.target.value); if (otpStage !== 'idle') resetEmailVerification();}} required placeholder="you@company.com"/>{otpStage === 'verified' ? <span className="email-verified-chip"><VerifiedIcon/>{otpEmailVerified ? 'Verified' : 'Accepted'}</span> : <button type="button" className="email-verify-button" disabled={otpBusy !== null || !email.trim() || (otpStage === 'sent' && otpResendIn > 0)} onClick={() => void sendSignUpOtp()}>{otpBusy === 'sending' ? 'Sending…' : otpStage === 'sent' ? (otpResendIn > 0 ? `Resend ${otpResendIn}s` : 'Resend') : 'Verify'}</button>}</span></label>
          {otpStage === 'idle' && !otpError && <small className="email-verify-hint">We’ll email you a one-time code to confirm it’s really you.</small>}
          {otpStage === 'sent' && <div className="email-otp-box"><small>Enter the code sent to <b>{email.trim()}</b></small><span className="email-otp-row"><input value={otp} onChange={e => setOtp(e.target.value.replace(/[^\d]/g, '').slice(0, 6))} onKeyDown={e => { if (e.key === 'Enter') { e.preventDefault(); void confirmSignUpOtp(); } }} inputMode="numeric" autoComplete="one-time-code" placeholder="••••••" aria-label="Verification code" autoFocus/><button type="button" disabled={otpBusy !== null || otp.length < 6} onClick={() => void confirmSignUpOtp()}>{otpBusy === 'checking' ? 'Checking…' : 'Confirm'}</button></span></div>}
          {otpStage === 'verified' && <small className="email-verify-hint ok">{otpEmailVerified ? 'Email verified.' : 'Code accepted — you can verify your email later from Profile.'} <button type="button" onClick={resetEmailVerification}>Use a different email</button></small>}
          {otpError && <small className="email-verify-hint error" role="alert">{otpError}</small>}
        </div>}
        {(mode === 'login' || mode === 'register' || mode === 'reset') && <label>{mode === 'reset' ? 'New password' : 'Password'}<input type="password" autoComplete={mode === 'register' || mode === 'reset' ? 'new-password' : 'current-password'} value={password} onChange={e=>setPassword(e.target.value)} required minLength={8} placeholder="At least 8 characters"/></label>}
      </>}
      {message && <p className={`auth-message ${messageIsError ? 'error' : ''}`} role={messageIsError ? 'alert' : 'status'}>{message}</p>}
      <button className="share-button" disabled={busy || (mode === 'register' && EMAIL_OTP_ENABLED && otpStage !== 'verified') || (mode === 'register' && !requestNewCompany && !companyId) || (mode === 'register' && requestNewCompany && !companyName.trim()) || (mode === 'reset' && !resetTokenReady)}>{busy ? 'Please wait…' : mode === 'register' ? (requestNewCompany ? 'Request company & create account' : 'Create account') : mode === 'forgot' ? 'Send reset link' : mode === 'reset' ? 'Update password' : mode === 'phone' ? (code ? 'Verify phone' : 'Send verification code') : 'Sign in'} <span>→</span></button>
    </form>
    <div className="auth-links">{mode === 'login' && <><button onClick={()=>{setMode('forgot');setMessage('')}}>Forgot password?</button><p>New to Office Gossip? <button onClick={()=>{setMode('register');setMessage('')}}>Create an account</button></p></>}{mode === 'register' && <p>Already have an account? <button onClick={()=>{setMode('login');setMessage('')}}>Sign in</button></p>}{(mode === 'forgot' || mode === 'reset' || mode === 'phone') && <p>Remembered your password? <button onClick={()=>{setMode('login');setMessage('')}}>Sign in</button></p>}{(mode === 'login' || mode === 'register') && <nav className="auth-legal" aria-label="Legal"><button type="button" onClick={() => setWebpage(WEBPAGES[2])}>Terms &amp; conditions</button><span aria-hidden="true">•</span><button type="button" onClick={() => setWebpage(WEBPAGES[1])}>Privacy policy</button></nav>}</div><small className="auth-terms">By continuing, you agree to our <button type="button" onClick={() => setWebpage(WEBPAGES[2])}>Terms</button> and <button type="button" onClick={() => setWebpage(WEBPAGES[1])}>Privacy policy</button>, and to follow your company’s community guidelines. Need a hand? Visit <button type="button" onClick={() => setWebpage(WEBPAGES[0])}>Help &amp; contact</button>.</small>{webpage && <WebpageViewer page={webpage} onClose={() => setWebpage(null)}/>}
    {deactivated && <RestoreAccountDialog account={deactivated} email={email.trim()} password={password} onClose={() => { setDeactivated(null); showMessage(deactivated.canRestore ? 'Your account is still scheduled for deletion. Sign in again any time before then to restore it.' : deactivated.message); }} onRestored={session => { setDeactivated(null); onAuthenticated(session.accessToken, session.refreshToken); }}/>}
  </section></main>;
}

const AVATAR_COLORS = ['lilac', 'rose', 'blue', 'green', 'amber'];
const avatarColor = (name: string) => AVATAR_COLORS[[...name].reduce((sum, char) => sum + char.charCodeAt(0), 0) % AVATAR_COLORS.length];
// Material "verified" seal, matching Icons.verified_rounded in the mobile app.
function VerifiedIcon() { return <svg className="verified-icon" width="1em" height="1em" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M23 12l-2.44-2.79.34-3.69-3.61-.82-1.89-3.2L12 2.96 8.6 1.5 6.71 4.69 3.1 5.5l.34 3.7L1 12l2.44 2.79-.34 3.7 3.61.82L8.6 22.5l3.4-1.47 3.4 1.46 1.89-3.19 3.61-.82-.34-3.69L23 12zm-12.91 4.72l-3.8-3.81 1.48-1.48 2.32 2.33 5.85-5.87 1.48 1.48-7.33 7.35z"/></svg>; }
function HeartIcon({ filled }: { filled: boolean }) { return <svg width="18" height="18" viewBox="0 0 24 24" fill={filled ? 'currentColor' : 'none'} stroke="currentColor" strokeWidth="2" strokeLinejoin="round" aria-hidden="true"><path d="M12 20.5s-7.5-4.4-9.3-9.2C1.5 8 3.6 4.5 7.1 4.5c2 0 3.5 1.1 4.9 2.9 1.4-1.8 2.9-2.9 4.9-2.9 3.5 0 5.6 3.5 4.4 6.8-1.8 4.8-9.3 9.2-9.3 9.2z"/></svg>; }
function ChatIcon() { return <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinejoin="round" aria-hidden="true"><path d="M20.5 11.6c0 4.3-3.8 7.7-8.5 7.7-1.1 0-2.1-.2-3.1-.5L4 20.5l1.3-3.9c-1.1-1.4-1.8-3.1-1.8-5 0-4.3 3.8-7.7 8.5-7.7s8.5 3.4 8.5 7.7z"/></svg>; }
function ShareIcon() { return <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M12 15V3.5M7.5 8 12 3.5 16.5 8"/><path d="M5 12.5v6a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-6"/></svg>; }
function EyeIcon() { return <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/></svg>; }
function EyeOffIcon() { return <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M10.6 5.1A10.4 10.4 0 0 1 12 5c6.4 0 10 7 10 7a17.6 17.6 0 0 1-2.9 3.8M6.6 6.6A17.4 17.4 0 0 0 2 12s3.6 7 10 7a9.7 9.7 0 0 0 5.4-1.6"/><path d="M9.9 9.9a3 3 0 0 0 4.2 4.2"/><path d="M2 2l20 20"/></svg>; }
function Avatar({ name, color = 'lilac', onClick }: {name:string;color?:string;onClick?:()=>void}) { if (color === 'anonymous') return <button type="button" onClick={onClick} className="member-avatar anonymous" aria-label="Anonymous member" title="Shared anonymously"><EyeOffIcon/></button>; const initials = name === 'Anonymous' ? 'AN' : name === 'You' ? 'TM' : name.split(' ').map(p => p[0]).slice(0,2).join('').toUpperCase(); return <button type="button" onClick={onClick} className={`member-avatar ${color}`} aria-label={name}>{initials}</button>; }
function AppleIcon() { return <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true"><path fill="currentColor" d="M16.37 12.6c-.02-2.2 1.8-3.26 1.88-3.31-1.03-1.5-2.62-1.7-3.19-1.73-1.36-.14-2.65.8-3.34.8-.69 0-1.75-.78-2.88-.76-1.48.02-2.85.86-3.61 2.19-1.54 2.67-.39 6.62 1.11 8.79.73 1.06 1.6 2.25 2.75 2.2 1.1-.04 1.52-.71 2.85-.71 1.33 0 1.71.71 2.88.69 1.19-.02 1.94-1.08 2.66-2.14.84-1.23 1.19-2.42 1.21-2.48-.03-.01-2.31-.89-2.32-3.54ZM14.18 6.13c.61-.74 1.02-1.76.91-2.78-.88.04-1.94.59-2.57 1.32-.56.65-1.06 1.69-.93 2.69.98.08 1.98-.5 2.59-1.23Z"/></svg>; }
function PlayIcon() { return <svg viewBox="0 0 24 24" width="19" height="19" aria-hidden="true"><path fill="#34a853" d="M3.6 2.3 13.4 12l-9.8 9.7c-.35-.2-.6-.6-.6-1.1V3.4c0-.5.25-.9.6-1.1Z"/><path fill="#fbbc04" d="m16.7 15.3-3.3-3.3 3.3-3.3 3.7 2.1c1.1.6 1.1 1.8 0 2.4l-3.7 2.1Z"/><path fill="#ea4335" d="M16.7 15.3 13.4 12l-9.8 9.7c.4.2.9.2 1.4-.1l11.7-6.3Z"/><path fill="#4285f4" d="M16.7 8.7 5 2.4c-.5-.3-1-.3-1.4-.1l9.8 9.7 3.3-3.3Z"/></svg>; }
// In-feed card pointing members to the native apps; the visitor's own platform is listed first.
function AppPromoCard({ trending = false, onDismiss }: { trending?: boolean; onDismiss: () => void }) {
  const ios = /iphone|ipad|ipod|macintosh/i.test(navigator.userAgent);
  const stores = [
    { id: 'ios', href: IOS_APP_URL, icon: <AppleIcon/>, small: 'Download on the', label: 'App Store' },
    { id: 'android', href: ANDROID_APP_URL, icon: <PlayIcon/>, small: 'Get it on', label: 'Google Play' },
  ];
  if (!ios) stores.reverse();
  return <aside className={`app-promo ${trending ? 'trending' : ''}`} aria-label="Get the Office Gossip app">
    <button type="button" className="app-promo-close" aria-label="Hide this card" onClick={onDismiss}>×</button>
    <div className="app-promo-phone" aria-hidden="true"><span><img src="/brand-mark.svg" alt=""/></span><i/><i/></div>
    <div className="app-promo-copy">
      <span className="app-promo-eyebrow">{trending ? '🔥 NEVER MISS WHAT’S HOT' : '📱 OFFICE GOSSIP ON THE GO'}</span>
      <b>{trending ? 'Catch trending conversations the moment they heat up' : 'Your company community, right in your pocket'}</b>
      <p>{trending ? 'Get the app for instant alerts when posts you care about start trending.' : 'Post, react and keep up with coworkers anywhere with the free app.'}</p>
      <div className="app-promo-stores">{stores.map(store => <a key={store.id} className="store-badge" href={store.href} target="_blank" rel="noreferrer">{store.icon}<span><small>{store.small}</small>{store.label}</span></a>)}</div>
    </div>
  </aside>;
}
// Rank medal, heat label and a bar relative to the #1 post.
function TrendBanner({ rank, heat, topHeat }: { rank: number; heat: number; topHeat: number }) {
  const share = topHeat <= 0 ? 1 : Math.min(1, Math.max(.06, heat / topHeat));
  const label = rank === 1 ? 'Hottest right now' : share >= .6 ? 'Heating up' : 'Rising';
  return <div className="trend-banner"><span className={`trend-medal ${rank <= 3 ? `medal-${rank}` : ''}`} aria-label={`Rank ${rank}`}>{rank}</span><div><span className="trend-banner-line"><b>{rank <= 3 && <i aria-hidden="true">🔥</i>}{label}</b><small>{heat} {heat === 1 ? 'interaction' : 'interactions'}</small></span><span className="trend-banner-bar"><i style={{ width: `${share * 100}%` }}/></span></div></div>;
}
function PostCard({ post, onLike, onComment, onOption, company, rank, topHeat = 0 }: {post:Post;onLike:()=>void;onComment:()=>void;onOption:(option:PostOptionId)=>void;company:string;rank?:number;topHeat?:number}) {
  const [menuOpen, setMenuOpen] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!menuOpen) return;
    const close = (event: MouseEvent | KeyboardEvent) => { if (event instanceof KeyboardEvent ? event.key === 'Escape' : !menuRef.current?.contains(event.target as Node)) setMenuOpen(false); };
    document.addEventListener('mousedown', close); document.addEventListener('keydown', close);
    return () => { document.removeEventListener('mousedown', close); document.removeEventListener('keydown', close); };
  }, [menuOpen]);
  return <article className={`post-card ${post.isArchived ? 'archived' : ''} ${rank ? `trend-card ${rank <= 3 ? 'podium' : ''}` : ''}`}>{rank && <TrendBanner rank={rank} heat={post.likes + post.comments} topHeat={topHeat}/>}<header className="post-head"><Avatar name={post.person} color={post.anonymous?'anonymous':'rose'}/><div className="post-byline"><b>{post.person}{post.isAdmin && <span className="admin-tag" title="Posted by the Office Gossip team"><VerifiedIcon/>Admin</span>}{post.isArchived && <span className="archived-tag" title="Only you can see archived posts">Archived</span>}{post.isPending && <span className="pending-tag" title="Only you can see this until your company is approved">Waiting for approval</span>}</b><span>{post.anonymous?'Shared anonymously':post.role} {post.role&&'·'} {post.time}</span></div><div className="post-menu-wrap" ref={menuRef}><button className="more-button" aria-label="More post options" aria-haspopup="menu" aria-expanded={menuOpen} onClick={() => setMenuOpen(open => !open)}>⋮</button>{menuOpen && <div className="post-menu" role="menu">{POST_OPTIONS.filter(option => option.visible(post)).map(option => <button key={option.id} type="button" role="menuitem" className={option.danger ? 'danger' : ''} onClick={() => { setMenuOpen(false); onOption(option.id); }}><span>{option.icon}</span>{typeof option.label === 'function' ? option.label(post) : option.label}</button>)}</div>}</div></header>{post.tag&&<span className="post-tag">{post.tag}</span>}<p className="post-body">{post.body}</p><div className="post-company">⌂ &nbsp;{company}</div><div className="post-actions"><button className={post.liked?'liked':''} onClick={onLike} disabled={post.isPending}><span><HeartIcon filled={Boolean(post.liked)}/></span> {post.likes} <small>likes</small></button>{COMMENTS_ENABLED && <button onClick={onComment} disabled={post.isPending} aria-label={`${post.comments} comments`}><span><ChatIcon/></span> {post.comments} <small>comments</small></button>}<button className="share-post" aria-label="Share post" onClick={() => navigator.clipboard?.writeText(post.body).then(()=>{})}><span><ShareIcon/></span> Share</button></div></article>; }
function CompanyPicker({ user, onClose, onRefresh, onSaved }: { user: MemberUser; onClose: () => void; onRefresh: () => Promise<MemberData>; onSaved: (user: MemberUser) => void }) {
  const [companies, setCompanies] = useState<CompanyOption[]>([]);
  const [loading, setLoading] = useState(false);
  const [companyId, setCompanyId] = useState('');
  const [requestNew, setRequestNew] = useState(false);
  const [companyName, setCompanyName] = useState('');
  const [companyWebsite, setCompanyWebsite] = useState('');
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');
  const [pending, setPending] = useState(user.companyRequestPending);
  // Starts from the company typed at sign-up: selected if it's listed now, else prefilled as a new request.
  const registeredApplied = useRef(false);
  const applyRegisteredCompany = useCallback((list: CompanyOption[]) => {
    if (registeredApplied.current) return;
    registeredApplied.current = true;
    const name = user.requestedCompany?.name?.trim();
    if (!name) return;
    const key = (value: string) => value.trim().replace(/\s+/g, ' ').toLowerCase();
    const match = list.find(company => key(company.name) === key(name));
    if (match) { setCompanyId(current => current || match.id); return; }
    setRequestNew(true); setCompanyName(name); setCompanyWebsite(user.requestedCompany?.website ?? '');
  }, [user.requestedCompany]);
  const loadCompanies = useCallback(() => { setLoading(true); setMessage(''); api<CompanyOption[]>('/api/public/companies').then(list => { setCompanies(list); setCompanyId(current => list.some(company => company.id === current) ? current : ''); applyRegisteredCompany(list); }).catch(() => setMessage('Could not load the company list. Please try again.')).finally(() => setLoading(false)); }, [applyRegisteredCompany]);
  useEffect(() => { if (!pending) loadCompanies(); }, [pending, loadCompanies]);
  async function checkStatus() {
    setBusy(true); setMessage('');
    try { const latest = await onRefresh(); if (latest.user?.company) onSaved(latest.user); else if (!latest.user?.companyRequestPending) { registeredApplied.current = true; setPending(false); setMessage('Your request was not approved. Choose another company below.'); } else setMessage('Still waiting for approval. We’ll let you know once it’s approved.'); }
    catch { setMessage('Could not check the status. Please try again.'); }
    finally { setBusy(false); }
  }
  async function submit(event: React.FormEvent) {
    event.preventDefault(); setBusy(true); setMessage('');
    try {
      const body = requestNew ? { companyName: companyName.trim(), ...(companyWebsite.trim() ? { companyWebsite: companyWebsite.trim() } : {}) } : { companyId };
      const result = await api<{ user: MemberUser }>('/api/me/company', { method: 'POST', body: JSON.stringify(body) });
      onSaved(result.user);
    } catch (error) { setMessage(error instanceof Error ? error.message : 'Could not save your company. Please try again.'); }
    finally { setBusy(false); }
  }
  return <div className="modal-shade" onMouseDown={e => { if (e.currentTarget === e.target && !busy) onClose(); }}><div className="compose-modal post-dialog company-picker" role="dialog" aria-modal="true" aria-labelledby="company-picker-title"><button type="button" className="close-modal" aria-label="Close" onClick={onClose}>×</button>
    {pending ? <>
      <span className="overline">YOUR COMPANY</span><h2 id="company-picker-title">Waiting for approval</h2>
      <p className="post-dialog-copy">You asked to bring <b>“{user.pendingCompanyName}”</b> to Office Gossip. Our team is reviewing it, and you can post as soon as it’s approved.</p>
      <div className="company-pending-card"><span aria-hidden="true">◷</span><div><b>{user.pendingCompanyName}</b><small>Pending admin approval</small></div></div>
      {message && <p className="company-picker-message" role="status">{message}</p>}
      <div className="post-dialog-actions"><button type="button" className="outline-button" onClick={onClose}>Close</button><button type="button" className="share-button" disabled={busy} onClick={() => void checkStatus()}>{busy ? 'Checking…' : 'Check status'}</button></div>
    </> : <form className="auth-form" onSubmit={submit}>
      <div><span className="overline">YOUR COMPANY</span><h2 id="company-picker-title">Choose your company</h2><p className="post-dialog-copy">Join your company community to see your coworkers’ posts and start sharing.</p></div>
      {requestNew ? <>
        <label><span className="field-label">Company name <em className="field-required">Required</em></span><input autoFocus value={companyName} onChange={e => setCompanyName(e.target.value)} required minLength={2} maxLength={100} autoComplete="organization" placeholder="Enter your company name"/></label>
        <label><span className="field-label">Company website <em className="field-optional">Optional</em></span><input value={companyWebsite} onChange={e => setCompanyWebsite(e.target.value)} inputMode="url" autoComplete="url" placeholder={defaultCompanyDomain(companyName) || 'yourcompany.com'}/></label>
        <p className="company-request-note">We’ll send this company to the Office Gossip team for review. You can post once it’s approved.</p>
      </> : <label>Company<span className="company-select-row"><select value={companyId} onChange={e => setCompanyId(e.target.value)} required disabled={loading || companies.length === 0}>
        <option value="">{loading ? 'Loading companies…' : companies.length ? 'Select your company' : 'No companies available'}</option>
        {companies.map(company => <option value={company.id} key={company.id}>{company.name}</option>)}
      </select><button type="button" className="company-refresh" onClick={loadCompanies} disabled={loading} aria-label="Refresh company list" title="Refresh company list"><span className={loading ? 'spinning' : ''}>↻</span></button></span></label>}
      <button type="button" className="company-choice-toggle" onClick={() => { setRequestNew(!requestNew); setMessage(''); }}>{requestNew ? '← Choose a listed company' : 'My company isn’t listed'}</button>
      {message && <p className="company-picker-message" role="alert">{message}</p>}
      <button className="share-button" disabled={busy || (requestNew ? companyName.trim().length < 2 : !companyId)}>{busy ? 'Saving…' : requestNew ? 'Request company' : 'Join company'} <span>→</span></button>
    </form>}
  </div></div>;
}
// Shown on Profile until the member can post to their verified company: what's done, what's left, one next step.
function PostingSetupCard({ user, onEditProfile, onChooseCompany }: { user: MemberUser; onEditProfile: () => void; onChooseCompany: () => void }) {
  const hasName = Boolean(user.name.trim());
  const pending = !user.company && user.companyRequestPending;
  const tone = pending && hasName ? 'pending' : 'action';
  const [icon, eyebrow, title, detail] = !hasName
    ? ['✎', 'FINISH SETTING UP', 'Add your name to start posting', 'Coworkers see your name and role on the posts you share.']
    : pending
      ? ['◷', 'ALMOST THERE', 'Waiting for company approval', `You can post now. Posts stay visible only to you until “${user.pendingCompanyName}” is approved, then they’re shared in Global and your company community.`]
      : ['▦', 'FINISH SETTING UP', 'Join your company to start posting', 'Pick your company so your posts reach your coworkers and the Global community.'];
  const steps = [
    { label: 'Display name', detail: hasName ? user.name : 'Not added yet', state: hasName ? 'done' : 'todo' },
    { label: 'Company', detail: user.company?.name || (pending ? `${user.pendingCompanyName} · awaiting approval` : 'Not chosen yet'), state: user.company ? 'done' : pending ? 'pending' : 'todo' },
  ];
  const done = steps.filter(step => step.state === 'done').length;
  return <section className={`setup-card ${tone}`} aria-label="Posting setup">
    <header><span className="setup-card-icon" aria-hidden="true">{icon}</span><div><span className="setup-card-eyebrow">{eyebrow} · {done}/2</span><b>{title}</b><p>{detail}</p></div></header>
    <div className="setup-card-progress" aria-hidden="true"><i style={{ width: `${Math.max(done * 50, pending ? 75 : 6)}%` }}/></div>
    <ol className="setup-card-steps">{steps.map(step => <li key={step.label} className={step.state}><i aria-hidden="true">{step.state === 'done' ? '✓' : step.state === 'pending' ? '◷' : '○'}</i><span><b>{step.label}</b><small>{step.detail}</small></span><em>{step.state === 'done' ? 'Done' : step.state === 'pending' ? 'Pending' : 'To do'}</em></li>)}</ol>
    <button type="button" className={tone === 'pending' ? 'secondary' : ''} onClick={!hasName ? onEditProfile : onChooseCompany}>{!hasName ? 'Complete profile' : pending ? 'Check status' : 'Choose company'} <span aria-hidden="true">→</span></button>
  </section>;
}
function CompanyBadge({ user }: { user?: MemberUser }) { const [label, tone] = companyVerified(user) ? ['Verified', 'active'] : user?.companyRequestPending ? ['Pending', 'pending'] : ['None', 'none']; return <span className={`company-badge ${tone}`}>{tone === 'active' && <VerifiedIcon/>}{label}</span>; }
function PageHeading({eyebrow,title,detail}:{eyebrow:string;title:string;detail:string}) { return <div className="page-heading"><span className="overline">{eyebrow}</span><h1>{title}</h1><p>{detail}</p></div>; }
type EmptyAction = { label: string; onClick: () => void; secondary?: boolean };
function Empty({ title, detail, icon = '✿', eyebrow, tone = 'default', actions = [] }: { title: string; detail: string; icon?: string; eyebrow?: string; tone?: 'default' | 'loading' | 'error'; actions?: EmptyAction[] }) {
  return <div className={`member-empty ${tone}`} role={tone === 'error' ? 'alert' : 'status'} aria-busy={tone === 'loading'}><span className="member-empty-icon">{icon}</span>{eyebrow && <span className="member-empty-eyebrow">{eyebrow}</span>}<b>{title}</b><p>{detail}</p>{actions.length > 0 && <div className="member-empty-actions">{actions.map(action => <button type="button" key={action.label} className={action.secondary ? 'secondary' : ''} onClick={action.onClick}>{action.label}</button>)}</div>}</div>;
}
const monthYear = (iso?: string) => iso ? new Date(iso).toLocaleDateString([], { month: 'short', year: 'numeric' }) : '';
const initialsOf = (text: string) => text.trim().split(/\s+/).map(part => part[0]).slice(0, 2).join('').toUpperCase() || '?';
function ProfileTile({ icon, title, detail, trailing, onClick }: { icon: string; title: string; detail: string; trailing?: React.ReactNode; onClick?: () => void }) {
  const body = <><span className="pv-tile-icon" aria-hidden="true">{icon}</span><span className="pv-tile-copy"><b>{title}</b><small>{detail}</small></span>{trailing}{onClick && trailing === undefined && <span className="pv-chevron" aria-hidden="true">›</span>}</>;
  return onClick ? <button type="button" className="pv-tile" onClick={onClick}>{body}</button> : <div className="pv-tile">{body}</div>;
}
function ProfileView({ data, pushEnabled, pushBusy, onEnablePush, onEdit, onInvite, onChooseCompany, onVerifyEmail, onOpen, onSignOut, onDelete }: {
  data: MemberData; pushEnabled: boolean; pushBusy: boolean; onEnablePush: () => void; onEdit: () => void; onInvite: () => void; onChooseCompany: () => void;
  onVerifyEmail: () => void; onOpen: (page: Webpage) => void; onSignOut: () => void; onDelete: () => void;
}) {
  const user = data.user;
  const name = data.profile.display_name.trim();
  const role = data.profile.role_title?.trim();
  const bio = data.profile.bio?.trim();
  const company = user?.company ?? null;
  const overline = company?.name || data.company?.name || (user?.companyRequestPending ? `${user.pendingCompanyName} · pending` : 'Your space');
  const emailVerified = user?.emailVerified === true;
  const help = WEBPAGES[0];
  const stats = [{ icon: '💬', value: data.stats.posts, label: 'Posts', tone: 'violet' }, { icon: '♡', value: data.stats.reactions, label: 'Reactions', tone: 'rose' }, { icon: '✎', value: data.stats.comments, label: 'Comments', tone: 'green' }];
  return <div className="pv">
    <section className="pv-hero">
      <div className="pv-hero-copy"><span className="pv-overline">{overline}</span><h1>{name || 'Add your name'}</h1><p>{role || 'Add your role'}<br/>{data.email}</p></div>
      <div className="pv-hero-side"><span className="pv-avatar" aria-hidden="true"><span>{initialsOf(name || data.email)}</span></span><button type="button" className="pv-edit" aria-label="Edit profile" title="Edit profile" onClick={onEdit}>✎</button></div>
    </section>
    <div className="pv-stats">{stats.map(stat => <div key={stat.label} className={`pv-stat ${stat.tone}`}><span aria-hidden="true">{stat.icon}</span><b>{stat.value}</b><small>{stat.label}</small></div>)}</div>
    <div className="pv-actions"><button type="button" onClick={onInvite}><span aria-hidden="true">＋</span>Invite</button><button type="button" onClick={() => onOpen(help)}><span aria-hidden="true">?</span>Help</button></div>
    {bio && <section className="pv-card pv-about"><span className="pv-label">About me</span><p>{bio}</p></section>}
    {user && (!canPost(user) || !companyVerified(user)) && <PostingSetupCard user={user} onEditProfile={onEdit} onChooseCompany={onChooseCompany}/>}
    <span className="pv-section">Account</span>
    <section className="pv-card">
      <ProfileTile icon="✉" title="Email" detail={data.email} onClick={!emailVerified && EMAIL_OTP_ENABLED ? onVerifyEmail : undefined} trailing={emailVerified ? <span className="pv-tag ok"><VerifiedIcon/>Verified</span> : <span className="pv-tag bad">{EMAIL_OTP_ENABLED ? 'Not verified · Verify' : 'Not verified'}</span>}/>
      <ProfileTile icon="▦" title="Company" detail={company?.name || (user?.pendingCompanyName ? `${user.pendingCompanyName} · Waiting for approval` : 'Not a member yet · Choose your company')} trailing={<span className="pv-trailing"><CompanyBadge user={user}/>{!company && <span className="pv-chevron" aria-hidden="true">›</span>}</span>} onClick={!company ? onChooseCompany : company.website ? () => onOpen({ title: company.name, url: company.website! }) : undefined}/>
    </section>
    <span className="pv-section">Preferences</span>
    <section className="pv-card">
      <ProfileTile icon="🔔" title="Push notifications" detail={pushEnabled ? 'Enabled on this device' : 'Get notified about community activity'} trailing={pushBusy ? <span className="feed-pager-spinner pv-spinner" aria-label="Enabling"/> : pushEnabled ? <span className="pv-check" aria-label="Enabled">✓</span> : undefined} onClick={pushEnabled || pushBusy ? undefined : onEnablePush}/>
    </section>
    <span className="pv-section">Support &amp; legal</span>
    <section className="pv-card">{WEBPAGES.map(page => <ProfileTile key={page.path} icon={page.icon} title={page.title} detail={page.detail} onClick={() => onOpen(page)}/>)}</section>
    <button type="button" className="pv-signout" onClick={onSignOut}><span className="pv-tile-icon" aria-hidden="true">⇥</span><span className="pv-tile-copy"><b>Sign out</b><small>Signed in as {data.email}</small></span><span className="pv-chevron" aria-hidden="true">›</span></button>
    <button type="button" className="pv-delete" onClick={onDelete}><span aria-hidden="true">⊖</span>Delete account</button>
    {data.profile.created_at && <p className="pv-since">Member since {monthYear(data.profile.created_at)}</p>}
  </div>;
}
// Sites that send X-Frame-Options/CSP frame-ancestors render blank in the iframe, so "Open in new tab" stays visible.
function WebpageViewer({ page, onClose }: { page: Webpage; onClose: () => void }) {
  const [loading, setLoading] = useState(true);
  const [covered, setCovered] = useState(true);
  const [reloadKey, setReloadKey] = useState(0);
  const host = useMemo(() => { try { return new URL(page.url).host; } catch { return ''; } }, [page.url]);
  // iframe onLoad waits for every image and script, so uncover early and let the progress bar track the rest.
  useEffect(() => { setLoading(true); setCovered(true); const timer = window.setTimeout(() => setCovered(false), 1200); return () => window.clearTimeout(timer); }, [page.url, reloadKey]);
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => { if (event.key === 'Escape') onClose(); };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [onClose]);
  return <div className="modal-shade webpage-shade" onMouseDown={e => { if (e.currentTarget === e.target) onClose(); }}><section className="webpage-modal" role="dialog" aria-modal="true" aria-label={page.title}><header className="webpage-bar"><button type="button" className="webpage-icon-button" aria-label="Close" onClick={onClose}>←</button><div className="webpage-title"><b>{page.title}</b>{host && <small><span aria-hidden="true">🔒</span> {host}</small>}</div><button type="button" className="webpage-icon-button" aria-label="Reload" title="Reload" onClick={() => setReloadKey(key => key + 1)}>↻</button><a className="webpage-icon-button" href={page.url} target="_blank" rel="noopener noreferrer" aria-label="Open in new tab" title="Open in new tab">↗</a><button type="button" className="webpage-icon-button" aria-label="Close" title="Close" onClick={onClose}>×</button>{loading && <i className="webpage-progress"/>}</header><div className="webpage-body">{loading && covered && <div className="webpage-loading"><span>✳</span><b>Loading {page.title.toLowerCase()}…</b><small>If nothing appears, <a href={page.url} target="_blank" rel="noopener noreferrer">open it in a new tab</a>.</small></div>}<iframe key={reloadKey} src={page.url} title={page.title} onLoad={() => { setLoading(false); setCovered(false); }} referrerPolicy="no-referrer" sandbox="allow-scripts allow-same-origin allow-popups allow-forms"/></div></section></div>;
}

// iOS-style banner for when the sign-up code email couldn't be sent and the API returned the code instead.
function OtpNotification({ code, expiresAt, onUse, onClose }: { code: string; expiresAt: number; onUse: () => void; onClose: () => void }) {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => { const timer = window.setInterval(() => setNow(Date.now()), 1000); return () => window.clearInterval(timer); }, []);
  const left = Math.max(0, Math.ceil((expiresAt - now) / 1000));
  useEffect(() => { if (left === 0) onClose(); }, [left, onClose]);
  const countdown = `${Math.floor(left / 60)}:${String(left % 60).padStart(2, '0')}`;
  return <div className="otp-notification" role="alert" aria-live="assertive">
    <button type="button" className="otp-notification-body" onClick={onUse} aria-label={`Use code ${code}`}>
      <span className="otp-notification-icon"><img src="/brand-mark.svg" alt=""/></span>
      <span className="otp-notification-copy"><span className="otp-notification-head"><b>OFFICE GOSSIP</b><small>now</small></span><strong>Your sign-up code</strong><span><em>{code}</em> is your verification code. Expires in {countdown}.</span><small className="otp-notification-tip">We couldn’t email it right now · Tap to fill it in</small></span>
    </button>
    <button type="button" className="otp-notification-close" aria-label="Dismiss" onClick={onClose}>×</button>
  </div>;
}
function VerifyEmailLanding() {
  const [state, setState] = useState<{ status: 'checking' | 'done' | 'error'; text: string }>({ status: 'checking', text: 'Verifying your email…' });
  const started = useRef(false);
  useEffect(() => {
    if (started.current) return; started.current = true;
    const params = new URLSearchParams(window.location.hash.slice(1));
    window.history.replaceState({}, document.title, window.location.pathname);
    const token = params.get('access_token');
    if (!token) { setState({ status: 'error', text: params.get('error_code') === 'otp_expired' ? 'This link has expired or was already used. Request a new one from your profile.' : (params.get('error_description')?.replace(/\+/g, ' ') || 'This verification link is invalid.') }); return; }
    void (async () => {
      try {
        const response = await fetch(`${API_URL}/api/auth/email/confirm-link`, { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` } });
        const body = await response.json().catch(() => ({})) as { email?: string | null; message?: string };
        if (!response.ok) throw new Error(body.message || 'This verification link is invalid or has expired.');
        setState({ status: 'done', text: body.email ? `${body.email} is now verified.` : 'Your email is now verified.' });
      } catch (error) { setState({ status: 'error', text: error instanceof Error ? error.message : 'Could not verify your email.' }); }
    })();
  }, []);
  return <main className="verify-landing"><section className={`verify-landing-card ${state.status}`}>
    <span className="verify-landing-icon" aria-hidden="true">{state.status === 'done' ? '✓' : state.status === 'error' ? '!' : '…'}</span>
    <h1>{state.status === 'done' ? 'Email verified' : state.status === 'error' ? 'Verification failed' : 'Verifying'}</h1>
    <p>{state.text}</p>
    {state.status !== 'checking' && <button type="button" onClick={() => window.location.replace('/')}>Continue to Office Gossip</button>}
  </section></main>;
}

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

createRoot(document.getElementById('root')!).render(<React.StrictMode>{(() => {
  const path = window.location.pathname.replace(/^\/|\/$/g, '');
  if (path === 'verify-email') return <VerifyEmailLanding/>;
  if (DELETE_ACCOUNT_ALIASES.includes(path)) window.history.replaceState(null, '', `/${DELETE_ACCOUNT_PATH}`);
  if (path === DELETE_ACCOUNT_PATH || DELETE_ACCOUNT_ALIASES.includes(path)) return <DeleteAccountPage/>;
  if (LEGAL_ALIASES[path]) { window.history.replaceState(null, '', `/${LEGAL_ALIASES[path]}`); return <LegalPage path={LEGAL_ALIASES[path]}/>; }
  if (LEGAL_PATHS.includes(path)) return <LegalPage path={path}/>;
  return <App/>;
})()}</React.StrictMode>);
