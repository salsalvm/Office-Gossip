import express from 'express';
import { createHmac, randomInt, timingSafeEqual } from 'node:crypto';
import cors from 'cors';
import { createClient, type SupabaseClient, type User } from '@supabase/supabase-js';
import { notifyCompanyMembers, sendUserNotification } from './services/fcm.js';
import { followContent, reactionContent } from './services/notification-content.js';
import { isMailerConfigured, sendCodeEmail } from './services/mailer.js';
import {
  ACCOUNT_DEACTIVATED, accountGraceDays, accountLifecycle, hasPasswordSignIn, isDeactivated, listAccounts, purgeAccount, purgeDueAccounts,
  setAccountStatus, type AccountStatus,
} from './services/accounts.js';

export const app = express();
app.use(cors());
app.use(express.json({ limit: '32kb' }));
app.get('/health', (_req, res) => { res.json({ status: 'ok', service: 'office-gossip-api' }); });

const supabaseUrl = process.env.SUPABASE_URL;
const anonKey = process.env.SUPABASE_ANON_KEY;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const frontendUrl = process.env.FRONTEND_URL ?? 'http://localhost:5173';
const authClient = (): SupabaseClient => {
  if (!supabaseUrl || !anonKey) throw new Error('Supabase auth is not configured');
  return createClient(supabaseUrl, anonKey, { auth: { persistSession: false, autoRefreshToken: false, flowType: 'implicit' } });
};
export const adminClient = (): SupabaseClient => {
  if (!supabaseUrl || !serviceKey) throw new Error('Supabase database access is not configured');
  return createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
};
const errorResponse = (res: express.Response, httpStatus: number, message: string, data: Record<string, unknown> = {}) =>
  res.status(httpStatus).json({ message, status: false, data });

const fail = (res: express.Response, error: unknown) => {
  const message = error instanceof Error ? error.message : 'Request failed';
  if (message.includes('not configured')) return errorResponse(res, 503, message);
  const candidateStatus = typeof error === 'object' && error !== null && 'status' in error
    ? Number((error as { status?: unknown }).status)
    : NaN;
  const httpStatus = Number.isInteger(candidateStatus) && candidateStatus >= 400 && candidateStatus <= 599 ? candidateStatus : 500;
  return errorResponse(res, httpStatus, message);
};

// Full member profile returned with auth tokens so clients can cache it after login/register.
// Sign-up does not confirm emails yet, so verification is our own server-only flag (app_metadata
// can't be edited by members). It flips to true only after the member verifies their email with an OTP.
const isEmailVerified = (user: User) => user.app_metadata?.email_verified === true;

async function userPayload(db: SupabaseClient, user: User): Promise<Record<string, unknown>> {
  const [profile, membership, request, latestRequest, posts, likes, comments] = await Promise.all([
    db.from('profiles').select('display_name,username,role_title,bio,theme_preference,created_at').eq('id', user.id).maybeSingle(),
    db.from('company_memberships').select('company:companies(id,name,website_domain)').eq('user_id', user.id).eq('status', 'active').limit(1).maybeSingle(),
    db.from('company_requests').select('company_name').eq('requested_by', user.id).eq('status', 'pending').order('created_at', { ascending: false }).limit(1).maybeSingle(),
    db.from('company_requests').select('company_name,website_domain').eq('requested_by', user.id).order('created_at', { ascending: false }).limit(1).maybeSingle(),
    db.from('posts').select('id', { count: 'exact', head: true }).eq('author_id', user.id).eq('status', 'active'),
    db.from('post_likes').select('post_id', { count: 'exact', head: true }).eq('user_id', user.id),
    db.from('comments').select('id', { count: 'exact', head: true }).eq('author_id', user.id),
  ]);
  for (const result of [profile, membership, request, latestRequest, posts, likes, comments]) if (result.error) throw result.error;
  // A request whose company is already active (e.g. added from the admin Companies page) is approved on the spot.
  if (!membership.data && request.data) {
    const existing = await findCompanyByName(db, normalizeCompanyName(request.data.company_name));
    if (existing?.status === 'active' && await fulfillPendingRequests(db, existing.id, request.data.company_name)) return userPayload(db, user);
  }
  const company = membership.data?.company as unknown as { id: string; name: string; website_domain: string | null } | null | undefined;
  return {
    id: user.id,
    email: user.email ?? '',
    emailVerified: isEmailVerified(user),
    name: profile.data?.display_name || String(user.user_metadata?.display_name ?? user.user_metadata?.full_name ?? ''),
    username: profile.data?.username ?? null,
    roleTitle: profile.data?.role_title ?? null,
    bio: profile.data?.bio ?? null,
    themePreference: profile.data?.theme_preference ?? 'system',
    company: company ? { id: company.id, name: company.name, website: company.website_domain ? `https://${company.website_domain.replace(/^https?:\/\//i, '')}` : null } : null,
    // True once the member belongs to a registered (active) company; false while it awaits admin approval.
    companyVerified: Boolean(company),
    companyRequestPending: Boolean(request.data),
    pendingCompanyName: request.data?.company_name ?? null,
    // The company typed at sign-up (or last requested), so pickers can start from it.
    requestedCompany: latestRequest.data ? { name: latestRequest.data.company_name, website: latestRequest.data.website_domain ?? null } : null,
    stats: { posts: posts.count ?? 0, reactions: likes.count ?? 0, comments: comments.count ?? 0 },
    createdAt: profile.data?.created_at ?? user.created_at,
  };
}

// Company names are unique case-insensitively ("real11" and "Real11" are the same company).
const normalizeCompanyName = (value: unknown) => typeof value === 'string' ? value.trim().replace(/\s+/g, ' ') : '';
const escapeLike = (value: string) => value.replace(/[%_\\]/g, '\\$&');

async function findCompanyByName(db: SupabaseClient, name: string) {
  const { data, error } = await db.from('companies').select('id,status').ilike('name', escapeLike(name)).limit(1).maybeSingle();
  if (error) throw error;
  return data as { id: string; status: string } | null;
}

// Requested companies get a website: the member's (optional) entry, else "<name>.com", e.g. "Acme Labs" → "acmelabs.com".
const requestedCompanyDomain = (companyName: unknown, companyWebsite: unknown) => {
  const slug = normalizeCompanyName(companyName).toLowerCase().replace(/[^a-z0-9]/g, '');
  return cleanDomain(companyWebsite) || (slug ? `${slug}.com` : null);
};
const isValidDomain = (domain: string) => /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/.test(domain) && domain.length <= 253;

async function checkCompanyChoice(db: SupabaseClient, companyId: unknown, companyName: unknown, companyWebsite?: unknown): Promise<string | null> {
  if ((!companyId && !companyName) || (companyId && companyName)) return 'Choose a company or request a new one.';
  if (companyName && typeof companyWebsite === 'string' && companyWebsite.trim()) {
    const domain = cleanDomain(companyWebsite);
    if (!domain || !isValidDomain(domain)) return 'Enter a valid company website, like acme.com.';
  }
  if (companyId) {
    const { data, error } = await db.from('companies').select('id').eq('id', String(companyId)).eq('status', 'active').maybeSingle();
    if (error) throw error;
    return data ? null : 'Choose an active company from the list.';
  }
  const name = normalizeCompanyName(companyName);
  if (name.length < 2 || name.length > 100) return 'Company name must be between 2 and 100 characters.';
  const existing = await findCompanyByName(db, name);
  if (existing && existing.status === 'disabled') return 'This company is not accepting new members right now.';
  return null;
}

// Joins an existing company (matched case-insensitively) or files a single pending request; returns whether approval is pending.
async function assignCompany(db: SupabaseClient, userId: string, companyId: unknown, companyName: unknown, companyWebsite?: unknown) {
  let targetId = companyId ? String(companyId) : null;
  const name = normalizeCompanyName(companyName);
  if (!targetId) {
    const existing = await findCompanyByName(db, name);
    if (existing?.status === 'active') targetId = existing.id;
  }
  if (targetId) {
    const membership = await db.from('company_memberships').upsert({ user_id: userId, company_id: targetId, status: 'active', join_method: 'request' }, { onConflict: 'user_id,company_id' });
    if (membership.error) throw membership.error;
    await publishHeldPosts(db, [userId], targetId);
    return false;
  }
  const { data: duplicate, error: duplicateError } = await db.from('company_requests').select('id').eq('requested_by', userId).eq('status', 'pending').ilike('company_name', escapeLike(name)).limit(1).maybeSingle();
  if (duplicateError) throw duplicateError;
  if (!duplicate) {
    const request = await db.from('company_requests').insert({ requested_by: userId, company_name: name, website_domain: requestedCompanyDomain(name, companyWebsite) });
    if (request.error) throw request.error;
  }
  return true;
}

// The admin account signs in only through /api/admin/login; it must never get a member session.
// Rejections mirror ordinary auth failures so the admin email can't be discovered from responses.
const INVALID_CREDENTIALS_MESSAGE = 'Email or password is incorrect.';
const EMAIL_TAKEN_MESSAGE = 'An account with this email already exists.';
const INVALID_SESSION_MESSAGE = 'Your session is invalid or expired.';
const isAdminEmail = (email: unknown) => typeof email === 'string' && Boolean(process.env.ADMIN_EMAIL)
  && email.trim().toLowerCase() === String(process.env.ADMIN_EMAIL).trim().toLowerCase();

// Public signup choices are restricted to active companies; privileged DB credentials stay server-side.
app.get('/api/public/companies', async (_req, res) => {
  try {
    const { data, error } = await adminClient().from('companies').select('id,name').eq('status', 'active').order('name');
    if (error) throw error;
    res.json(data ?? []);
  } catch (error) { fail(res, error); }
});

app.get('/api/public/account-policy', (_req, res) => { res.json({ graceDays: accountGraceDays() }); });

// Sign-up verifies the email before the account exists: Supabase creates a pending user and emails a code.
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
async function isRegisteredUser(db: SupabaseClient, userId: string) {
  const { data, error } = await db.from('profiles').select('display_name').eq('id', userId).maybeSingle();
  if (error) throw error;
  return Boolean(data?.display_name?.trim());
}

// Fallback codes: with DEV_MASTER_OTP set, its code passes sign-up (even if the email can't be sent) but the
// account stays unverified. DEV_MASTER_OTP=dynamic issues a random single-use code per email, stored in
// public.signup_otps (database/scheme.sql) and listed on the admin console's "OTP codes" page;
// any other value is one fixed code for everyone.
const devMasterOtp = () => (process.env.DEV_MASTER_OTP ?? '').trim();
const isDynamicDevOtp = () => devMasterOtp().toLowerCase() === 'dynamic';
const DEV_OTP_TTL_MS = 10 * 60 * 1000;
const DEV_OTP_MAX_ATTEMPTS = 5;
const isMissingTable = (error: { code?: string } | null) => error?.code === '42P01' || error?.code === 'PGRST205';
const OTP_TABLE_MISSING_MESSAGE = 'Sign-up codes are not set up yet. Run the signup_otps block of database/scheme.sql in Supabase.';
// Stores a fresh single-use code for this email (replacing any earlier one) and returns it.
async function issueOtp(db: SupabaseClient, email: string, name: string | null): Promise<string> {
  const code = randomInt(0, 1_000_000).toString().padStart(6, '0');
  const row = {
    email, code, attempts: 0, used_at: null, emailed: false,
    created_at: new Date().toISOString(), expires_at: new Date(Date.now() + DEV_OTP_TTL_MS).toISOString(),
  };
  let { error } = await db.from('signup_otps').upsert({ ...row, name }, { onConflict: 'email' });
  // PGRST204: an older signup_otps table without the `name`/`emailed` columns from database/scheme.sql.
  if (error?.code === 'PGRST204') {
    console.warn('signup_otps is missing columns; run `alter table public.signup_otps add column if not exists name text, add column if not exists emailed boolean not null default false;`.');
    const { emailed: _emailed, ...legacyRow } = row;
    ({ error } = await db.from('signup_otps').upsert(legacyRow, { onConflict: 'email' }));
  }
  if (isMissingTable(error)) throw Object.assign(new Error(OTP_TABLE_MISSING_MESSAGE), { status: 503 });
  if (error) throw error;
  return code;
}
async function issueDevOtp(db: SupabaseClient, email: string, name: string | null): Promise<string | null> {
  if (!isDynamicDevOtp()) return null;
  const code = await issueOtp(db, email, name);
  console.log(`[DEV_MASTER_OTP] Sign-up code for ${email}: ${code}`);
  return code;
}
// Only codes that actually reached the inbox prove the member owns the address.
async function markOtpEmailed(db: SupabaseClient, email: string) {
  const { error } = await db.from('signup_otps').update({ emailed: true }).eq('email', email);
  if (error?.code === 'PGRST204' || error?.code === '42703') console.warn('signup_otps.emailed is missing; emailed codes will verify accounts as unverified until it is added.');
  else if (error) throw error;
}
async function consumeStoredOtp(db: SupabaseClient, email: string, code: string): Promise<{ ok: boolean; emailed: boolean }> {
  const rejected = { ok: false, emailed: false };
  let { data: entry, error } = await db.from('signup_otps').select('code,attempts,expires_at,used_at,emailed').eq('email', email).maybeSingle();
  if (error?.code === '42703') ({ data: entry, error } = await db.from('signup_otps').select('code,attempts,expires_at,used_at').eq('email', email).maybeSingle() as any);
  if (isMissingTable(error)) return rejected;
  if (error) throw error;
  if (!entry || entry.used_at || Date.parse(entry.expires_at) < Date.now() || entry.attempts >= DEV_OTP_MAX_ATTEMPTS) return rejected;
  if (!safeEqual(code, entry.code)) {
    await db.from('signup_otps').update({ attempts: entry.attempts + 1 }).eq('email', email);
    return rejected;
  }
  // Conditional update so two concurrent requests can't both spend the same code.
  const { data: used, error: useError } = await db.from('signup_otps').update({ used_at: new Date().toISOString() })
    .eq('email', email).eq('code', code).is('used_at', null).select('email').maybeSingle();
  if (useError) throw useError;
  return { ok: Boolean(used), emailed: Boolean(used) && (entry as { emailed?: boolean }).emailed === true };
}
async function consumeDevOtp(db: SupabaseClient, email: string, code: string) {
  if (devMasterOtp() && !isDynamicDevOtp()) return { ok: safeEqual(code, devMasterOtp()), emailed: false };
  if (!isDynamicDevOtp() && !isMailerConfigured()) return { ok: false, emailed: false };
  return consumeStoredOtp(db, email, code);
}
const BYPASS_TOKEN_TTL_MS = 30 * 60 * 1000;
const bypassSecret = () => process.env.SUPABASE_SERVICE_ROLE_KEY ?? '';
// `verified` is true only when the code was emailed to this address (not a fallback code).
const signBypassToken = (email: string, verified = false) => {
  const payload = Buffer.from(JSON.stringify({ email, verified, exp: Date.now() + BYPASS_TOKEN_TTL_MS })).toString('base64url');
  return `devotp.${payload}.${createHmac('sha256', bypassSecret()).update(payload).digest('base64url')}`;
};
const readBypassToken = (token: string): { email: string; verified: boolean } | null => {
  const [kind, payload, signature] = token.split('.');
  if (kind !== 'devotp' || !payload || !signature || !bypassSecret()) return null;
  const expected = createHmac('sha256', bypassSecret()).update(payload).digest('base64url');
  if (!safeEqual(signature, expected)) return null;
  try {
    const data = JSON.parse(Buffer.from(payload, 'base64url').toString()) as { email?: string; verified?: boolean; exp?: number };
    return typeof data.email === 'string' && typeof data.exp === 'number' && data.exp > Date.now() ? { email: data.email, verified: data.verified === true } : null;
  } catch { return null; }
};
async function findUserByEmail(db: SupabaseClient, email: string) {
  for (let page = 1; page <= 20; page++) {
    const { data, error } = await db.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) throw error;
    const match = data.users.find(user => user.email?.toLowerCase() === email);
    if (match) return match;
    if (data.users.length < 1000) return null;
  }
  return null;
}

// Supabase reports SMTP failures (bad credentials, timeouts) as 5xx; surface them as a delivery problem, not a crash.
const EMAIL_DELIVERY_FAILED_MESSAGE = 'We could not send the email right now. Please try again in a few minutes.';
const isEmailDeliveryError = (error: { status?: number }) => (error.status ?? 500) >= 500;

// With SMTP configured, the API emails its own codes instead of relying on Supabase's mailer.
const OTP_RESEND_MS = 45_000;
async function emailOwnCode(db: SupabaseClient, email: string, name: string | null, purpose: 'signup' | 'verify'): Promise<{ status: 'sent' | 'throttled' | 'failed'; code?: string }> {
  const { data: previous } = await db.from('signup_otps').select('created_at,used_at').eq('email', email).maybeSingle();
  if (previous && !previous.used_at && Date.now() - Date.parse(previous.created_at) < OTP_RESEND_MS) return { status: 'throttled' };
  const code = await issueOtp(db, email, name);
  try {
    await sendCodeEmail({ to: email, code, name, purpose, expiresInMinutes: DEV_OTP_TTL_MS / 60_000 });
  } catch (error) {
    console.error(`Code email to ${email} failed:`, error instanceof Error ? error.message : error);
    return { status: 'failed', code };
  }
  await markOtpEmailed(db, email);
  return { status: 'sent' };
}

app.post('/api/auth/email/send-otp', async (req, res) => {
  try {
    const email = typeof req.body?.email === 'string' ? req.body.email.trim().toLowerCase() : '';
    if (!EMAIL_PATTERN.test(email)) return errorResponse(res, 400, 'Enter a valid email address.');
    if (isAdminEmail(email)) return errorResponse(res, 409, `${EMAIL_TAKEN_MESSAGE} Sign in instead.`);
    const admin = adminClient();
    const existing = await findUserByEmail(admin, email);
    if (existing && await isRegisteredUser(admin, existing.id)) return errorResponse(res, 409, `${EMAIL_TAKEN_MESSAGE} Sign in instead.`);
    const name = typeof req.body?.name === 'string' ? req.body.name.trim().slice(0, 100) || null : null;
    if (isMailerConfigured()) {
      const result = await emailOwnCode(admin, email, name, 'signup');
      if (result.status === 'throttled') return errorResponse(res, 429, 'Please wait a minute before requesting another code.');
      if (result.status === 'sent') return res.json({ sent: true });
      if (isDynamicDevOtp()) return res.json({ sent: true, fallback: true, code: result.code, expiresInSeconds: DEV_OTP_TTL_MS / 1000 });
      return errorResponse(res, 502, EMAIL_DELIVERY_FAILED_MESSAGE);
    }
    const fallbackCode = await issueDevOtp(admin, email, name);
    const { error } = await authClient().auth.signInWithOtp({ email, options: { shouldCreateUser: true, emailRedirectTo: `${frontendUrl}/verify-email` } });
    if (error) {
      if (devMasterOtp()) {
        console.warn('Sign-up code email failed; DEV_MASTER_OTP fallback is available:', error.message);
        // Only when the email didn't go out: the app shows this code in an in-app notification instead.
        // Accounts verified this way stay unverified (see consumeDevOtp callers).
        return res.json({ sent: true, fallback: true, ...(fallbackCode ? { code: fallbackCode, expiresInSeconds: DEV_OTP_TTL_MS / 1000 } : {}) });
      }
      if (error.status === 429) return errorResponse(res, 429, 'Please wait a minute before requesting another code.');
      if (isEmailDeliveryError(error)) {
        console.error('Sign-up code email failed:', error.message);
        return errorResponse(res, 502, EMAIL_DELIVERY_FAILED_MESSAGE);
      }
      throw error;
    }
    res.json({ sent: true });
  } catch (error) { fail(res, error); }
});

app.post('/api/auth/email/verify-otp', async (req, res) => {
  try {
    const email = typeof req.body?.email === 'string' ? req.body.email.trim().toLowerCase() : '';
    const code = typeof req.body?.code === 'string' ? req.body.code.replace(/\s+/g, '') : '';
    if (!EMAIL_PATTERN.test(email) || !/^\d{6}$/.test(code)) return errorResponse(res, 400, 'Enter the 6-digit code from your email.');
    if (isAdminEmail(email)) return errorResponse(res, 400, 'That code is invalid or has expired.');
    const stored = await consumeDevOtp(adminClient(), email, code);
    if (stored.ok) return res.json({ emailVerified: stored.emailed, verificationToken: signBypassToken(email, stored.emailed) });
    if (isMailerConfigured()) return errorResponse(res, 400, 'That code is invalid or has expired.');
    const { data, error } = await authClient().auth.verifyOtp({ email, token: code, type: 'email' });
    if (error || !data.user || !data.session) return errorResponse(res, 400, 'That code is invalid or has expired.');
    const admin = adminClient();
    if (await isRegisteredUser(admin, data.user.id)) {
      void admin.auth.admin.signOut(data.session.access_token, 'local').catch(() => {});
      return errorResponse(res, 409, `${EMAIL_TAKEN_MESSAGE} Sign in instead.`);
    }
    const { error: updateError } = await admin.auth.admin.updateUserById(data.user.id, { app_metadata: { ...data.user.app_metadata, email_verified: true } });
    if (updateError) throw updateError;
    res.json({ emailVerified: true, verificationToken: data.session.access_token });
  } catch (error) { fail(res, error); }
});

app.post('/api/auth/register', async (req, res) => {
  try {
    const { name, email, password, companyId, companyName, companyWebsite, verificationToken } = req.body ?? {};
    if (typeof name !== 'string' || !name.trim() || typeof email !== 'string' || typeof password !== 'string' || password.length < 8) {
      return errorResponse(res, 400, 'Name, valid email, and a password of at least 8 characters are required.');
    }
    if (!EMAIL_PATTERN.test(email.trim())) return errorResponse(res, 400, 'Enter a valid email address.');
    if (isAdminEmail(email)) return errorResponse(res, 422, EMAIL_TAKEN_MESSAGE);
    // Until REQUIRE_EMAIL_OTP=true, sign-up works without a code and the account starts unverified.
    const hasToken = typeof verificationToken === 'string' && verificationToken.length > 0;
    if (!hasToken && process.env.REQUIRE_EMAIL_OTP === 'true') return errorResponse(res, 400, 'Verify your email with the code we sent before creating your account.');
    const admin = adminClient();
    const normalizedEmail = email.trim().toLowerCase();
    const bypass = hasToken ? readBypassToken(verificationToken) : { email: normalizedEmail, verified: false };
    const bypassEmail = bypass?.email ?? null;
    let pending: User | null = null;
    if (bypassEmail) {
      if (bypassEmail !== normalizedEmail) return errorResponse(res, 400, 'Your email verification expired. Verify your email again.');
      pending = await findUserByEmail(admin, normalizedEmail);
    } else {
      const { data: verified, error: verifiedError } = await authClient().auth.getUser(verificationToken);
      pending = verified?.user ?? null;
      if (verifiedError || !pending || pending.email?.toLowerCase() !== normalizedEmail || pending.app_metadata?.email_verified !== true) {
        return errorResponse(res, 400, 'Your email verification expired. Verify your email again.');
      }
    }
    if (pending && await isRegisteredUser(admin, pending.id)) return errorResponse(res, 422, EMAIL_TAKEN_MESSAGE);
    const companyError = await checkCompanyChoice(admin, companyId, companyName, companyWebsite);
    if (companyError) return errorResponse(res, 400, companyError);
    const emailVerified = !bypass || bypass.verified || pending?.app_metadata?.email_verified === true;
    const { data: saved, error: saveError } = pending
      ? await admin.auth.admin.updateUserById(pending.id, {
        password, email_confirm: true,
        user_metadata: { ...pending.user_metadata, display_name: name.trim() },
        app_metadata: { ...pending.app_metadata, email_verified: emailVerified },
      })
      : await admin.auth.admin.createUser({
        email: normalizedEmail, password, email_confirm: true,
        user_metadata: { display_name: name.trim() },
        app_metadata: { email_verified: emailVerified },
      });
    if (saveError) throw saveError;
    const user = saved.user;
    if (!user) throw new Error('Account could not be created');
    const { data: sessionData, error: signInError } = await authClient().auth.signInWithPassword({ email: email.trim(), password });
    if (signInError) throw signInError;
    if (hasToken && !bypassEmail) void admin.auth.admin.signOut(verificationToken, 'local').catch(() => {});
    const db = admin;
    const profile = await db.from('profiles').upsert({ id: user.id, display_name: name.trim() }, { onConflict: 'id' });
    if (profile.error) throw profile.error;
    const companyRequestPending = await assignCompany(db, user.id, companyId, companyName, companyWebsite);
    res.status(201).json({
      accessToken: sessionData.session?.access_token ?? null,
      refreshToken: sessionData.session?.refresh_token ?? null,
      confirmationRequired: false,
      companyRequestPending,
      user: await userPayload(db, user),
    });
  } catch (error) { fail(res, error); }
});

app.post('/api/auth/complete-profile', async (req, res) => {
  try {
    const authorization = req.header('authorization') ?? '';
    const token = authorization.startsWith('Bearer ') ? authorization.slice(7) : '';
    if (!token) return errorResponse(res, 401, 'Authentication is required.');
    const { data, error } = await authClient().auth.getUser(token);
    if (error || !data.user) return errorResponse(res, 401, 'Invalid authentication token.');
    if (isAdminEmail(data.user.email)) return errorResponse(res, 401, INVALID_SESSION_MESSAGE);
    if (isDeactivated(data.user)) return rejectDeactivatedSignIn(res, adminClient(), data.user, token);
    const { companyId, companyName, companyWebsite } = req.body ?? {};
    const user = data.user;
    const db = adminClient();
    const companyError = await checkCompanyChoice(db, companyId, companyName, companyWebsite);
    if (companyError) return errorResponse(res, 400, companyError);
    const displayName = String(user.user_metadata?.full_name ?? user.user_metadata?.name ?? user.email ?? '').trim();
    const profile = await db.from('profiles').upsert({ id: user.id, display_name: displayName }, { onConflict: 'id' });
    if (profile.error) throw profile.error;
    const companyRequestPending = await assignCompany(db, user.id, companyId, companyName, companyWebsite);
    res.json({ ok: true, companyRequestPending });
  } catch (error) { fail(res, error); }
});

app.post('/api/auth/login', async (req, res) => {
  try {
    const { email, password } = req.body ?? {};
    if (typeof email !== 'string' || typeof password !== 'string') return errorResponse(res, 400, 'Email and password are required.');
    if (isAdminEmail(email)) return errorResponse(res, 401, INVALID_CREDENTIALS_MESSAGE);
    const { data, error } = await authClient().auth.signInWithPassword({ email, password });
    if (error) throw error;
    if (!data.session) throw new Error('Sign in did not return a session');
    if (isDeactivated(data.user)) return rejectDeactivatedSignIn(res, adminClient(), data.user, data.session.access_token);
    res.json({
      accessToken: data.session.access_token,
      refreshToken: data.session.refresh_token,
      user: await userPayload(adminClient(), data.user),
    });
  } catch (error) { fail(res, error); }
});

app.post('/api/auth/refresh', async (req, res) => {
  try {
    const { refreshToken } = req.body ?? {};
    if (typeof refreshToken !== 'string' || !refreshToken) return errorResponse(res, 400, 'Refresh token is required.');
    const { data, error } = await authClient().auth.refreshSession({ refresh_token: refreshToken });
    if (error) throw error;
    if (!data.session) throw new Error('Session could not be refreshed');
    if (data.user && isDeactivated(data.user)) return errorResponse(res, 401, DEACTIVATED_SESSION_MESSAGE, { code: ACCOUNT_DEACTIVATED });
    res.json({ accessToken: data.session.access_token, refreshToken: data.session.refresh_token });
  } catch (error) { fail(res, error); }
});

app.post('/api/auth/reset-password', async (req, res) => {
  try {
    const authorization = req.header('authorization') ?? '';
    const token = authorization.startsWith('Bearer ') ? authorization.slice(7) : '';
    const { password } = req.body ?? {};
    if (!token) return errorResponse(res, 401, 'Password reset session is required.');
    if (typeof password !== 'string' || password.length < 8) return errorResponse(res, 400, 'Password must be at least 8 characters.');
    const { data, error } = await authClient().auth.getUser(token);
    if (error || !data.user) return errorResponse(res, 401, 'Password reset link is invalid or expired.');
    const { error: updateError } = await adminClient().auth.admin.updateUserById(data.user.id, { password });
    if (updateError) throw updateError;
    res.json({ ok: true });
  } catch (error) { fail(res, error); }
});

app.post('/api/auth/forgot-password', async (req, res) => {
  try {
    const { email } = req.body ?? {};
    if (typeof email !== 'string') return errorResponse(res, 400, 'Email is required.');
    const { error } = await authClient().auth.resetPasswordForEmail(email, { redirectTo: `${frontendUrl}/reset-password` });
    if (error) throw error;
    res.json({ ok: true });
  } catch (error) { fail(res, error); }
});

app.post('/api/auth/google', async (req, res) => {
  try {
    const redirectTo = typeof req.body?.redirectTo === 'string' ? req.body.redirectTo : frontendUrl;
    if (new URL(redirectTo).origin !== new URL(frontendUrl).origin) return errorResponse(res, 400, 'Invalid OAuth redirect URL.');
    const { data, error } = await authClient().auth.signInWithOAuth({ provider: 'google', options: { redirectTo, skipBrowserRedirect: true } });
    if (error) throw error;
    res.json({ url: data.url });
  } catch (error) { fail(res, error); }
});

async function authenticatedUser(req: express.Request, res: express.Response) {
  const authorization = req.header('authorization') ?? '';
  const token = authorization.startsWith('Bearer ') ? authorization.slice(7) : '';
  if (!token) { errorResponse(res, 401, 'Authentication is required.'); return null; }
  const { data, error } = await authClient().auth.getUser(token);
  if (error || !data.user) { errorResponse(res, 401, 'Your session is invalid or expired.'); return null; }
  if (isAdminEmail(data.user.email)) { errorResponse(res, 401, INVALID_SESSION_MESSAGE); return null; }
  if (isDeactivated(data.user)) { errorResponse(res, 401, DEACTIVATED_SESSION_MESSAGE, { code: ACCOUNT_DEACTIVATED }); return null; }
  return { user: data.user, token };
}

// ── Account deletion ────────────────────────────────────────────────────────
// "Delete account" deactivates first; the account is purged after the grace period unless the member signs in
// again and restores it. Sign-in with valid credentials answers 403 + data.code ACCOUNT_DEACTIVATED instead of a session.
const DEACTIVATED_SESSION_MESSAGE = 'This account has been deleted. Sign in again to restore it.';
const DELETE_REASON_MAX_LENGTH = 500;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const readReason = (value: unknown): string | null | false =>
  value === undefined || value === null ? null : typeof value === 'string' && value.length <= DELETE_REASON_MAX_LENGTH ? value.trim() || null : false;

async function rejectDeactivatedSignIn(res: express.Response, db: SupabaseClient, user: User, sessionToken?: string) {
  if (sessionToken) void db.auth.admin.signOut(sessionToken, 'local').catch(() => {});
  const lifecycle = await accountLifecycle(db, user.id);
  if (lifecycle.purgeAfter && Date.parse(lifecycle.purgeAfter) <= Date.now()) {
    // Past the grace period: finish the deletion now rather than waiting for the scheduled purge.
    await purgeAccount(db, user.id, 'system', 'Deletion grace period ended');
    return errorResponse(res, 401, INVALID_CREDENTIALS_MESSAGE);
  }
  const message = lifecycle.canRestore
    ? 'This account is scheduled for deletion. Restore it to keep using Office Gossip.'
    : 'This account has been deactivated by the Office Gossip team. Contact support if you think this is a mistake.';
  return errorResponse(res, 403, message, {
    code: ACCOUNT_DEACTIVATED, canRestore: lifecycle.canRestore, email: user.email ?? null,
    deactivatedAt: lifecycle.deactivatedAt, purgeAfter: lifecycle.purgeAfter,
  });
}

app.delete('/api/me/account', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const { password } = req.body ?? {};
    const reason = readReason(req.body?.reason);
    if (reason === false) return errorResponse(res, 400, `Reason must be at most ${DELETE_REASON_MAX_LENGTH} characters.`);
    // Re-authenticate so an unlocked phone or a stolen token alone can't delete the account.
    if (hasPasswordSignIn(session.user)) {
      if (typeof password !== 'string' || !password) return errorResponse(res, 400, 'Enter your password to delete your account.');
      const { data, error } = await authClient().auth.signInWithPassword({ email: session.user.email ?? '', password });
      if (error || data.user?.id !== session.user.id) return errorResponse(res, 400, 'That password is incorrect.');
    }
    const lifecycle = await setAccountStatus(adminClient(), session.user.id, 'deactivated', 'self', reason);
    res.json({ ok: true, status: lifecycle.status, purgeAfter: lifecycle.purgeAfter, graceDays: accountGraceDays() });
  } catch (error) { fail(res, error); }
});

app.post('/api/auth/restore', async (req, res) => {
  try {
    const { email, password } = req.body ?? {};
    if (typeof email !== 'string' || typeof password !== 'string') return errorResponse(res, 400, 'Email and password are required.');
    if (isAdminEmail(email)) return errorResponse(res, 401, INVALID_CREDENTIALS_MESSAGE);
    const { data, error } = await authClient().auth.signInWithPassword({ email, password });
    if (error) throw error;
    if (!data.session) throw new Error('Sign in did not return a session');
    const db = adminClient();
    if (isDeactivated(data.user)) {
      const lifecycle = await accountLifecycle(db, data.user.id);
      if (!lifecycle.canRestore) return rejectDeactivatedSignIn(res, db, data.user, data.session.access_token);
      await setAccountStatus(db, data.user.id, 'active', 'self');
    }
    res.json({
      accessToken: data.session.access_token,
      refreshToken: data.session.refresh_token,
      restored: true,
      user: await userPayload(db, data.user),
    });
  } catch (error) { fail(res, error); }
});

app.get('/api/me', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const db = adminClient();
    const [profile, membership, preference, posts, likes, comments] = await Promise.all([
      db.from('profiles').select('display_name,username,role_title,bio,theme_preference,created_at').eq('id', session.user.id).maybeSingle(),
      db.from('company_memberships').select('company:companies(name)').eq('user_id', session.user.id).eq('status', 'active').limit(1).maybeSingle(),
      db.from('notification_preferences').select('comments,reactions,company_updates').eq('user_id', session.user.id).maybeSingle(),
      db.from('posts').select('id', { count: 'exact', head: true }).eq('author_id', session.user.id).eq('status', 'active'),
      db.from('post_likes').select('post_id', { count: 'exact', head: true }).eq('user_id', session.user.id),
      db.from('comments').select('id', { count: 'exact', head: true }).eq('author_id', session.user.id),
    ]);
    for (const result of [profile, membership, preference, posts, likes, comments]) if (result.error) throw result.error;
    res.json({
      email: session.user.email ?? '',
      profile: profile.data ?? { display_name: String(session.user.user_metadata?.display_name ?? session.user.user_metadata?.full_name ?? ''), role_title: '', bio: '', theme_preference: 'system', created_at: session.user.created_at },
      company: membership.data?.company ?? null,
      preferences: preference.data ?? { comments: true, reactions: true, company_updates: true },
      stats: { posts: posts.count ?? 0, reactions: likes.count ?? 0, comments: comments.count ?? 0 },
      user: await userPayload(db, session.user),
    });
  } catch (error) { fail(res, error); }
});

// The emailed link lands on /verify-email with a one-off session token; this marks that account verified.
app.post('/api/auth/email/confirm-link', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const admin = adminClient();
    if (!isEmailVerified(session.user)) {
      const { error } = await admin.auth.admin.updateUserById(session.user.id, { app_metadata: { ...session.user.app_metadata, email_verified: true } });
      if (error) throw error;
    }
    void admin.auth.admin.signOut(session.token, 'local').catch(() => {});
    res.json({ emailVerified: true, email: session.user.email ?? null });
  } catch (error) { fail(res, error); }
});

// Email verification: Supabase emails a one-time code; a correct code sets app_metadata.email_verified.
app.post('/api/me/email/send-otp', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    if (isEmailVerified(session.user)) return res.json({ emailVerified: true });
    if (!session.user.email) return errorResponse(res, 400, 'Your account has no email address.');
    if (isMailerConfigured()) {
      const name = typeof session.user.user_metadata?.display_name === 'string' ? session.user.user_metadata.display_name : null;
      const result = await emailOwnCode(adminClient(), session.user.email.toLowerCase(), name, 'verify');
      if (result.status === 'throttled') return errorResponse(res, 429, 'Please wait a minute before requesting another code.');
      if (result.status === 'failed') return errorResponse(res, 502, EMAIL_DELIVERY_FAILED_MESSAGE);
      return res.json({ emailVerified: false, sent: true });
    }
    const { error } = await authClient().auth.signInWithOtp({ email: session.user.email, options: { shouldCreateUser: false, emailRedirectTo: `${frontendUrl}/verify-email` } });
    if (error) {
      if (error.status === 429) return errorResponse(res, 429, 'Please wait a minute before requesting another code.');
      if (isEmailDeliveryError(error)) {
        console.error('Verification email failed:', error.message);
        return errorResponse(res, 502, EMAIL_DELIVERY_FAILED_MESSAGE);
      }
      throw error;
    }
    res.json({ emailVerified: false, sent: true });
  } catch (error) { fail(res, error); }
});

app.post('/api/me/email/verify-otp', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    if (isEmailVerified(session.user)) return res.json({ emailVerified: true });
    const code = typeof req.body?.code === 'string' ? req.body.code.replace(/\s+/g, '') : '';
    if (!/^\d{6}$/.test(code)) return errorResponse(res, 400, 'Enter the 6-digit code from your email.');
    if (isMailerConfigured()) {
      const stored = await consumeStoredOtp(adminClient(), (session.user.email ?? '').toLowerCase(), code);
      if (!stored.ok || !stored.emailed) return errorResponse(res, 400, 'That code is invalid or has expired.');
      const { error: verifyError } = await adminClient().auth.admin.updateUserById(session.user.id, { app_metadata: { ...session.user.app_metadata, email_verified: true } });
      if (verifyError) throw verifyError;
      return res.json({ emailVerified: true });
    }
    const { data, error } = await authClient().auth.verifyOtp({ email: session.user.email ?? '', token: code, type: 'email' });
    if (error || data.user?.id !== session.user.id) return errorResponse(res, 400, 'That code is invalid or has expired.');
    const admin = adminClient();
    // verifyOtp opens a second session we don't need; the member keeps their current one.
    if (data.session?.access_token) void admin.auth.admin.signOut(data.session.access_token, 'local').catch(() => {});
    const { error: updateError } = await admin.auth.admin.updateUserById(session.user.id, { app_metadata: { ...session.user.app_metadata, email_verified: true } });
    if (updateError) throw updateError;
    res.json({ emailVerified: true });
  } catch (error) { fail(res, error); }
});

app.patch('/api/me/preferences', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const { themePreference, comments, reactions, companyUpdates } = req.body ?? {};
    const db = adminClient();
    if (themePreference !== undefined) {
      if (!['system', 'light', 'dark'].includes(themePreference)) return errorResponse(res, 400, 'Invalid theme preference.');
      const result = await db.from('profiles').upsert({ id: session.user.id, theme_preference: themePreference }, { onConflict: 'id' });
      if (result.error) throw result.error;
    }
    if ([comments, reactions, companyUpdates].some(value => value !== undefined)) {
      const current = await db.from('notification_preferences').select('comments,reactions,company_updates').eq('user_id', session.user.id).maybeSingle();
      if (current.error) throw current.error;
      const result = await db.from('notification_preferences').upsert({ user_id: session.user.id, comments: comments ?? current.data?.comments ?? true, reactions: reactions ?? current.data?.reactions ?? true, company_updates: companyUpdates ?? current.data?.company_updates ?? true }, { onConflict: 'user_id' });
      if (result.error) throw result.error;
    }
    res.json({ ok: true });
  } catch (error) { fail(res, error); }
});

app.patch('/api/me/profile', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const { displayName, roleTitle, bio } = req.body ?? {};
    if (typeof displayName !== 'string' || !displayName.trim()) return errorResponse(res, 400, 'Display name is required.');
    const result = await adminClient().from('profiles').upsert({ id: session.user.id, display_name: displayName.trim(), role_title: typeof roleTitle === 'string' ? roleTitle.trim() : null, bio: typeof bio === 'string' ? bio.trim() : null }, { onConflict: 'id' });
    if (result.error) throw result.error;
    res.json({ ok: true });
  } catch (error) { fail(res, error); }
});

// Members who skipped (or lost) a company pick one from Profile; a new company name waits for admin approval.
app.post('/api/me/company', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const { companyId, companyName, companyWebsite } = req.body ?? {};
    const db = adminClient();
    const [membership, request] = await Promise.all([
      db.from('company_memberships').select('company:companies(name)').eq('user_id', session.user.id).eq('status', 'active').limit(1).maybeSingle(),
      db.from('company_requests').select('company_name').eq('requested_by', session.user.id).eq('status', 'pending').limit(1).maybeSingle(),
    ]);
    for (const result of [membership, request]) if (result.error) throw result.error;
    if (membership.data) return errorResponse(res, 409, `You’re already a member of ${(membership.data.company as unknown as { name: string } | null)?.name ?? 'a company'}.`);
    if (request.data) return errorResponse(res, 409, `Your request for “${request.data.company_name}” is still waiting for admin approval.`);
    const companyError = await checkCompanyChoice(db, companyId, companyName, companyWebsite);
    if (companyError) return errorResponse(res, 400, companyError);
    const profile = await db.from('profiles').upsert({ id: session.user.id }, { onConflict: 'id', ignoreDuplicates: true });
    if (profile.error) throw profile.error;
    const companyRequestPending = await assignCompany(db, session.user.id, companyId, companyName, companyWebsite);
    res.json({ companyRequestPending, user: await userPayload(db, session.user) });
  } catch (error) { fail(res, error); }
});

app.get('/api/me/devices', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const { data, error } = await adminClient().from('user_devices').select('id,platform,last_seen_at,created_at').eq('user_id', session.user.id).order('created_at', { ascending: false });
    if (error) throw error;
    res.json(data ?? []);
  } catch (error) { fail(res, error); }
});

app.post('/api/me/devices', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const { platform, pushToken } = req.body ?? {};
    if (!['ios', 'android', 'web'].includes(platform) || typeof pushToken !== 'string' || pushToken.trim().length < 10 || pushToken.length > 4096) {
      return errorResponse(res, 400, 'A valid platform and FCM registration token are required.');
    }
    const { data, error } = await adminClient().from('user_devices').upsert({
      user_id: session.user.id,
      platform,
      push_token: pushToken.trim(),
      last_seen_at: new Date().toISOString(),
    }, { onConflict: 'push_token' }).select('id,platform,last_seen_at,created_at').single();
    if (error) throw error;
    res.status(201).json(data);
  } catch (error) { fail(res, error); }
});

app.delete('/api/me/devices/current', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const { pushToken } = req.body ?? {};
    if (typeof pushToken !== 'string' || !pushToken) return errorResponse(res, 400, 'FCM registration token is required.');
    const { error } = await adminClient().from('user_devices').delete().eq('user_id', session.user.id).eq('platform', 'web').eq('push_token', pushToken);
    if (error) throw error;
    res.json({ ok: true });
  } catch (error) { fail(res, error); }
});

app.delete('/api/me/devices/:id', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const { data, error } = await adminClient().from('user_devices').delete().eq('id', req.params.id).eq('user_id', session.user.id).select('id').maybeSingle();
    if (error) throw error;
    if (!data) return errorResponse(res, 404, 'Device registration not found.');
    res.status(204).end();
  } catch (error) { fail(res, error); }
});

function notifySafely(input: Parameters<typeof sendUserNotification>[0]) {
  void sendUserNotification(input).catch((error) => {
    console.error('Push notification delivery failed:', error instanceof Error ? error.message : 'unknown error');
  });
}
async function silences(db: SupabaseClient, recipientId: string, actorId: string) {
  const relations = await relationsFor(db, recipientId);
  return relations.blocked.has(actorId) || relations.muted.has(actorId);
}
const SOCIAL_PUSH_COOLDOWN_MS = 24 * 60 * 60 * 1000;
/** True when no push with this key went out within the cooldown, recording this one; unfollow/re-follow or unlike/re-like spam stays silent. */
async function claimPush(db: SupabaseClient, key: string, cooldownMs = SOCIAL_PUSH_COOLDOWN_MS) {
  const { data, error } = await db.from('push_log').select('sent_at').eq('key', key).maybeSingle();
  if (isMissingTable(error)) return true;
  if (error) throw error;
  if (data && Date.now() - new Date(data.sent_at).getTime() < cooldownMs) return false;
  const { error: saveError } = await db.from('push_log').upsert({ key, sent_at: new Date().toISOString() }, { onConflict: 'key' });
  if (saveError && !isMissingTable(saveError)) throw saveError;
  return true;
}
async function notifyFollow(db: SupabaseClient, actorId: string, targetId: string) {
  if (!(await claimPush(db, `follow:${actorId}:${targetId}`))) return;
  const [{ data: actor }, { data: reverse }] = await Promise.all([
    db.from('profiles').select('display_name,role_title').eq('id', actorId).maybeSingle(),
    db.from('follows').select('follower_id').eq('follower_id', targetId).eq('following_id', actorId).maybeSingle(),
  ]);
  const content = followContent({ actorName: actor?.display_name, actorRole: actor?.role_title, followsBack: Boolean(reverse) });
  await sendUserNotification({ userId: targetId, category: 'reactions', ...content, data: { type: 'follow', userId: actorId }, link: '/?open=people', group: `follow:${actorId}` });
}
async function notifyReaction(db: SupabaseClient, actorId: string, post: { id: string; author_id: string; body: string; is_anonymous: boolean }, reaction: Reaction) {
  if (!(await claimPush(db, `like:${actorId}:${post.id}`))) return;
  const [{ data: actor }, { count }, { count: pollOptions }] = await Promise.all([
    db.from('profiles').select('display_name').eq('id', actorId).maybeSingle(),
    db.from('post_likes').select('user_id', { count: 'exact', head: true }).eq('post_id', post.id).neq('user_id', post.author_id),
    db.from('poll_options').select('id', { count: 'exact', head: true }).eq('post_id', post.id),
  ]);
  const content = reactionContent({
    reaction,
    actorName: actor?.display_name,
    othersCount: Math.max(0, (count ?? 1) - 1),
    postBody: post.body,
    anonymousPost: post.is_anonymous,
    hasPoll: (pollOptions ?? 0) > 0,
  });
  await sendUserNotification({ userId: post.author_id, category: 'reactions', ...content, data: { type: 'reaction', postId: post.id, reaction }, link: '/?open=activity', group: `reaction:${post.id}` });
}
function runSafely(label: string, task: () => Promise<unknown>) {
  void task().catch((error) => {
    console.error(`${label} failed:`, error instanceof Error ? error.message : 'unknown error');
  });
}
function notifyCompanySafely(input: Parameters<typeof notifyCompanyMembers>[0]) {
  void notifyCompanyMembers(input).catch((error) => {
    console.error('Company push delivery failed:', error instanceof Error ? error.message : 'unknown error');
  });
}

const relativeAge = (iso: string) => {
  const minutes = Math.max(0, Math.floor((Date.now() - new Date(iso).getTime()) / 60000));
  return minutes < 1 ? 'just now' : minutes < 60 ? `${minutes}m ago` : minutes < 1440 ? `${Math.floor(minutes / 60)}h ago` : `${Math.floor(minutes / 1440)}d ago`;
};
// One feed item as clients render it; `heldCompany` names the pending company on held posts.
function toFeedPost(post: any, viewerId: string, heldCompany = '') {
  const isDeleted = post.status === 'removed';
  const isPending = post.status === 'pending_company';
  return {
    id: post.id,
    person: post.is_anonymous ? 'Anonymous' : post.author?.display_name || 'Member',
    role: post.is_anonymous ? '' : post.author?.role_title || '',
    company: post.company?.name || (isPending ? heldCompany : ''),
    time: relativeAge(post.created_at),
    createdAt: post.created_at,
    // Deleted posts stay in the feed as a flag only; clients hide them.
    body: isDeleted ? '' : post.body,
    likes: post.post_likes?.length ?? 0,
    comments: post.comments?.length ?? 0,
    anonymous: post.is_anonymous,
    liked: post.post_likes?.some((like: any) => like.user_id === viewerId) ?? false,
    isOwner: post.author_id === viewerId,
    isDeleted,
    isArchived: post.is_archived ?? false,
    isAdmin: post.is_admin ?? false,
    // Waiting for the author's company to be approved; only the author sees it.
    isPending,
  };
}

// Trending is ranked on the server, so it doesn't depend on which feed page a client has loaded.
const TRENDING_WINDOW_DAYS = 3;
// Distinct people (other than the author) who liked or commented.
const TRENDING_MIN_INTERACTIONS = 2;
const TRENDING_CANDIDATES = 1000;
const TRENDING_MAX = 10;
// Each interaction's weight halves every HALF_LIFE hours, so posts with fresh activity outrank older totals.
const TRENDING_HALF_LIFE_HOURS = 36;
const TRENDING_LIKE_WEIGHT = 1;
const TRENDING_COMMENT_WEIGHT = 3;
const TRENDING_REPEAT_COMMENT_WEIGHT = 0.5;
// Each further post by the same author is scaled by this, so one person can't fill the list.
const TRENDING_AUTHOR_REPEAT_FACTOR = 0.6;

function trendingScore(post: any, now: number) {
  const decay = (createdAt: string) => 0.5 ** (Math.max(0, now - Date.parse(createdAt)) / 3_600_000 / TRENDING_HALF_LIFE_HOURS);
  const people = new Set<string>();
  let score = 0;
  for (const like of post.post_likes ?? []) {
    if (like.user_id === post.author_id) continue;
    people.add(like.user_id);
    score += TRENDING_LIKE_WEIGHT * decay(like.created_at);
  }
  const commenters = new Set<string>();
  const comments = [...(post.comments ?? [])].sort((a: any, b: any) => Date.parse(a.created_at) - Date.parse(b.created_at));
  for (const comment of comments) {
    if (comment.author_id === post.author_id) continue;
    const weight = commenters.has(comment.author_id) ? TRENDING_REPEAT_COMMENT_WEIGHT : TRENDING_COMMENT_WEIGHT;
    commenters.add(comment.author_id);
    people.add(comment.author_id);
    score += weight * decay(comment.created_at);
  }
  // Breadth beats depth: many people reacting a little counts more than a few reacting a lot.
  return { score: score * (1 + Math.log2(Math.max(1, people.size))), people: people.size };
}

function rankTrending(posts: any[]) {
  const now = Date.now();
  const scored = posts.map(post => ({ post, ...trendingScore(post, now) }))
    .filter(entry => entry.people >= TRENDING_MIN_INTERACTIONS)
    .sort((a, b) => b.score - a.score || Date.parse(b.post.created_at) - Date.parse(a.post.created_at));
  const seen = new Map<string, number>();
  for (const entry of scored) {
    const count = seen.get(entry.post.author_id) ?? 0;
    entry.score *= TRENDING_AUTHOR_REPEAT_FACTOR ** count;
    seen.set(entry.post.author_id, count + 1);
  }
  return scored.sort((a, b) => b.score - a.score || Date.parse(b.post.created_at) - Date.parse(a.post.created_at)).map(entry => entry.post);
}

app.get('/api/community/feed', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const db = adminClient();
    const [{ data: membership, error: membershipError }, relations] = await Promise.all([
      db.from('company_memberships').select('company_id').eq('user_id', session.user.id).eq('status', 'active').limit(1).maybeSingle(),
      relationsFor(db, session.user.id),
    ]);
    if (membershipError) throw membershipError;
    // `global` shows every company's posts to any signed-in member; `company` (default) only the member's own company.
    const scope = req.query.scope === 'global' ? 'global' : 'company';
    // Cursor pagination: `limit` (1–50, default 50) posts older than the ISO `before` timestamp.
    const limit = Math.min(50, Math.max(1, Number.parseInt(String(req.query.limit ?? ''), 10) || 50));
    const before = typeof req.query.before === 'string' && !Number.isNaN(Date.parse(req.query.before)) ? req.query.before : null;
    if (scope === 'company' && !membership) return res.json([]);
    // `tag` narrows to posts with that #hashtag; `q` (2+ characters) searches post text. Authors are never matched,
    // so searching can't unmask anonymous posts.
    const tag = parseTag(req.query.tag);
    const search = parseSearch(req.query.q);
    const filtered = Boolean(tag || search);
    // `sort=trending`: admin-pinned posts (posts.is_trending) first, newest pin first, then posts from the last
    // TRENDING_WINDOW_DAYS ranked by rankTrending; capped at TRENDING_MAX in total.
    if (req.query.sort === 'trending') {
      const offset = Math.max(0, Number.parseInt(String(req.query.offset ?? ''), 10) || 0);
      const since = new Date(Date.now() - TRENDING_WINDOW_DAYS * 86_400_000).toISOString();
      const loadCandidates = (pinned: boolean, withArchive: boolean, withLifecycle: boolean) => {
        let query = db.from('posts')
          .select(`id,body,status,${withArchive ? 'is_archived,is_admin,' : ''}is_anonymous,created_at,author_id,company_id,author:profiles!posts_author_id_fkey${withLifecycle ? '!inner' : ''}(display_name,role_title),company:companies(name),post_likes(user_id,created_at),comments(id,author_id,created_at)`)
          .eq('status', 'active');
        query = pinned ? query.eq('is_trending', true) : query.gte('created_at', since);
        if (withLifecycle) query = query.eq('author.account_status', 'active');
        if (withArchive) query = query.eq('is_archived', false);
        if (scope === 'company') query = query.eq('company_id', membership!.company_id);
        query = excludeAuthors(query, relations.hidden);
        return query.order(pinned ? 'trending_at' : 'created_at', { ascending: false }).limit(pinned ? TRENDING_MAX : TRENDING_CANDIDATES);
      };
      const load = async (pinned: boolean) => {
        let result = await loadCandidates(pinned, true, true);
        if (result.error?.code === '42703') result = await loadCandidates(pinned, true, false);
        if (result.error?.code === '42703') result = await loadCandidates(pinned, false, false);
        return result;
      };
      const [candidates, pinned] = await Promise.all([load(false), load(true)]);
      if (candidates.error) throw candidates.error;
      // 42703 here means the database predates posts.is_trending, so nothing is pinned.
      if (pinned.error && pinned.error.code !== '42703') throw pinned.error;
      const pinnedPosts = (pinned.error ? [] : pinned.data ?? []) as any[];
      const pinnedIds = new Set(pinnedPosts.map(post => post.id));
      const ranked = [...pinnedPosts, ...rankTrending(((candidates.data ?? []) as any[]).filter(post => !pinnedIds.has(post.id)))];
      const page = ranked.slice(0, TRENDING_MAX).slice(offset, offset + limit).map(post => ({ ...toFeedPost(post, session.user.id), isPinned: pinnedIds.has(post.id) }));
      return res.json(await withExtras(db, session.user.id, page));
    }
    const loadPosts = (withArchive: boolean, withLifecycle: boolean) => {
      let query = db.from('posts')
        .select(`id,body,status,${withArchive ? 'is_archived,is_admin,' : ''}is_anonymous,created_at,author_id,company_id,author:profiles!posts_author_id_fkey${withLifecycle ? '!inner' : ''}(display_name,role_title),company:companies(name),post_likes(user_id),comments(id)`)
        .in('status', filtered ? ['active'] : ['active', 'removed']);
      if (tag) query = query.ilike('body', `%#${escapeLike(tag)}%`).filter('body', 'imatch', `(^|[^[:alnum:]_&])#${tag}([^[:alnum:]_]|$)`);
      if (search) query = query.ilike('body', `%${escapeLike(search)}%`);
      // Posts by deleted (deactivated) accounts disappear for everyone and come back if the account is restored.
      if (withLifecycle) query = query.eq('author.account_status', 'active');
      if (withArchive) query = query.or(`is_archived.eq.false,author_id.eq.${session.user.id}`);
      if (scope === 'company') query = query.eq('company_id', membership!.company_id);
      if (before) query = query.lt('created_at', before);
      query = excludeAuthors(query, relations.hidden);
      return query.order('created_at', { ascending: false }).limit(limit);
    };
    let { data, error } = await loadPosts(true, true);
    // 42703 = undefined column: the database predates the account lifecycle or is_archived/is_admin columns in database/scheme.sql.
    if (error?.code === '42703') ({ data, error } = await loadPosts(true, false));
    if (error?.code === '42703') ({ data, error } = await loadPosts(false, false));
    if (error) throw error;
    // Held posts (author's company awaiting approval) are shown only to their author, above the first page.
    let held: any[] = [];
    let heldCompany = '';
    if (!membership && !before && !filtered) {
      const [heldPosts, request] = await Promise.all([
        db.from('posts').select('id,body,status,is_archived,is_admin,is_anonymous,created_at,author_id,company_id,author:profiles!posts_author_id_fkey(display_name,role_title),company:companies(name),post_likes(user_id),comments(id)')
          .eq('author_id', session.user.id).eq('status', 'pending_company').order('created_at', { ascending: false }).limit(limit),
        db.from('company_requests').select('company_name').eq('requested_by', session.user.id).eq('status', 'pending').order('created_at', { ascending: false }).limit(1).maybeSingle(),
      ]);
      if (heldPosts.error) throw heldPosts.error;
      if (request.error) throw request.error;
      held = heldPosts.data ?? [];
      heldCompany = request.data?.company_name ?? '';
    }
    res.json(await withExtras(db, session.user.id, [...held, ...(data ?? [])].map(post => toFeedPost(post, session.user.id, heldCompany))));
  } catch (error) { fail(res, error); }
});

app.get('/api/community/people', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const db = adminClient();
    const { data: membership, error: membershipError } = await db.from('company_memberships').select('company_id').eq('user_id', session.user.id).eq('status', 'active').limit(1).maybeSingle();
    if (membershipError) throw membershipError;
    if (!membership) return res.json([]);
    const loadMembers = (withLifecycle: boolean) => {
      const query = db.from('company_memberships')
        .select(`user_id,profile:profiles!company_memberships_user_id_fkey${withLifecycle ? '!inner' : ''}(display_name,role_title)`)
        .eq('company_id', membership.company_id).eq('status', 'active');
      return (withLifecycle ? query.eq('profile.account_status', 'active') : query).order('created_at', { ascending: true });
    };
    let { data, error } = await loadMembers(true);
    if (error?.code === '42703') ({ data, error } = await loadMembers(false));
    if (error) throw error;
    const [following, relations] = await Promise.all([followingIds(db, session.user.id), relationsFor(db, session.user.id)]);
    res.json((data ?? []).filter((member: any) => !relations.blocked.has(member.user_id)).map((member: any) => ({
      id: member.user_id,
      name: member.profile?.display_name || 'Member',
      role: member.profile?.role_title || '',
      team: '',
      following: following.has(member.user_id),
      muted: relations.muted.has(member.user_id),
    })));
  } catch (error) { fail(res, error); }
});

// Missing table (follows block of database/scheme.sql not applied yet) reads as "follows nobody" instead of breaking People.
async function followingIds(db: SupabaseClient, userId: string) {
  const { data, error } = await db.from('follows').select('following_id').eq('follower_id', userId);
  if (isMissingTable(error)) return new Set<string>();
  if (error) throw error;
  return new Set((data ?? []).map(row => row.following_id as string));
}

// ── Block & mute ────────────────────────────────────────────────────────────
// `hidden`: authors whose posts this member never sees (they blocked or muted them, or were blocked by them).
// `blocked` / `muted`: named relations only — anonymous-post blocks must not change People, follows or notifications.
type Relations = { hidden: Set<string>; blocked: Set<string>; muted: Set<string> };
const BLOCKS_MISSING_MESSAGE = 'Blocking is not set up yet. Run the "Block & mute" block of database/scheme.sql in Supabase.';
async function relationsFor(db: SupabaseClient, userId: string): Promise<Relations> {
  const relations: Relations = { hidden: new Set(), blocked: new Set(), muted: new Set() };
  const { data, error } = await db.from('user_blocks').select('blocker_id,blocked_id,kind,via_anonymous')
    .or(`blocker_id.eq.${userId},and(blocked_id.eq.${userId},kind.eq.block)`);
  if (isMissingTable(error)) return relations;
  if (error) throw error;
  for (const row of data ?? []) {
    const mine = row.blocker_id === userId;
    const other = mine ? row.blocked_id : row.blocker_id;
    relations.hidden.add(other);
    if (row.via_anonymous) continue;
    if (row.kind === 'block') relations.blocked.add(other);
    else if (mine) relations.muted.add(other);
  }
  return relations;
}
function excludeAuthors<T>(query: T, ids: Set<string>): T {
  return ids.size ? (query as any).not('author_id', 'in', `(${[...ids].join(',')})`) : query;
}
async function saveBlock(db: SupabaseClient, input: { blockerId: string; blockedId: string; kind: 'block' | 'mute'; viaAnonymous: boolean; label: string }) {
  const { data, error } = await db.from('user_blocks')
    .upsert({ blocker_id: input.blockerId, blocked_id: input.blockedId, kind: input.kind, via_anonymous: input.viaAnonymous, label: input.label }, { onConflict: 'blocker_id,blocked_id,via_anonymous' })
    .select('id,kind,label,via_anonymous,created_at').single();
  if (isMissingTable(error)) throw Object.assign(new Error(BLOCKS_MISSING_MESSAGE), { status: 503 });
  if (error) throw error;
  if (input.kind === 'block' && !input.viaAnonymous) {
    const { error: followError } = await db.from('follows').delete()
      .or(`and(follower_id.eq.${input.blockerId},following_id.eq.${input.blockedId}),and(follower_id.eq.${input.blockedId},following_id.eq.${input.blockerId})`);
    if (followError && !isMissingTable(followError)) throw followError;
  }
  return toBlock(data);
}
const toBlock = (row: any) => ({ id: row.id, kind: row.kind as 'block' | 'mute', label: row.label, anonymous: row.via_anonymous === true, createdAt: row.created_at });
const parseBlockKind = (value: unknown): 'block' | 'mute' | null => value === undefined ? 'block' : value === 'block' || value === 'mute' ? value : null;

// ── Polls & saved posts on feed items ───────────────────────────────────────
type FeedPost = ReturnType<typeof toFeedPost>;
type Poll = { options: { id: string; label: string; votes: number }[]; totalVotes: number; myVote: string | null };
const POLL_MIN_OPTIONS = 2;
const POLL_MAX_OPTIONS = 4;
const POLL_OPTION_MAX_LENGTH = 80;
const POLLS_MISSING_MESSAGE = 'Polls are not set up yet. Run the "Polls" block of database/scheme.sql in Supabase.';
const SAVES_MISSING_MESSAGE = 'Saved posts are not set up yet. Run the "Saved posts" block of database/scheme.sql in Supabase.';
async function pollsFor(db: SupabaseClient, userId: string, postIds: string[]) {
  const polls = new Map<string, Poll>();
  if (!postIds.length) return polls;
  const [options, mine] = await Promise.all([
    db.from('poll_options').select('id,post_id,label,position,poll_votes(count)').in('post_id', postIds).order('position'),
    db.from('poll_votes').select('post_id,option_id').eq('user_id', userId).in('post_id', postIds),
  ]);
  if (isMissingTable(options.error) || isMissingTable(mine.error)) return polls;
  if (options.error) throw options.error;
  if (mine.error) throw mine.error;
  const myVotes = new Map((mine.data ?? []).map(vote => [vote.post_id as string, vote.option_id as string]));
  for (const option of (options.data ?? []) as any[]) {
    const poll = polls.get(option.post_id) ?? { options: [], totalVotes: 0, myVote: myVotes.get(option.post_id) ?? null };
    const votes = option.poll_votes?.[0]?.count ?? 0;
    poll.options.push({ id: option.id, label: option.label, votes });
    poll.totalVotes += votes;
    polls.set(option.post_id, poll);
  }
  return polls;
}
async function savedIds(db: SupabaseClient, userId: string, postIds: string[]) {
  if (!postIds.length) return new Set<string>();
  const { data, error } = await db.from('post_saves').select('post_id').eq('user_id', userId).in('post_id', postIds);
  if (isMissingTable(error)) return new Set<string>();
  if (error) throw error;
  return new Set((data ?? []).map(row => row.post_id as string));
}
const REACTIONS = ['love', 'laugh', 'fire', 'clap', 'wow'] as const;
type Reaction = typeof REACTIONS[number];
const REACTIONS_MISSING_MESSAGE = 'Emoji reactions are not set up yet. Run the "Emoji reactions" block of database/scheme.sql in Supabase.';
const parseReaction = (value: unknown): Reaction | null | undefined =>
  value === null ? null : REACTIONS.includes(value as Reaction) ? value as Reaction : undefined;
type ReactionSummary = { counts: Partial<Record<Reaction, number>>; mine: Reaction | null };
// `null` when the database predates post_likes.reaction; callers then treat every like as ❤️.
async function reactionsFor(db: SupabaseClient, userId: string, postIds: string[]) {
  const summaries = new Map<string, ReactionSummary>();
  if (!postIds.length) return summaries;
  const { data, error } = await db.from('post_likes').select('post_id,user_id,reaction').in('post_id', postIds);
  if (error?.code === '42703') return null;
  if (error) throw error;
  for (const row of (data ?? []) as Array<{ post_id: string; user_id: string; reaction: Reaction }>) {
    const summary = summaries.get(row.post_id) ?? { counts: {}, mine: null };
    summary.counts[row.reaction] = (summary.counts[row.reaction] ?? 0) + 1;
    if (row.user_id === userId) summary.mine = row.reaction;
    summaries.set(row.post_id, summary);
  }
  return summaries;
}
async function withExtras<T extends FeedPost & { likes?: number; liked?: boolean }>(db: SupabaseClient, userId: string, posts: T[]) {
  const ids = posts.filter(post => !post.isDeleted).map(post => String(post.id));
  const [polls, saved, reactions] = await Promise.all([pollsFor(db, userId, ids), savedIds(db, userId, ids), reactionsFor(db, userId, ids)]);
  return posts.map(post => {
    const summary = reactions ? reactions.get(String(post.id)) : { counts: post.likes ? { love: post.likes } : {}, mine: post.liked ? 'love' as const : null };
    return { ...post, saved: saved.has(String(post.id)), poll: polls.get(String(post.id)) ?? null, reactions: summary?.counts ?? {}, myReaction: summary?.mine ?? null };
  });
}

// Hashtags are `#` + 2–30 letters, digits or underscores, matched case-insensitively and returned lowercase.
const HASHTAG_PATTERN = /(?:^|[^\p{L}\p{M}\p{N}_&])#([\p{L}\p{M}\p{N}_]{2,30})/gu;
const hashtagsIn = (body: string) => [...new Set([...body.matchAll(HASHTAG_PATTERN)].map(match => match[1].toLowerCase()))];
const parseTag = (value: unknown) => typeof value === 'string' && /^[\p{L}\p{M}\p{N}_]{2,30}$/u.test(value.replace(/^#/, '')) ? value.replace(/^#/, '').toLowerCase() : null;
const SEARCH_MAX_LENGTH = 80;
const parseSearch = (value: unknown) => {
  const text = typeof value === 'string' ? value.trim().slice(0, SEARCH_MAX_LENGTH) : '';
  return text.length >= 2 ? text : null;
};
const TOPICS_WINDOW_DAYS = 14;
const TOPICS_SAMPLE = 500;
const TOPICS_MAX = 12;
// Trimmed, de-duplicated 2–4 options, `undefined` when no poll was sent, or `null` when the input is invalid.
function parsePollOptions(value: unknown): string[] | undefined | null {
  if (value === undefined || value === null) return undefined;
  if (!Array.isArray(value)) return null;
  const options = value.map(option => typeof option === 'string' ? option.trim() : '');
  if (options.length < POLL_MIN_OPTIONS || options.length > POLL_MAX_OPTIONS) return null;
  if (options.some(option => !option || option.length > POLL_OPTION_MAX_LENGTH)) return null;
  if (new Set(options.map(option => option.toLowerCase())).size !== options.length) return null;
  return options;
}

app.post('/api/community/people/:id/follow', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const targetId = req.params.id;
    if (targetId === session.user.id) return errorResponse(res, 400, 'You can’t follow yourself.');
    const db = adminClient();
    const { data: target, error: targetError } = await db.from('profiles').select('id').eq('id', targetId).maybeSingle();
    if (targetError) throw targetError;
    if (!target) return errorResponse(res, 404, 'Member not found.');
    if ((await relationsFor(db, session.user.id)).blocked.has(targetId)) return errorResponse(res, 403, 'You can’t follow this member.');
    const { error } = await db.from('follows').insert({ follower_id: session.user.id, following_id: targetId });
    if (error?.code === '23505') return res.json({ following: true });
    if (error) throw error;
    if (!(await silences(db, targetId, session.user.id))) {
      runSafely('Follow push', () => notifyFollow(db, session.user.id, targetId));
    }
    res.json({ following: true });
  } catch (error) { fail(res, error); }
});

app.delete('/api/community/people/:id/follow', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const { error } = await adminClient().from('follows').delete().eq('follower_id', session.user.id).eq('following_id', req.params.id);
    if (error) throw error;
    res.json({ following: false });
  } catch (error) { fail(res, error); }
});

// Repeat submits (double taps, retries) within this window return the earlier row instead of creating a copy.
const DUPLICATE_WINDOW_MS = 30_000;
const recentSince = () => new Date(Date.now() - DUPLICATE_WINDOW_MS).toISOString();

app.post('/api/community/posts', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const body = typeof req.body?.body === 'string' ? req.body.body.trim() : '';
    const isAnonymous = req.body?.anonymous === undefined ? false : req.body.anonymous;
    if (!body || body.length > 500 || typeof isAnonymous !== 'boolean') return errorResponse(res, 400, 'Post text must be 1–500 characters and anonymous must be a boolean.');
    const pollOptions = parsePollOptions(req.body?.poll);
    if (pollOptions === null) return errorResponse(res, 400, `A poll needs ${POLL_MIN_OPTIONS}–${POLL_MAX_OPTIONS} different options of up to ${POLL_OPTION_MAX_LENGTH} characters.`);
    const db = adminClient();
    const [{ data: membership, error: membershipError }, { data: request, error: requestError }] = await Promise.all([
      db.from('company_memberships').select('company_id').eq('user_id', session.user.id).eq('status', 'active').limit(1).maybeSingle(),
      db.from('company_requests').select('company_name').eq('requested_by', session.user.id).eq('status', 'pending').limit(1).maybeSingle(),
    ]);
    if (membershipError) throw membershipError;
    if (requestError) throw requestError;
    // With a company request awaiting approval the post is held, then published once the company is approved.
    if (!membership && !request) return errorResponse(res, 403, 'Active company membership required.');
    const pending = !membership;
    const { data: duplicate, error: duplicateError } = await db.from('posts').select('id').eq('author_id', session.user.id).eq('body', body).in('status', ['active', 'pending_company']).gte('created_at', recentSince()).limit(1).maybeSingle();
    if (duplicateError) throw duplicateError;
    if (duplicate) return res.status(201).json({ id: duplicate.id, pending });
    const { data, error } = await db.from('posts').insert({ company_id: membership?.company_id ?? null, author_id: session.user.id, body, is_anonymous: isAnonymous, ...(pending ? { status: 'pending_company' } : {}) }).select('id').single();
    if (error?.code === '23502' || error?.code === '23514') return errorResponse(res, 503, 'Posting before company approval is not set up yet. Run the held-posts block of database/scheme.sql in Supabase.');
    if (error) throw error;
    if (pollOptions) {
      const { error: pollError } = await db.from('poll_options').insert(pollOptions.map((label, position) => ({ post_id: data.id, label, position })));
      if (pollError) {
        await db.from('posts').delete().eq('id', data.id);
        if (isMissingTable(pollError)) return errorResponse(res, 503, POLLS_MISSING_MESSAGE);
        throw pollError;
      }
    }
    if (membership) notifyCompanySafely({ companyId: membership.company_id, excludeUserId: session.user.id, title: 'New community post', body: 'A coworker shared a post with your company.', data: { type: 'post', postId: data.id } });
    res.status(201).json({ id: data.id, pending });
  } catch (error) { fail(res, error); }
});

app.post('/api/community/posts/:id/comments', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const body = typeof req.body?.body === 'string' ? req.body.body.trim() : '';
    if (!body || body.length > 1000) return errorResponse(res, 400, 'Comment must be between 1 and 1000 characters.');
    const db = adminClient();
    const { data: post, error: postError } = await db.from('posts').select('id,author_id,company_id,status').eq('id', req.params.id).maybeSingle();
    if (postError) throw postError;
    if (!post || post.status !== 'active') return errorResponse(res, 404, 'Post not found.');
    const { data: duplicate, error: duplicateError } = await db.from('comments').select('id,post_id,body,created_at').eq('post_id', post.id).eq('author_id', session.user.id).eq('body', body).gte('created_at', recentSince()).limit(1).maybeSingle();
    if (duplicateError) throw duplicateError;
    if (duplicate) return res.status(201).json(duplicate);
    const { data, error } = await db.from('comments').insert({ post_id: post.id, author_id: session.user.id, body }).select('id,post_id,body,created_at').single();
    if (error) throw error;
    if (post.author_id !== session.user.id && !(await relationsFor(db, post.author_id)).blocked.has(session.user.id)) {
      const { data: profile } = await db.from('profiles').select('display_name').eq('id', session.user.id).maybeSingle();
      notifySafely({ userId: post.author_id, category: 'comments', title: 'New comment', body: `${profile?.display_name || 'Someone'} commented on your post: “${excerpt(body)}”`, data: { type: 'comment', postId: post.id } });
    }
    res.status(201).json(data);
  } catch (error) { fail(res, error); }
});

app.post('/api/community/posts/:id/likes', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const db = adminClient();
    const { data: post, error: postError } = await db.from('posts').select('id,author_id,company_id,status,body,is_anonymous').eq('id', req.params.id).maybeSingle();
    if (postError) throw postError;
    if (!post || post.status !== 'active') return errorResponse(res, 404, 'Post not found.');
    const { data: existing, error: findError } = await db.from('post_likes').select('post_id').eq('post_id', post.id).eq('user_id', session.user.id).maybeSingle();
    if (findError) throw findError;
    if (existing) {
      const { error } = await db.from('post_likes').delete().eq('post_id', post.id).eq('user_id', session.user.id);
      if (error) throw error;
      return res.json({ liked: false });
    }
    const { error } = await db.from('post_likes').insert({ post_id: post.id, user_id: session.user.id });
    if (error?.code === '23505') return res.json({ liked: true });
    if (error) throw error;
    if (post.author_id !== session.user.id && !(await silences(db, post.author_id, session.user.id))) {
      runSafely('Reaction push', () => notifyReaction(db, session.user.id, post, 'love'));
    }
    res.json({ liked: true });
  } catch (error) { fail(res, error); }
});

// Sets (or with `reaction: null` removes) the member's single emoji reaction; returns the post's updated counts.
app.post('/api/community/posts/:id/reactions', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const reaction = parseReaction(req.body?.reaction);
    if (reaction === undefined) return errorResponse(res, 400, `Reaction must be one of ${REACTIONS.join(', ')}, or null to remove it.`);
    const db = adminClient();
    const { data: post, error: postError } = await db.from('posts').select('id,author_id,status,body,is_anonymous').eq('id', req.params.id).maybeSingle();
    if (postError) throw postError;
    if (!post || post.status !== 'active') return errorResponse(res, 404, 'Post not found.');
    if (reaction === null) {
      const { error } = await db.from('post_likes').delete().eq('post_id', post.id).eq('user_id', session.user.id);
      if (error) throw error;
    } else {
      const { data: existing, error: findError } = await db.from('post_likes').select('reaction').eq('post_id', post.id).eq('user_id', session.user.id).maybeSingle();
      if (findError?.code === '42703') return errorResponse(res, 503, REACTIONS_MISSING_MESSAGE);
      if (findError) throw findError;
      const { error } = await db.from('post_likes').upsert({ post_id: post.id, user_id: session.user.id, reaction }, { onConflict: 'post_id,user_id' });
      if (error) throw error;
      if (!existing && post.author_id !== session.user.id && !(await silences(db, post.author_id, session.user.id))) {
        runSafely('Reaction push', () => notifyReaction(db, session.user.id, post, reaction));
      }
    }
    const summary = (await reactionsFor(db, session.user.id, [post.id]))?.get(post.id) ?? { counts: {}, mine: null };
    const likes = Object.values(summary.counts).reduce((sum, count) => sum + (count ?? 0), 0);
    res.json({ reactions: summary.counts, myReaction: summary.mine, likes, liked: summary.mine !== null });
  } catch (error) { fail(res, error); }
});

// Most-used #hashtags in recent posts of the scope, for topic chips.
app.get('/api/community/topics', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const db = adminClient();
    const [{ data: membership, error: membershipError }, relations] = await Promise.all([
      db.from('company_memberships').select('company_id').eq('user_id', session.user.id).eq('status', 'active').limit(1).maybeSingle(),
      relationsFor(db, session.user.id),
    ]);
    if (membershipError) throw membershipError;
    const scope = req.query.scope === 'global' ? 'global' : 'company';
    if (scope === 'company' && !membership) return res.json([]);
    const since = new Date(Date.now() - TOPICS_WINDOW_DAYS * 86_400_000).toISOString();
    let query = db.from('posts').select('body').eq('status', 'active').gte('created_at', since).like('body', '%#%');
    if (scope === 'company') query = query.eq('company_id', membership!.company_id);
    query = excludeAuthors(query, relations.hidden);
    const { data, error } = await query.order('created_at', { ascending: false }).limit(TOPICS_SAMPLE);
    if (error) throw error;
    const counts = new Map<string, number>();
    for (const post of data ?? []) for (const tag of hashtagsIn(post.body)) counts.set(tag, (counts.get(tag) ?? 0) + 1);
    res.json([...counts].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0])).slice(0, TOPICS_MAX).map(([tag, posts]) => ({ tag, posts })));
  } catch (error) { fail(res, error); }
});

// Held posts count as live for their author's own edits and deletes.
async function findActivePost(db: SupabaseClient, postId: string) {
  const { data, error } = await db.from('posts').select('id,author_id,company_id,status').eq('id', postId).maybeSingle();
  if (error) throw error;
  return data && (data.status === 'active' || data.status === 'pending_company') ? data : null;
}

const excerpt = (text: string, max = 80) => (text.length > max ? `${text.slice(0, max - 1).trimEnd()}…` : text);

// Built from likes and comments on the member's posts; "seen" is kept in auth user metadata.
app.get('/api/notifications', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const db = adminClient();
    const [{ data: posts, error: postsError }, followers] = await Promise.all([
      db.from('posts').select('id,body').eq('author_id', session.user.id).eq('status', 'active').order('created_at', { ascending: false }).limit(200),
      db.from('follows').select('follower_id,created_at').eq('following_id', session.user.id).order('created_at', { ascending: false }).limit(50),
    ]);
    if (postsError) throw postsError;
    if (followers.error && !isMissingTable(followers.error)) throw followers.error;
    const allFollows = followers.error ? [] : followers.data ?? [];
    const postIds = (posts ?? []).map(post => post.id);
    const empty = { data: [] as any[], error: null };
    const loadLikes = (withReaction: boolean) => db.from('post_likes').select(`post_id,user_id,created_at${withReaction ? ',reaction' : ''}`).in('post_id', postIds).neq('user_id', session.user.id).order('created_at', { ascending: false }).limit(50);
    const [likes, comments] = postIds.length ? await Promise.all([
      loadLikes(true).then(result => result.error?.code === '42703' ? loadLikes(false) : result) as Promise<{ data: Array<{ post_id: string; user_id: string; created_at: string; reaction?: Reaction }> | null; error: any }>,
      db.from('comments').select('id,post_id,author_id,body,created_at').in('post_id', postIds).neq('author_id', session.user.id).order('created_at', { ascending: false }).limit(50),
    ]) : [empty, empty];
    if (likes.error) throw likes.error;
    if (comments.error) throw comments.error;
    const { blocked } = await relationsFor(db, session.user.id);
    if (blocked.size) {
      likes.data = (likes.data ?? []).filter(like => !blocked.has(like.user_id));
      comments.data = (comments.data ?? []).filter(comment => !blocked.has(comment.author_id));
    }
    const follows = allFollows.filter(follow => !blocked.has(follow.follower_id));
    if (!likes.data?.length && !comments.data?.length && !follows.length) return res.json({ items: [], unreadCount: 0 });
    const actorIds = [...new Set([...(likes.data ?? []).map(like => like.user_id), ...(comments.data ?? []).map(comment => comment.author_id), ...follows.map(follow => follow.follower_id)])];
    const { data: profiles, error: profilesError } = actorIds.length ? await db.from('profiles').select('id,display_name').in('id', actorIds) : { data: [], error: null };
    if (profilesError) throw profilesError;
    const names = new Map((profiles ?? []).map(profile => [profile.id, profile.display_name || 'Someone']));
    const bodies = new Map((posts ?? []).map(post => [post.id, post.body]));
    const seenAt = Date.parse(String(session.user.user_metadata?.notifications_seen_at ?? '')) || 0;
    const items = [
      ...(likes.data ?? []).map(like => ({ id: `like-${like.post_id}-${like.user_id}`, type: 'reaction' as const, reaction: like.reaction ?? 'love', actorName: names.get(like.user_id) || 'Someone', postId: like.post_id, postExcerpt: excerpt(bodies.get(like.post_id) || ''), comment: null as string | null, createdAt: like.created_at })),
      ...(comments.data ?? []).map(comment => ({ id: `comment-${comment.id}`, type: 'comment' as const, actorName: names.get(comment.author_id) || 'Someone', postId: comment.post_id, postExcerpt: excerpt(bodies.get(comment.post_id) || ''), comment: excerpt(comment.body, 120), createdAt: comment.created_at })),
      ...follows.map(follow => ({ id: `follow-${follow.follower_id}`, type: 'follow' as const, actorName: names.get(follow.follower_id) || 'Someone', postId: null as string | null, postExcerpt: '', comment: null as string | null, createdAt: follow.created_at })),
    ].sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt)).slice(0, 50)
      .map(item => ({ ...item, time: relativeTime(item.createdAt), unread: Date.parse(item.createdAt) > seenAt }));
    res.json({ items, unreadCount: items.filter(item => item.unread).length });
  } catch (error) { fail(res, error); }
});

app.post('/api/notifications/read', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const { error } = await adminClient().auth.admin.updateUserById(session.user.id, { user_metadata: { ...session.user.user_metadata, notifications_seen_at: new Date().toISOString() } });
    if (error) throw error;
    res.status(204).end();
  } catch (error) { fail(res, error); }
});

app.patch('/api/community/posts/:id', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const body = typeof req.body?.body === 'string' ? req.body.body.trim() : '';
    if (!body || body.length > 500) return errorResponse(res, 400, 'Post text must be 1–500 characters.');
    const db = adminClient();
    const post = await findActivePost(db, String(req.params.id));
    if (!post) return errorResponse(res, 404, 'Post not found.');
    if (post.author_id !== session.user.id) return errorResponse(res, 403, 'You can only edit your own posts.');
    const { error } = await db.from('posts').update({ body, updated_at: new Date().toISOString() }).eq('id', post.id);
    if (error) throw error;
    res.json({ id: post.id, body });
  } catch (error) { fail(res, error); }
});

app.post('/api/community/posts/:id/archive', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const archived = req.body?.archived === undefined ? true : req.body.archived;
    if (typeof archived !== 'boolean') return errorResponse(res, 400, 'archived must be a boolean.');
    const db = adminClient();
    const post = await findActivePost(db, String(req.params.id));
    if (!post) return errorResponse(res, 404, 'Post not found.');
    if (post.author_id !== session.user.id) return errorResponse(res, 403, 'You can only archive your own posts.');
    const { error } = await db.from('posts').update({ is_archived: archived, updated_at: new Date().toISOString() }).eq('id', post.id);
    if (error) throw error;
    res.json({ id: post.id, isArchived: archived });
  } catch (error) { fail(res, error); }
});

// Soft delete so open reports and moderation history keep pointing at the post.
app.delete('/api/community/posts/:id', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const db = adminClient();
    const post = await findActivePost(db, String(req.params.id));
    if (!post) return errorResponse(res, 404, 'Post not found.');
    if (post.author_id !== session.user.id) return errorResponse(res, 403, 'You can only delete your own posts.');
    const { error } = await db.from('posts').update({ status: 'removed', updated_at: new Date().toISOString() }).eq('id', post.id);
    if (error) throw error;
    res.json({ id: post.id, isDeleted: true });
  } catch (error) { fail(res, error); }
});

app.post('/api/community/posts/:id/report', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const reason = typeof req.body?.reason === 'string' ? req.body.reason.trim() : '';
    if (!reason || reason.length > 200) return errorResponse(res, 400, 'Report reason must be 1–200 characters.');
    const db = adminClient();
    const post = await findActivePost(db, String(req.params.id));
    if (!post) return errorResponse(res, 404, 'Post not found.');
    const { data: profile, error: profileError } = await db.from('profiles').select('display_name').eq('id', session.user.id).maybeSingle();
    if (profileError) throw profileError;
    const reporterName = profile?.display_name || String(session.user.user_metadata?.display_name ?? session.user.user_metadata?.full_name ?? '');
    const { error } = await db.from('reports').insert({ post_id: post.id, reporter_id: session.user.id, reporter_name: reporterName, reporter_email: session.user.email ?? '', reason });
    if (error?.code === '23505') return res.json({ ok: true, alreadyReported: true });
    if (error) throw error;
    res.status(201).json({ ok: true, alreadyReported: false });
  } catch (error) { fail(res, error); }
});

// Blocks or mutes a post's author without revealing who wrote an anonymous post. Body: { kind?: 'block' | 'mute' }.
app.post('/api/community/posts/:id/block', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const kind = parseBlockKind(req.body?.kind);
    if (!kind) return errorResponse(res, 400, 'kind must be "block" or "mute".');
    const db = adminClient();
    const { data: post, error } = await db.from('posts').select('id,author_id,is_anonymous,status,author:profiles!posts_author_id_fkey(display_name)').eq('id', String(req.params.id)).maybeSingle();
    if (error) throw error;
    if (!post || post.status !== 'active') return errorResponse(res, 404, 'Post not found.');
    if (post.author_id === session.user.id) return errorResponse(res, 400, `You can’t ${kind} yourself.`);
    const anonymous = post.is_anonymous === true;
    const label = anonymous ? 'Anonymous member' : (post.author as any)?.display_name || 'Member';
    res.json(await saveBlock(db, { blockerId: session.user.id, blockedId: post.author_id, kind, viaAnonymous: anonymous, label }));
  } catch (error) { fail(res, error); }
});

app.post('/api/community/people/:id/block', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const kind = parseBlockKind(req.body?.kind);
    if (!kind) return errorResponse(res, 400, 'kind must be "block" or "mute".');
    const targetId = String(req.params.id);
    if (targetId === session.user.id) return errorResponse(res, 400, `You can’t ${kind} yourself.`);
    const db = adminClient();
    const { data: target, error } = await db.from('profiles').select('id,display_name').eq('id', targetId).maybeSingle();
    if (error) throw error;
    if (!target) return errorResponse(res, 404, 'Member not found.');
    res.json(await saveBlock(db, { blockerId: session.user.id, blockedId: targetId, kind, viaAnonymous: false, label: target.display_name || 'Member' }));
  } catch (error) { fail(res, error); }
});

// Removes named blocks and mutes only; anonymous-post blocks are managed from the blocked list.
app.delete('/api/community/people/:id/block', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const { error } = await adminClient().from('user_blocks').delete().eq('blocker_id', session.user.id).eq('blocked_id', String(req.params.id)).eq('via_anonymous', false);
    if (isMissingTable(error)) return errorResponse(res, 503, BLOCKS_MISSING_MESSAGE);
    if (error) throw error;
    res.status(204).end();
  } catch (error) { fail(res, error); }
});

app.get('/api/me/blocks', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const { data, error } = await adminClient().from('user_blocks').select('id,kind,label,via_anonymous,created_at').eq('blocker_id', session.user.id).order('created_at', { ascending: false });
    if (isMissingTable(error)) return res.json([]);
    if (error) throw error;
    res.json((data ?? []).map(toBlock));
  } catch (error) { fail(res, error); }
});

app.delete('/api/me/blocks/:id', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const { error } = await adminClient().from('user_blocks').delete().eq('id', String(req.params.id)).eq('blocker_id', session.user.id);
    if (isMissingTable(error)) return errorResponse(res, 503, BLOCKS_MISSING_MESSAGE);
    if (error) throw error;
    res.status(204).end();
  } catch (error) { fail(res, error); }
});

// One vote per member per poll; voting again moves the vote and `optionId: null` takes it back.
app.post('/api/community/posts/:id/vote', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const optionId = req.body?.optionId;
    if (optionId !== null && typeof optionId !== 'string') return errorResponse(res, 400, 'optionId must be a poll option id or null.');
    const db = adminClient();
    const post = await findActivePost(db, String(req.params.id));
    if (!post) return errorResponse(res, 404, 'Post not found.');
    if (optionId === null) {
      const { error } = await db.from('poll_votes').delete().eq('post_id', post.id).eq('user_id', session.user.id);
      if (isMissingTable(error)) return errorResponse(res, 503, POLLS_MISSING_MESSAGE);
      if (error) throw error;
    } else {
      const { data: option, error: optionError } = await db.from('poll_options').select('id').eq('id', optionId).eq('post_id', post.id).maybeSingle();
      if (isMissingTable(optionError)) return errorResponse(res, 503, POLLS_MISSING_MESSAGE);
      if (optionError?.code === '22P02') return errorResponse(res, 404, 'Poll option not found.');
      if (optionError) throw optionError;
      if (!option) return errorResponse(res, 404, 'Poll option not found.');
      const { error } = await db.from('poll_votes').upsert({ post_id: post.id, option_id: option.id, user_id: session.user.id, created_at: new Date().toISOString() }, { onConflict: 'post_id,user_id' });
      if (error) throw error;
    }
    const poll = (await pollsFor(db, session.user.id, [post.id])).get(post.id);
    if (!poll) return errorResponse(res, 404, 'This post has no poll.');
    res.json({ poll });
  } catch (error) { fail(res, error); }
});

// Body: { saved: boolean } (defaults to true).
app.post('/api/community/posts/:id/save', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const saved = req.body?.saved === undefined ? true : req.body.saved;
    if (typeof saved !== 'boolean') return errorResponse(res, 400, 'saved must be a boolean.');
    const db = adminClient();
    const post = await findActivePost(db, String(req.params.id));
    if (!post) return errorResponse(res, 404, 'Post not found.');
    const { error } = saved
      ? await db.from('post_saves').upsert({ post_id: post.id, user_id: session.user.id }, { onConflict: 'post_id,user_id', ignoreDuplicates: true })
      : await db.from('post_saves').delete().eq('post_id', post.id).eq('user_id', session.user.id);
    if (isMissingTable(error)) return errorResponse(res, 503, SAVES_MISSING_MESSAGE);
    if (error) throw error;
    res.json({ saved });
  } catch (error) { fail(res, error); }
});

// Newest save first; posts that were deleted, archived by someone else or hidden by a block drop out.
const SAVED_LIMIT = 100;
app.get('/api/me/saved', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const db = adminClient();
    const [{ data: saves, error }, relations] = await Promise.all([
      db.from('post_saves').select('post_id').eq('user_id', session.user.id).order('created_at', { ascending: false }).limit(SAVED_LIMIT),
      relationsFor(db, session.user.id),
    ]);
    if (isMissingTable(error)) return res.json([]);
    if (error) throw error;
    const ids = (saves ?? []).map(save => save.post_id as string);
    if (!ids.length) return res.json([]);
    const loadSaved = (withLifecycle: boolean) => {
      let query = db.from('posts')
        .select(`id,body,status,is_archived,is_admin,is_anonymous,created_at,author_id,company_id,author:profiles!posts_author_id_fkey${withLifecycle ? '!inner' : ''}(display_name,role_title),company:companies(name),post_likes(user_id),comments(id)`)
        .in('id', ids).eq('status', 'active').or(`is_archived.eq.false,author_id.eq.${session.user.id}`);
      if (withLifecycle) query = query.eq('author.account_status', 'active');
      return excludeAuthors(query, relations.hidden);
    };
    let { data: posts, error: postsError } = await loadSaved(true);
    if (postsError?.code === '42703') ({ data: posts, error: postsError } = await loadSaved(false));
    if (postsError) throw postsError;
    const byId = new Map((posts ?? []).map((post: any) => [post.id, post]));
    const ordered = ids.map(id => byId.get(id)).filter(Boolean).map(post => toFeedPost(post, session.user.id));
    res.json(await withExtras(db, session.user.id, ordered));
  } catch (error) { fail(res, error); }
});

const ADMIN_TOKEN_TTL_MS = 12 * 60 * 60 * 1000;
const adminSecret = () => {
  const secret = process.env.ADMIN_TOKEN_SECRET;
  if (!secret || !process.env.ADMIN_EMAIL || !process.env.ADMIN_PASSWORD) throw new Error('Admin access is not configured');
  return secret;
};
const signAdmin = (payload: string) => createHmac('sha256', adminSecret()).update(payload).digest('base64url');
const safeEqual = (a: string, b: string) => {
  const left = Buffer.from(a); const right = Buffer.from(b);
  return left.length === right.length && timingSafeEqual(left, right);
};

function requireAdmin(req: express.Request, res: express.Response, next: express.NextFunction) {
  try {
    const authorization = req.header('authorization') ?? '';
    const token = authorization.startsWith('Bearer ') ? authorization.slice(7) : '';
    const [payload, signature] = token.split('.');
    if (!payload || !signature || !safeEqual(signature, signAdmin(payload))) return errorResponse(res, 401, 'Admin session is invalid.');
    const { exp } = JSON.parse(Buffer.from(payload, 'base64url').toString()) as { exp?: number };
    if (!exp || exp < Date.now()) return errorResponse(res, 401, 'Admin session has expired.');
    next();
  } catch (error) { fail(res, error); }
}

const cleanDomain = (value: unknown) => typeof value === 'string' ? value.trim().replace(/^https?:\/\//i, '').replace(/\/.*$/, '').toLowerCase() || null : null;

app.post('/api/admin/login', (req, res) => {
  try {
    const { email, password } = req.body ?? {};
    const secret = adminSecret();
    if (typeof email !== 'string' || typeof password !== 'string'
      || !safeEqual(email.trim().toLowerCase(), String(process.env.ADMIN_EMAIL).toLowerCase())
      || !safeEqual(password, String(process.env.ADMIN_PASSWORD))) return errorResponse(res, 401, 'Email or password is incorrect.');
    const payload = Buffer.from(JSON.stringify({ sub: 'admin', exp: Date.now() + ADMIN_TOKEN_TTL_MS })).toString('base64url');
    res.json({ token: `${payload}.${createHmac('sha256', secret).update(payload).digest('base64url')}` });
  } catch (error) { fail(res, error); }
});

async function adminCompanyList(db: SupabaseClient) {
  const [companies, memberships] = await Promise.all([
    db.from('companies').select('id,name,website_domain,status,created_at').neq('status', 'pending_review').order('created_at', { ascending: false }),
    db.from('company_memberships').select('company_id').eq('status', 'active'),
  ]);
  for (const result of [companies, memberships]) if (result.error) throw result.error;
  const memberCounts = new Map<string, number>();
  for (const m of memberships.data ?? []) memberCounts.set(m.company_id, (memberCounts.get(m.company_id) ?? 0) + 1);
  return (companies.data ?? []).map(c => ({ id: c.id, name: c.name, domain: c.website_domain ?? '', members: memberCounts.get(c.id) ?? 0, status: c.status === 'active' ? 'Active' : 'Disabled', createdAt: c.created_at }));
}

app.get('/api/admin/companies', requireAdmin, async (_req, res) => {
  try { res.json(await adminCompanyList(adminClient())); } catch (error) { fail(res, error); }
});

app.get('/api/admin/dashboard', requireAdmin, async (_req, res) => {
  try {
    const db = adminClient();
    const [companies, memberships, requests, reports, users] = await Promise.all([
      adminCompanyList(db),
      db.from('company_memberships').select('user_id,company_id,join_method,status,created_at,profile:profiles!company_memberships_user_id_fkey(display_name),company:companies(name)').eq('status', 'active').order('created_at', { ascending: false }),
      db.from('company_requests').select('id,company_name,website_domain,created_at,requested_by,profile:profiles!company_requests_requested_by_fkey(display_name)').eq('status', 'pending').order('created_at', { ascending: false }),
      db.from('reports').select('id,reason,created_at,reporter_id,reporter_name,reporter_email,post:posts(id,body,is_anonymous,status,author:profiles!posts_author_id_fkey(display_name),company:companies(name))').eq('status', 'open').order('created_at', { ascending: false }),
      db.auth.admin.listUsers({ perPage: 1000 }),
    ]);
    for (const result of [memberships, requests, reports, users]) if (result.error) throw result.error;
    const emails = new Map(users.data.users.map(user => [user.id, user.email ?? '']));
    const groupedReports = new Map<string, any>();
    for (const report of (reports.data ?? []) as any[]) {
      const post = report.post;
      if (!post || post.status === 'removed') continue;
      const reporter = { name: report.reporter_name || 'Member', email: report.reporter_email || emails.get(report.reporter_id) || '', reason: report.reason, createdAt: report.created_at };
      const existing = groupedReports.get(post.id);
      if (existing) { existing.reports += 1; existing.reporters.push(reporter); continue; }
      groupedReports.set(post.id, {
        reporters: [reporter],
        id: post.id,
        company: post.company?.name ?? '',
        author: post.is_anonymous ? 'Anonymous' : post.author?.display_name || 'Member',
        body: post.body,
        reason: report.reason,
        createdAt: report.created_at,
        reports: 1,
      });
    }
    res.json({
      companies,
      requests: [...((requests.data ?? []) as any[]).reduce((groups, r) => {
        const key = normalizeCompanyName(r.company_name).toLowerCase();
        const existing = groups.get(key);
        if (existing) existing.others += 1;
        else groups.set(key, { id: r.id, name: normalizeCompanyName(r.company_name), domain: r.website_domain ?? '', requester: r.profile?.display_name || 'Member', email: emails.get(r.requested_by) ?? '', createdAt: r.created_at, others: 0 });
        return groups;
      }, new Map<string, any>()).values()],
      members: ((memberships.data ?? []) as any[]).map(m => ({ id: `${m.user_id}:${m.company_id}`, name: m.profile?.display_name || 'Member', email: emails.get(m.user_id) ?? '', company: m.company?.name ?? '', method: m.join_method, createdAt: m.created_at })),
      reports: [...groupedReports.values()],
    });
  } catch (error) { fail(res, error); }
});

app.post('/api/admin/companies', requireAdmin, async (req, res) => {
  try {
    const rows: unknown[] = Array.isArray(req.body?.companies) ? req.body.companies : [req.body ?? {}];
    const input = rows.map((row: any) => ({ name: normalizeCompanyName(row?.name), website_domain: cleanDomain(row?.domain) })).filter(row => row.name);
    if (input.some(row => row.name.length < 2 || row.name.length > 100)) return errorResponse(res, 400, 'Company names must be between 2 and 100 characters.');
    if (!input.length || input.length > 1000) return errorResponse(res, 400, 'Provide between 1 and 1000 companies with a name.');
    const db = adminClient();
    const { data: existing, error: existingError } = await db.from('companies').select('name');
    if (existingError) throw existingError;
    const taken = new Set((existing ?? []).map(c => normalizeCompanyName(c.name).toLowerCase()));
    const additions = input.filter(row => !taken.has(row.name.toLowerCase()) && taken.add(row.name.toLowerCase()));
    const skipped = input.length - additions.length;
    if (!additions.length) return res.status(200).json({ added: 0, skipped });
    const { data: created, error } = await db.from('companies').insert(additions.map(row => ({ ...row, status: 'active' }))).select('id,name');
    if (error) throw error;
    for (const company of created ?? []) await fulfillPendingRequests(db, String(company.id), company.name);
    res.status(201).json({ added: additions.length, skipped });
  } catch (error) { fail(res, error); }
});

app.patch('/api/admin/companies/:id', requireAdmin, async (req, res) => {
  try {
    const { status, name, domain } = req.body ?? {};
    const changes: Record<string, unknown> = { updated_at: new Date().toISOString() };
    if (status !== undefined) {
      if (!['active', 'disabled'].includes(status)) return errorResponse(res, 400, 'Status must be active or disabled.');
      changes.status = status;
    }
    const db = adminClient();
    if (name !== undefined) {
      const cleanName = normalizeCompanyName(name);
      if (cleanName.length < 2 || cleanName.length > 100) return errorResponse(res, 400, 'Company name must be between 2 and 100 characters.');
      const existing = await findCompanyByName(db, cleanName);
      if (existing && existing.id !== String(req.params.id)) return errorResponse(res, 409, 'A company with this name already exists.');
      changes.name = cleanName;
    }
    if (domain !== undefined) changes.website_domain = cleanDomain(domain);
    if (Object.keys(changes).length === 1) return errorResponse(res, 400, 'Nothing to update.');
    const { data, error } = await db.from('companies').update(changes).eq('id', String(req.params.id)).select('id,name,status').maybeSingle();
    if (error) throw error;
    if (!data) return errorResponse(res, 404, 'Company not found.');
    if (data.status === 'active') await fulfillPendingRequests(db, String(data.id), data.name);
    res.json({ ok: true });
  } catch (error) { fail(res, error); }
});

// Approving one request approves every pending request for the same company name, regardless of letter case.
async function approveCompanyRequest(db: SupabaseClient, requestId: string) {
  const { data: request, error } = await db.from('company_requests').select('id,company_name,website_domain,requested_by,status').eq('id', requestId).maybeSingle();
  if (error) throw error;
  if (!request || request.status !== 'pending') return false;
  const name = normalizeCompanyName(request.company_name);
  const found = await findCompanyByName(db, name);
  let companyId = found?.id;
  if (companyId) {
    const { error: activateError } = await db.from('companies').update({ status: 'active', updated_at: new Date().toISOString() }).eq('id', companyId);
    if (activateError) throw activateError;
  } else {
    const { data: created, error: createError } = await db.from('companies').insert({ name, website_domain: cleanDomain(request.website_domain), status: 'active' }).select('id').single();
    if (createError) throw createError;
    companyId = String(created.id);
  }
  await fulfillPendingRequests(db, String(companyId), name);
  return true;
}

// Posts written while the company awaited approval go live in it, dated now so they surface at the top of feeds.
async function publishHeldPosts(db: SupabaseClient, userIds: string[], companyId: string) {
  if (!userIds.length) return;
  const now = new Date().toISOString();
  const { data, error } = await db.from('posts').update({ company_id: companyId, status: 'active', created_at: now, updated_at: now })
    .in('author_id', userIds).eq('status', 'pending_company').select('id,author_id');
  if (error) throw error;
  for (const userId of new Set((data ?? []).map(post => String(post.author_id)))) {
    notifyCompanySafely({ companyId, excludeUserId: userId, title: 'New community post', body: 'A coworker shared a post with your company.', data: { type: 'post' } });
  }
}

// Every pending request for this company name (any letter case) becomes an active membership.
async function fulfillPendingRequests(db: SupabaseClient, companyId: string, companyName: string) {
  const name = normalizeCompanyName(companyName);
  const { data: requests, error: matchError } = await db.from('company_requests').select('id,requested_by').eq('status', 'pending').ilike('company_name', escapeLike(name));
  if (matchError) throw matchError;
  if (!requests?.length) return 0;
  const userIds = [...new Set(requests.map(r => String(r.requested_by)))];
  const membership = await db.from('company_memberships').upsert(userIds.map(userId => ({ user_id: userId, company_id: companyId, status: 'active', join_method: 'admin_approved' })), { onConflict: 'user_id,company_id' });
  if (membership.error) throw membership.error;
  const update = await db.from('company_requests').update({ status: 'approved', reviewed_at: new Date().toISOString() }).in('id', requests.map(r => r.id));
  if (update.error) throw update.error;
  await publishHeldPosts(db, userIds, companyId);
  for (const userId of userIds) {
    notifySafely({ userId, category: 'company_updates', title: 'Company approved', body: `${name} is now live on Office Gossip.`, data: { type: 'company_approved', companyId } });
  }
  return userIds.length;
}

app.post('/api/admin/requests/:id/approve', requireAdmin, async (req, res) => {
  try {
    if (!await approveCompanyRequest(adminClient(), String(req.params.id))) return errorResponse(res, 404, 'Pending request not found.');
    res.json({ ok: true });
  } catch (error) { fail(res, error); }
});

app.post('/api/admin/requests/approve-all', requireAdmin, async (_req, res) => {
  try {
    const db = adminClient();
    const { data, error } = await db.from('company_requests').select('id').eq('status', 'pending').order('created_at');
    if (error) throw error;
    let approved = 0;
    for (const request of data ?? []) if (await approveCompanyRequest(db, String(request.id))) approved += 1;
    res.json({ approved });
  } catch (error) { fail(res, error); }
});

app.post('/api/admin/requests/:id/reject', requireAdmin, async (req, res) => {
  try {
    const db = adminClient();
    const { data: request, error: findError } = await db.from('company_requests').select('company_name').eq('id', String(req.params.id)).eq('status', 'pending').maybeSingle();
    if (findError) throw findError;
    if (!request) return errorResponse(res, 404, 'Pending request not found.');
    const { error } = await db.from('company_requests').update({ status: 'rejected', reviewed_at: new Date().toISOString() }).eq('status', 'pending').ilike('company_name', escapeLike(normalizeCompanyName(request.company_name)));
    if (error) throw error;
    res.json({ ok: true });
  } catch (error) { fail(res, error); }
});

app.post('/api/admin/reports/:postId/:action', requireAdmin, async (req, res) => {
  try {
    const postId = String(req.params.postId); const action = String(req.params.action);
    if (!['dismiss', 'remove'].includes(action)) return errorResponse(res, 404, 'Unknown moderation action.');
    const db = adminClient();
    if (action === 'remove') {
      const post = await db.from('posts').update({ status: 'removed', updated_at: new Date().toISOString() }).eq('id', postId);
      if (post.error) throw post.error;
    }
    const { error } = await db.from('reports').update({ status: action === 'remove' ? 'resolved' : 'dismissed' }).eq('post_id', postId).eq('status', 'open');
    if (error) throw error;
    res.json({ ok: true });
  } catch (error) { fail(res, error); }
});

// ── Admin trending pins ─────────────────────────────────────────────────────
const TRENDING_COLUMN_MISSING_MESSAGE = 'Trending pins need the posts.is_trending column. Run the "Trending pins" block of database/scheme.sql in the Supabase SQL editor.';
const ADMIN_POSTS_LIMIT = 100;

// Pinned posts first, then the latest active posts; `q` searches post text.
app.get('/api/admin/posts', requireAdmin, async (req, res) => {
  try {
    const search = typeof req.query.q === 'string' ? req.query.q.trim().slice(0, 100) : '';
    const select = 'id,body,is_anonymous,is_trending,trending_at,created_at,author:profiles!posts_author_id_fkey(display_name),company:companies(name),post_likes(user_id),comments(id)';
    const db = adminClient();
    let latest = db.from('posts').select(select).eq('status', 'active').eq('is_archived', false);
    if (search) latest = latest.ilike('body', `%${escapeLike(search)}%`);
    const [pinned, recent] = await Promise.all([
      db.from('posts').select(select).eq('status', 'active').eq('is_trending', true).order('trending_at', { ascending: false }),
      latest.order('created_at', { ascending: false }).limit(ADMIN_POSTS_LIMIT),
    ]);
    if (pinned.error?.code === '42703' || recent.error?.code === '42703') return errorResponse(res, 503, TRENDING_COLUMN_MISSING_MESSAGE);
    for (const result of [pinned, recent]) if (result.error) throw result.error;
    const pinnedIds = new Set((pinned.data ?? []).map((post: any) => post.id));
    const posts = [...(search ? [] : pinned.data ?? []), ...(recent.data ?? []).filter((post: any) => search || !pinnedIds.has(post.id))];
    res.json(posts.map((post: any) => ({
      id: post.id,
      body: post.body,
      author: post.is_anonymous ? 'Anonymous' : post.author?.display_name || 'Member',
      company: post.company?.name ?? '',
      likes: post.post_likes?.length ?? 0,
      comments: post.comments?.length ?? 0,
      trending: post.is_trending === true,
      trendingAt: post.trending_at,
      createdAt: post.created_at,
    })));
  } catch (error) { fail(res, error); }
});

app.post('/api/admin/posts/:id/trending', requireAdmin, async (req, res) => {
  try {
    const trending = req.body?.trending;
    if (typeof trending !== 'boolean') return errorResponse(res, 400, 'Send { "trending": true } or { "trending": false }.');
    const { data, error } = await adminClient().from('posts')
      .update({ is_trending: trending, trending_at: trending ? new Date().toISOString() : null })
      .eq('id', String(req.params.id)).select('id').maybeSingle();
    if (error?.code === '42703') return errorResponse(res, 503, TRENDING_COLUMN_MISSING_MESSAGE);
    if (error) throw error;
    if (!data) return errorResponse(res, 404, 'Post not found.');
    res.json({ ok: true });
  } catch (error) { fail(res, error); }
});

const OTP_HISTORY_MS = 7 * 24 * 60 * 60 * 1000;
const otpStatus = (row: { attempts: number; expires_at: string; used_at: string | null }) =>
  row.used_at ? 'used' : row.attempts >= DEV_OTP_MAX_ATTEMPTS ? 'locked' : Date.parse(row.expires_at) < Date.now() ? 'expired' : 'active';

app.get('/api/admin/otps', requireAdmin, async (_req, res) => {
  try {
    const mode = !devMasterOtp() ? 'off' : isDynamicDevOtp() ? 'dynamic' : 'fixed';
    const db = adminClient();
    const cleanup = await db.from('signup_otps').delete().lt('created_at', new Date(Date.now() - OTP_HISTORY_MS).toISOString());
    if (isMissingTable(cleanup.error)) return errorResponse(res, 503, OTP_TABLE_MISSING_MESSAGE);
    if (cleanup.error) throw cleanup.error;
    // `*` so the list still loads on older signup_otps tables without `name`/`emailed`.
    const { data, error } = await db.from('signup_otps').select('*').order('created_at', { ascending: false }).limit(200);
    if (error) throw error;
    res.json({
      mode,
      fixedCode: mode === 'fixed' ? devMasterOtp() : null,
      // Codes Supabase emails itself (no SMTP configured) are never stored, so they can't be listed.
      mailerConfigured: isMailerConfigured(),
      codes: (data ?? []).map(row => ({ email: row.email, name: row.name ?? null, code: row.code, status: otpStatus(row), attempts: row.attempts, emailed: row.emailed === true, createdAt: row.created_at, expiresAt: row.expires_at, usedAt: row.used_at })),
    });
  } catch (error) { fail(res, error); }
});

app.delete('/api/admin/otps/:email', requireAdmin, async (req, res) => {
  try {
    const { error } = await adminClient().from('signup_otps').delete().eq('email', String(req.params.email).trim().toLowerCase());
    if (error) throw error;
    res.json({ ok: true });
  } catch (error) { fail(res, error); }
});

// ── Admin account manager ───────────────────────────────────────────────────
const ACCOUNT_PAGE_SIZE = 25;
app.get('/api/admin/accounts', requireAdmin, async (req, res) => {
  try {
    const status = (['active', 'deactivated'] as const).find(value => value === req.query.status) ?? null;
    const search = typeof req.query.q === 'string' ? req.query.q.trim().slice(0, 100) : '';
    const pageSize = Math.min(100, Math.max(1, Number.parseInt(String(req.query.pageSize ?? ''), 10) || ACCOUNT_PAGE_SIZE));
    const page = Math.max(1, Number.parseInt(String(req.query.page ?? ''), 10) || 1);
    const { rows, total, counts } = await listAccounts(adminClient(), { status, query: search ? escapeLike(search) : null, limit: pageSize, offset: (page - 1) * pageSize });
    res.json({
      items: rows.map(row => ({
        id: row.id, email: row.email ?? '', name: row.display_name || 'Member', company: row.company_name, status: row.account_status,
        deactivatedAt: row.deactivated_at, deactivatedBy: row.deactivated_by, reason: row.deactivation_reason,
        purgeAfter: row.purge_after, createdAt: row.created_at, lastSignInAt: row.last_sign_in_at,
      })),
      total, page, pageSize, counts, graceDays: accountGraceDays(),
    });
  } catch (error) { fail(res, error); }
});

app.post('/api/admin/accounts/purge-due', requireAdmin, async (_req, res) => {
  try { res.json(await purgeDueAccounts(adminClient())); } catch (error) { fail(res, error); }
});

app.post('/api/admin/accounts/:id/:action', requireAdmin, async (req, res) => {
  try {
    const id = String(req.params.id);
    const action = String(req.params.action);
    if (!UUID_PATTERN.test(id)) return errorResponse(res, 404, 'Account not found.');
    if (action !== 'deactivate' && action !== 'restore') return errorResponse(res, 404, 'Unknown account action.');
    const reason = readReason(req.body?.reason);
    if (reason === false) return errorResponse(res, 400, `Reason must be at most ${DELETE_REASON_MAX_LENGTH} characters.`);
    const status: AccountStatus = action === 'deactivate' ? 'deactivated' : 'active';
    const lifecycle = await setAccountStatus(adminClient(), id, status, 'admin', reason);
    res.json({ ok: true, status: lifecycle.status, purgeAfter: lifecycle.purgeAfter });
  } catch (error) { fail(res, error); }
});

app.delete('/api/admin/accounts/:id', requireAdmin, async (req, res) => {
  try {
    const id = String(req.params.id);
    if (!UUID_PATTERN.test(id)) return errorResponse(res, 404, 'Account not found.');
    const reason = readReason(req.body?.reason);
    await purgeAccount(adminClient(), id, 'admin', reason || 'Deleted by an administrator');
    res.json({ ok: true });
  } catch (error) { fail(res, error); }
});

app.post('/api/auth/logout', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const { error } = await adminClient().auth.admin.signOut(session.token);
    if (error) throw error;
    res.json({ ok: true });
  } catch (error) { fail(res, error); }
});

const relativeTime = (iso: string) => {
  const minutes = Math.max(0, Math.floor((Date.now() - new Date(iso).getTime()) / 60000));
  return minutes < 1 ? 'just now' : minutes < 60 ? `${minutes}m ago` : minutes < 1440 ? `${Math.floor(minutes / 60)}h ago` : `${Math.floor(minutes / 1440)}d ago`;
};
const audienceLabels = { everyone: 'Everyone', user: 'One user', company: 'One company' } as const;
type AnnouncementAudience = keyof typeof audienceLabels;

app.post('/api/admin/announcements', requireAdmin, async (req, res) => {
  try {
    const message = typeof req.body?.message === 'string' ? req.body.message.trim() : '';
    const audience = (Object.keys(audienceLabels) as AnnouncementAudience[]).find(key => audienceLabels[key] === req.body?.audience || key === req.body?.audience);
    const target = typeof req.body?.target === 'string' ? req.body.target.trim() : '';
    if (!message || message.length > 500) return errorResponse(res, 400, 'Message must be 1–500 characters.');
    if (!audience) return errorResponse(res, 400, 'Audience must be Everyone, One user, or One company.');
    if (audience !== 'everyone' && !target) return errorResponse(res, 400, audience === 'user' ? 'Enter the user email or username.' : 'Choose a company.');
    const db = adminClient();
    let targetUserId: string | null = null;
    let targetCompanyId: string | null = null;
    let targetLabel: string | undefined;
    if (audience === 'user') {
      if (target.includes('@')) {
        const { data, error } = await db.auth.admin.listUsers({ perPage: 1000 });
        if (error) throw error;
        targetUserId = data.users.find(user => user.email?.toLowerCase() === target.toLowerCase())?.id ?? null;
      } else {
        const { data, error } = await db.from('profiles').select('id').ilike('username', target).maybeSingle();
        if (error) throw error;
        targetUserId = data?.id ?? null;
      }
      if (!targetUserId) return errorResponse(res, 404, `No user found for “${target}”.`);
      targetLabel = target;
    } else if (audience === 'company') {
      const { data, error } = await db.from('companies').select('id,name').ilike('name', target).eq('status', 'active').limit(1).maybeSingle();
      if (error) throw error;
      if (!data) return errorResponse(res, 404, `No active company named “${target}”.`);
      targetCompanyId = data.id;
      targetLabel = data.name;
    }
    const { data, error } = await db.from('announcements')
      .insert({ message, audience, target_user_id: targetUserId, target_company_id: targetCompanyId })
      .select('id,created_at').single();
    if (error) throw error;
    const push = { title: 'Office Gossip update', body: message, data: { type: 'announcement', announcementId: String(data.id) } };
    if (targetUserId) notifySafely({ userId: targetUserId, category: 'company_updates', ...push });
    if (targetCompanyId) notifyCompanySafely({ companyId: targetCompanyId, excludeUserId: '00000000-0000-0000-0000-000000000000', ...push });
    res.status(201).json({ id: data.id, message, audience: audienceLabels[audience], target: targetLabel, createdAt: data.created_at });
  } catch (error) { fail(res, error); }
});

app.get('/api/admin/announcements', requireAdmin, async (_req, res) => {
  try {
    const db = adminClient();
    const { data, error } = await db.from('announcements')
      .select('id,message,audience,created_at,target_user:profiles(display_name,username),target_company:companies(name)')
      .order('created_at', { ascending: false }).limit(50);
    if (error) throw error;
    res.json((data ?? []).map((row: any) => ({
      id: row.id,
      message: row.message,
      audience: audienceLabels[row.audience as AnnouncementAudience],
      target: row.target_company?.name ?? row.target_user?.username ?? row.target_user?.display_name ?? undefined,
      createdAt: row.created_at,
    })));
  } catch (error) { fail(res, error); }
});

app.get('/api/announcements', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const db = adminClient();
    const { data: membership, error: membershipError } = await db.from('company_memberships').select('company_id').eq('user_id', session.user.id).eq('status', 'active').limit(1).maybeSingle();
    if (membershipError) throw membershipError;
    const filters = ['audience.eq.everyone', `target_user_id.eq.${session.user.id}`];
    if (membership) filters.push(`target_company_id.eq.${membership.company_id}`);
    const { data, error } = await db.from('announcements')
      .select('id,message,audience,created_at')
      .or(filters.join(','))
      .order('created_at', { ascending: false }).limit(20);
    // 42P01 = missing table: announcements table from database/scheme.sql has not been applied yet.
    if (error?.code === '42P01' || error?.code === 'PGRST205') return res.json([]);
    if (error) throw error;
    res.json((data ?? []).map(row => ({
      id: row.id,
      message: row.message,
      audience: row.audience,
      createdAt: row.created_at,
      time: relativeTime(row.created_at),
    })));
  } catch (error) { fail(res, error); }
});
