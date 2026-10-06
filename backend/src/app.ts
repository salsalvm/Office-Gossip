import express from 'express';
import { createHmac, randomInt, timingSafeEqual } from 'node:crypto';
import cors from 'cors';
import { createClient, type SupabaseClient, type User } from '@supabase/supabase-js';
import { notifyCompanyMembers, sendUserNotification } from './services/fcm.js';

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
const adminClient = (): SupabaseClient => {
  if (!supabaseUrl || !serviceKey) throw new Error('Supabase database access is not configured');
  return createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
};
const errorResponse = (res: express.Response, httpStatus: number, message: string) =>
  res.status(httpStatus).json({ message, status: false, data: {} });

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

async function userPayload(db: SupabaseClient, user: User) {
  const [profile, membership, request, posts, likes, comments] = await Promise.all([
    db.from('profiles').select('display_name,username,role_title,bio,theme_preference,created_at').eq('id', user.id).maybeSingle(),
    db.from('company_memberships').select('company:companies(id,name,website_domain)').eq('user_id', user.id).eq('status', 'active').limit(1).maybeSingle(),
    db.from('company_requests').select('company_name').eq('requested_by', user.id).eq('status', 'pending').order('created_at', { ascending: false }).limit(1).maybeSingle(),
    db.from('posts').select('id', { count: 'exact', head: true }).eq('author_id', user.id).eq('status', 'active'),
    db.from('post_likes').select('post_id', { count: 'exact', head: true }).eq('user_id', user.id),
    db.from('comments').select('id', { count: 'exact', head: true }).eq('author_id', user.id),
  ]);
  for (const result of [profile, membership, request, posts, likes, comments]) if (result.error) throw result.error;
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
    companyRequestPending: Boolean(request.data),
    pendingCompanyName: request.data?.company_name ?? null,
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

// Sign-up verifies the email before the account exists: Supabase creates a pending user and emails a code.
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
async function isRegisteredUser(db: SupabaseClient, userId: string) {
  const { data, error } = await db.from('profiles').select('display_name').eq('id', userId).maybeSingle();
  if (error) throw error;
  return Boolean(data?.display_name?.trim());
}

// Test bypass: with DEV_MASTER_OTP set, its code passes sign-up (even if the email can't be sent) but the
// account stays unverified. DEV_MASTER_OTP=dynamic issues a random single-use code per email, printed to the
// server log; any other value is a fixed code. Leave it unset in production.
const devMasterOtp = () => (process.env.DEV_MASTER_OTP ?? '').trim();
const isDynamicDevOtp = () => devMasterOtp().toLowerCase() === 'dynamic';
const DEV_OTP_TTL_MS = 10 * 60 * 1000;
const devOtps = new Map<string, { code: string; exp: number }>();
const issueDevOtp = (email: string) => {
  if (!isDynamicDevOtp()) return;
  const code = randomInt(0, 1_000_000).toString().padStart(6, '0');
  devOtps.set(email, { code, exp: Date.now() + DEV_OTP_TTL_MS });
  console.log(`[DEV_MASTER_OTP] Sign-up code for ${email}: ${code}`);
};
const consumeDevOtp = (email: string, code: string) => {
  if (!devMasterOtp()) return false;
  if (!isDynamicDevOtp()) return safeEqual(code, devMasterOtp());
  const entry = devOtps.get(email);
  if (!entry || entry.exp < Date.now() || !safeEqual(code, entry.code)) return false;
  devOtps.delete(email);
  return true;
};
const BYPASS_TOKEN_TTL_MS = 30 * 60 * 1000;
const bypassSecret = () => process.env.SUPABASE_SERVICE_ROLE_KEY ?? '';
const signBypassToken = (email: string) => {
  const payload = Buffer.from(JSON.stringify({ email, exp: Date.now() + BYPASS_TOKEN_TTL_MS })).toString('base64url');
  return `devotp.${payload}.${createHmac('sha256', bypassSecret()).update(payload).digest('base64url')}`;
};
const readBypassToken = (token: string): string | null => {
  const [kind, payload, signature] = token.split('.');
  if (kind !== 'devotp' || !payload || !signature || !devMasterOtp() || !bypassSecret()) return null;
  const expected = createHmac('sha256', bypassSecret()).update(payload).digest('base64url');
  if (!safeEqual(signature, expected)) return null;
  try {
    const data = JSON.parse(Buffer.from(payload, 'base64url').toString()) as { email?: string; exp?: number };
    return typeof data.email === 'string' && typeof data.exp === 'number' && data.exp > Date.now() ? data.email : null;
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

app.post('/api/auth/email/send-otp', async (req, res) => {
  try {
    const email = typeof req.body?.email === 'string' ? req.body.email.trim().toLowerCase() : '';
    if (!EMAIL_PATTERN.test(email)) return errorResponse(res, 400, 'Enter a valid email address.');
    if (isAdminEmail(email)) return errorResponse(res, 409, `${EMAIL_TAKEN_MESSAGE} Sign in instead.`);
    const admin = adminClient();
    const existing = await findUserByEmail(admin, email);
    if (existing && await isRegisteredUser(admin, existing.id)) return errorResponse(res, 409, `${EMAIL_TAKEN_MESSAGE} Sign in instead.`);
    issueDevOtp(email);
    const { error } = await authClient().auth.signInWithOtp({ email, options: { shouldCreateUser: true, emailRedirectTo: `${frontendUrl}/verify-email` } });
    if (error) {
      if (devMasterOtp()) {
        console.warn('Sign-up code email failed; DEV_MASTER_OTP fallback is available:', error.message);
        return res.json({ sent: true, fallback: true });
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
    if (consumeDevOtp(email, code)) return res.json({ emailVerified: false, verificationToken: signBypassToken(email) });
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
    const bypassEmail = hasToken ? readBypassToken(verificationToken) : normalizedEmail;
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
    const emailVerified = !bypassEmail || pending?.app_metadata?.email_verified === true;
    const { data: saved, error: saveError } = pending
      ? await admin.auth.admin.updateUserById(pending.id, {
        password, email_confirm: true,
        user_metadata: { ...pending.user_metadata, display_name: name.trim() },
        app_metadata: { ...pending.app_metadata, email_verified: emailVerified },
      })
      : await admin.auth.admin.createUser({
        email: normalizedEmail, password, email_confirm: true,
        user_metadata: { display_name: name.trim() },
        app_metadata: { email_verified: false },
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
  return { user: data.user, token };
}

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
function notifyCompanySafely(input: Parameters<typeof notifyCompanyMembers>[0]) {
  void notifyCompanyMembers(input).catch((error) => {
    console.error('Company push delivery failed:', error instanceof Error ? error.message : 'unknown error');
  });
}

app.get('/api/community/feed', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const db = adminClient();
    const { data: membership, error: membershipError } = await db.from('company_memberships').select('company_id').eq('user_id', session.user.id).eq('status', 'active').limit(1).maybeSingle();
    if (membershipError) throw membershipError;
    // `global` shows every company's posts to any signed-in member; `company` (default) only the member's own company.
    const scope = req.query.scope === 'global' ? 'global' : 'company';
    // Cursor pagination: `limit` (1–50, default 50) posts older than the ISO `before` timestamp.
    const limit = Math.min(50, Math.max(1, Number.parseInt(String(req.query.limit ?? ''), 10) || 50));
    const before = typeof req.query.before === 'string' && !Number.isNaN(Date.parse(req.query.before)) ? req.query.before : null;
    if (scope === 'company' && !membership) return res.json([]);
    const loadPosts = (withArchive: boolean) => {
      let query = db.from('posts')
        .select(`id,body,status,${withArchive ? 'is_archived,is_admin,' : ''}is_anonymous,created_at,author_id,company_id,author:profiles!posts_author_id_fkey(display_name,role_title),company:companies(name),post_likes(user_id),comments(id)`)
        .in('status', ['active', 'removed']);
      if (withArchive) query = query.or(`is_archived.eq.false,author_id.eq.${session.user.id}`);
      if (scope === 'company') query = query.eq('company_id', membership!.company_id);
      if (before) query = query.lt('created_at', before);
      return query.order('created_at', { ascending: false }).limit(limit);
    };
    let { data, error } = await loadPosts(true);
    // 42703 = undefined column: database/002 or 003 migrations have not been applied yet.
    if (error?.code === '42703') ({ data, error } = await loadPosts(false));
    if (error) throw error;
    const now = Date.now();
    res.json((data ?? []).map((post: any) => {
      const minutes = Math.max(0, Math.floor((now - new Date(post.created_at).getTime()) / 60000));
      const isDeleted = post.status === 'removed';
      const time = minutes < 1 ? 'just now' : minutes < 60 ? `${minutes}m ago` : minutes < 1440 ? `${Math.floor(minutes / 60)}h ago` : `${Math.floor(minutes / 1440)}d ago`;
      return {
        id: post.id,
        person: post.is_anonymous ? 'Anonymous' : post.author?.display_name || 'Member',
        role: post.is_anonymous ? '' : post.author?.role_title || '',
        company: post.company?.name || '',
        time,
        createdAt: post.created_at,
        // Deleted posts stay in the feed as a flag only; clients hide them.
        body: isDeleted ? '' : post.body,
        likes: post.post_likes?.length ?? 0,
        comments: post.comments?.length ?? 0,
        anonymous: post.is_anonymous,
        liked: post.post_likes?.some((like: any) => like.user_id === session.user.id) ?? false,
        isOwner: post.author_id === session.user.id,
        isDeleted,
        isArchived: post.is_archived ?? false,
        isAdmin: post.is_admin ?? false,
      };
    }));
  } catch (error) { fail(res, error); }
});

app.get('/api/community/people', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const db = adminClient();
    const { data: membership, error: membershipError } = await db.from('company_memberships').select('company_id').eq('user_id', session.user.id).eq('status', 'active').limit(1).maybeSingle();
    if (membershipError) throw membershipError;
    if (!membership) return res.json([]);
    const { data, error } = await db.from('company_memberships')
      .select('user_id,profile:profiles!company_memberships_user_id_fkey(display_name,role_title)')
      .eq('company_id', membership.company_id).eq('status', 'active').order('created_at', { ascending: true });
    if (error) throw error;
    res.json((data ?? []).map((member: any) => ({
      id: member.user_id,
      name: member.profile?.display_name || 'Member',
      role: member.profile?.role_title || '',
      team: '',
    })));
  } catch (error) { fail(res, error); }
});

app.post('/api/community/posts', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const body = typeof req.body?.body === 'string' ? req.body.body.trim() : '';
    const isAnonymous = req.body?.anonymous === undefined ? false : req.body.anonymous;
    if (!body || body.length > 500 || typeof isAnonymous !== 'boolean') return errorResponse(res, 400, 'Post text must be 1–500 characters and anonymous must be a boolean.');
    const db = adminClient();
    const { data: membership, error: membershipError } = await db.from('company_memberships').select('company_id').eq('user_id', session.user.id).eq('status', 'active').limit(1).maybeSingle();
    if (membershipError) throw membershipError;
    if (!membership) return errorResponse(res, 403, 'Active company membership required.');
    const { data, error } = await db.from('posts').insert({ company_id: membership.company_id, author_id: session.user.id, body, is_anonymous: isAnonymous }).select('id').single();
    if (error) throw error;
    notifyCompanySafely({ companyId: membership.company_id, excludeUserId: session.user.id, title: 'New community post', body: 'A coworker shared a post with your company.', data: { type: 'post', postId: data.id } });
    res.status(201).json({ id: data.id });
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
    const { data, error } = await db.from('comments').insert({ post_id: post.id, author_id: session.user.id, body }).select('id,post_id,body,created_at').single();
    if (error) throw error;
    if (post.author_id !== session.user.id) {
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
    const { data: post, error: postError } = await db.from('posts').select('id,author_id,company_id,status').eq('id', req.params.id).maybeSingle();
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
    if (error) throw error;
    if (post.author_id !== session.user.id) {
      const { data: profile } = await db.from('profiles').select('display_name').eq('id', session.user.id).maybeSingle();
      notifySafely({ userId: post.author_id, category: 'reactions', title: 'New reaction', body: `${profile?.display_name || 'Someone'} liked your post.`, data: { type: 'reaction', postId: post.id } });
    }
    res.json({ liked: true });
  } catch (error) { fail(res, error); }
});

async function findActivePost(db: SupabaseClient, postId: string) {
  const { data, error } = await db.from('posts').select('id,author_id,company_id,status').eq('id', postId).maybeSingle();
  if (error) throw error;
  return data && data.status === 'active' ? data : null;
}

const excerpt = (text: string, max = 80) => (text.length > max ? `${text.slice(0, max - 1).trimEnd()}…` : text);

// Built from likes and comments on the member's posts; "seen" is kept in auth user metadata.
app.get('/api/notifications', async (req, res) => {
  try {
    const session = await authenticatedUser(req, res); if (!session) return;
    const db = adminClient();
    const { data: posts, error: postsError } = await db.from('posts').select('id,body').eq('author_id', session.user.id).eq('status', 'active').order('created_at', { ascending: false }).limit(200);
    if (postsError) throw postsError;
    if (!posts?.length) return res.json({ items: [], unreadCount: 0 });
    const postIds = posts.map(post => post.id);
    const [likes, comments] = await Promise.all([
      db.from('post_likes').select('post_id,user_id,created_at').in('post_id', postIds).neq('user_id', session.user.id).order('created_at', { ascending: false }).limit(50),
      db.from('comments').select('id,post_id,author_id,body,created_at').in('post_id', postIds).neq('author_id', session.user.id).order('created_at', { ascending: false }).limit(50),
    ]);
    if (likes.error) throw likes.error;
    if (comments.error) throw comments.error;
    const actorIds = [...new Set([...(likes.data ?? []).map(like => like.user_id), ...(comments.data ?? []).map(comment => comment.author_id)])];
    const { data: profiles, error: profilesError } = actorIds.length ? await db.from('profiles').select('id,display_name').in('id', actorIds) : { data: [], error: null };
    if (profilesError) throw profilesError;
    const names = new Map((profiles ?? []).map(profile => [profile.id, profile.display_name || 'Someone']));
    const bodies = new Map(posts.map(post => [post.id, post.body]));
    const seenAt = Date.parse(String(session.user.user_metadata?.notifications_seen_at ?? '')) || 0;
    const items = [
      ...(likes.data ?? []).map(like => ({ id: `like-${like.post_id}-${like.user_id}`, type: 'reaction' as const, actorName: names.get(like.user_id) || 'Someone', postId: like.post_id, postExcerpt: excerpt(bodies.get(like.post_id) || ''), comment: null as string | null, createdAt: like.created_at })),
      ...(comments.data ?? []).map(comment => ({ id: `comment-${comment.id}`, type: 'comment' as const, actorName: names.get(comment.author_id) || 'Someone', postId: comment.post_id, postExcerpt: excerpt(bodies.get(comment.post_id) || ''), comment: excerpt(comment.body, 120), createdAt: comment.created_at })),
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
    const { error } = await db.from('companies').insert(additions.map(row => ({ ...row, status: 'active' })));
    if (error) throw error;
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
    const { data, error } = await db.from('companies').update(changes).eq('id', String(req.params.id)).select('id').maybeSingle();
    if (error) throw error;
    if (!data) return errorResponse(res, 404, 'Company not found.');
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
  const { data: matching, error: matchError } = await db.from('company_requests').select('id,requested_by').eq('status', 'pending').ilike('company_name', escapeLike(name));
  if (matchError) throw matchError;
  const requests = matching?.length ? matching : [request];
  const membership = await db.from('company_memberships').upsert([...new Set(requests.map(r => r.requested_by))].map(userId => ({ user_id: userId, company_id: companyId, status: 'active', join_method: 'admin_approved' })), { onConflict: 'user_id,company_id' });
  if (membership.error) throw membership.error;
  const update = await db.from('company_requests').update({ status: 'approved', reviewed_at: new Date().toISOString() }).in('id', requests.map(r => r.id));
  if (update.error) throw update.error;
  for (const userId of new Set(requests.map(r => r.requested_by))) {
    notifySafely({ userId, category: 'company_updates', title: 'Company approved', body: `${name} is now live on Office Gossip.`, data: { type: 'company_approved', companyId: String(companyId) } });
  }
  return true;
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
    // 42P01 = missing table: announcements table from database/001_initial_schema.sql has not been applied yet.
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
