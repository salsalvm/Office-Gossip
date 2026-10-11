import type { SupabaseClient, User } from '@supabase/supabase-js';

export type AccountStatus = 'active' | 'deactivated';
export type AccountActor = 'self' | 'admin' | 'system';

// Error `data.code` clients branch on to offer restoring the account instead of a plain sign-in error.
export const ACCOUNT_DEACTIVATED = 'ACCOUNT_DEACTIVATED';

export const accountGraceDays = () => {
  const days = Number.parseInt(process.env.ACCOUNT_DELETION_GRACE_DAYS ?? '', 10);
  return Number.isInteger(days) && days >= 0 ? Math.min(days, 365) : 30;
};

// Mirrored into app_metadata by set_account_status, so checking it costs no query.
export const isDeactivated = (user: User) => user.app_metadata?.account_status === 'deactivated';
export const deactivatedBy = (user: User): AccountActor | null =>
  isDeactivated(user) ? (user.app_metadata?.deactivated_by === 'admin' ? 'admin' : 'self') : null;

// Password re-entry is only possible for accounts that have one (not Google-only sign-ins).
export const hasPasswordSignIn = (user: User) => {
  const providers = user.app_metadata?.providers;
  return Array.isArray(providers) ? providers.includes('email') : user.app_metadata?.provider === 'email';
};

export type AccountLifecycle = {
  status: AccountStatus;
  deactivatedAt: string | null;
  deactivatedBy: 'self' | 'admin' | null;
  purgeAfter: string | null;
  canRestore: boolean;
};

const LIFECYCLE_MISSING_MESSAGE = 'Account deletion is not set up yet. Run the account lifecycle block of database/scheme.sql in Supabase.';
const httpError = (message: string, status: number) => Object.assign(new Error(message), { status });
// PGRST202/42883: function missing, 42703/PGRST204: column missing, 42P01/PGRST205: table missing.
const isMissingSchema = (error: { code?: string } | null) => ['PGRST202', '42883', '42703', 'PGRST204', '42P01', 'PGRST205'].includes(error?.code ?? '');

type ProfileRow = { account_status: AccountStatus; deactivated_at: string | null; deactivated_by: 'self' | 'admin' | null; purge_after: string | null };
const toLifecycle = (row: ProfileRow | null): AccountLifecycle => {
  const status = row?.account_status ?? 'active';
  const purgeAfter = row?.purge_after ?? null;
  return {
    status,
    deactivatedAt: row?.deactivated_at ?? null,
    deactivatedBy: row?.deactivated_by ?? null,
    purgeAfter,
    // Admin deactivations are moderation decisions; only the member's own deletion can be undone by signing in.
    canRestore: status === 'deactivated' && row?.deactivated_by === 'self' && (!purgeAfter || Date.parse(purgeAfter) > Date.now()),
  };
};

export async function setAccountStatus(db: SupabaseClient, userId: string, status: AccountStatus, actor: AccountActor, reason?: string | null) {
  const { data, error } = await db.rpc('set_account_status', {
    p_user_id: userId, p_status: status, p_actor: actor, p_reason: reason ?? null, p_grace_days: accountGraceDays(),
  });
  if (isMissingSchema(error)) throw httpError(LIFECYCLE_MISSING_MESSAGE, 503);
  if (error?.code === 'P0002') throw httpError('Account not found.', 404);
  if (error) throw error;
  return toLifecycle(data as ProfileRow);
}

export async function accountLifecycle(db: SupabaseClient, userId: string) {
  const { data, error } = await db.from('profiles').select('account_status,deactivated_at,deactivated_by,purge_after').eq('id', userId).maybeSingle();
  if (isMissingSchema(error)) return toLifecycle(null);
  if (error) throw error;
  return toLifecycle(data as ProfileRow | null);
}

// Deleting the auth user cascades to the profile and everything that references it (posts, likes, devices, ...).
export async function purgeAccount(db: SupabaseClient, userId: string, actor: AccountActor, reason?: string | null) {
  const { data, error } = await db.auth.admin.getUserById(userId);
  if (error?.status === 404 || (!error && !data.user)) throw httpError('Account not found.', 404);
  if (error) throw error;
  const audit = await db.from('account_events').insert({ user_id: userId, email: data.user.email ?? null, event: 'purged', actor, reason: reason ?? null });
  if (audit.error && !isMissingSchema(audit.error)) throw audit.error;
  const { error: deleteError } = await db.auth.admin.deleteUser(userId);
  if (deleteError) throw deleteError;
}

const PURGE_BATCH_SIZE = 100;
// Works through due accounts in batches; safe to call repeatedly from a scheduler or the admin console.
export async function purgeDueAccounts(db: SupabaseClient, maxAccounts = 1000) {
  let purged = 0;
  let failed = 0;
  while (purged + failed < maxAccounts) {
    const { data, error } = await db.from('profiles').select('id').eq('account_status', 'deactivated')
      .lte('purge_after', new Date().toISOString()).order('purge_after').limit(Math.min(PURGE_BATCH_SIZE, maxAccounts - purged - failed));
    if (isMissingSchema(error)) throw httpError(LIFECYCLE_MISSING_MESSAGE, 503);
    if (error) throw error;
    if (!data?.length) break;
    let batchFailed = 0;
    for (const row of data) {
      try { await purgeAccount(db, String(row.id), 'system', 'Deletion grace period ended'); purged += 1; }
      catch (purgeError) {
        batchFailed += 1;
        console.error(`Purging account ${row.id} failed:`, purgeError instanceof Error ? purgeError.message : purgeError);
      }
    }
    failed += batchFailed;
    // Failed rows stay due and would be re-selected forever; retry them on the next run instead.
    if (batchFailed) break;
  }
  return { purged, failed };
}

export type AdminAccountRow = {
  id: string; email: string | null; display_name: string | null; company_name: string | null; account_status: AccountStatus;
  deactivated_at: string | null; deactivated_by: 'self' | 'admin' | null; deactivation_reason: string | null;
  purge_after: string | null; created_at: string; last_sign_in_at: string | null; total_count: number;
};

export async function listAccounts(db: SupabaseClient, options: { status: AccountStatus | null; query: string | null; limit: number; offset: number }) {
  const [list, deactivated, due, all] = await Promise.all([
    db.rpc('admin_list_accounts', { p_status: options.status, p_query: options.query, p_limit: options.limit, p_offset: options.offset }),
    db.from('profiles').select('id', { count: 'exact', head: true }).eq('account_status', 'deactivated'),
    db.from('profiles').select('id', { count: 'exact', head: true }).eq('account_status', 'deactivated').lte('purge_after', new Date().toISOString()),
    db.from('profiles').select('id', { count: 'exact', head: true }),
  ]);
  for (const result of [list, deactivated, due, all]) {
    if (isMissingSchema(result.error)) throw httpError(LIFECYCLE_MISSING_MESSAGE, 503);
    if (result.error) throw result.error;
  }
  const rows = (list.data ?? []) as AdminAccountRow[];
  return {
    rows,
    total: rows[0]?.total_count ?? 0,
    counts: { all: all.count ?? 0, active: (all.count ?? 0) - (deactivated.count ?? 0), deactivated: deactivated.count ?? 0, dueForPurge: due.count ?? 0 },
  };
}
