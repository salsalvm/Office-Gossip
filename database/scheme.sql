-- Office Gossip schema for PostgreSQL / Supabase.
-- WARNING: this script DROPS every Office Gossip table first, permanently deleting all app data
-- (companies, posts, memberships, reports, ...). Supabase auth users in auth.users are kept.
-- Run the whole file in the Supabase SQL editor. To add a single missing table to an existing database
-- without wiping data, run only that table's `create table` block.
create extension if not exists pgcrypto;

drop table if exists public.account_events cascade;
drop table if exists public.signup_otps cascade;
drop table if exists public.follows cascade;
drop table if exists public.announcements cascade;
drop table if exists public.user_devices cascade;
drop table if exists public.notification_preferences cascade;
drop table if exists public.company_requests cascade;
drop table if exists public.reports cascade;
drop table if exists public.post_likes cascade;
drop table if exists public.comments cascade;
drop table if exists public.posts cascade;
drop table if exists public.company_memberships cascade;
drop table if exists public.profiles cascade;
drop table if exists public.companies cascade;

create table if not exists public.companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  website_domain text,
  approved_email_domains text[] not null default '{}',
  status text not null default 'active' check (status in ('pending_review','active','disabled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists companies_name_lower_uq on public.companies (lower(name));

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  username text unique,
  role_title text,
  bio text,
  theme_preference text not null default 'system' check (theme_preference in ('system','light','dark')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.company_memberships (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','active','rejected','left')),
  join_method text not null default 'request' check (join_method in ('request','invite','admin_approved','verified_domain')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(user_id, company_id)
);
create index if not exists memberships_company_status_idx on public.company_memberships(company_id, status);

create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  -- Null only while the author's requested company awaits approval (status 'pending_company').
  company_id uuid references public.companies(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 500),
  is_anonymous boolean not null default false,
  -- Archived posts are hidden from everyone except the author.
  is_archived boolean not null default false,
  -- Posts published by the Office Gossip team; clients show an "Admin" tag.
  is_admin boolean not null default false,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists posts_company_created_idx on public.posts(company_id, created_at desc) where status = 'active';

create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now()
);

create table if not exists public.post_likes (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(post_id, user_id)
);

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  -- Snapshot of the reporter at report time, shown to admins in the moderation queue.
  reporter_name text not null default '',
  reporter_email text not null default '',
  reason text not null,
  status text not null default 'open' check (status in ('open','reviewing','resolved','dismissed')),
  created_at timestamptz not null default now(),
  unique(post_id, reporter_id)
);

create table if not exists public.company_requests (
  id uuid primary key default gen_random_uuid(),
  requested_by uuid not null references public.profiles(id) on delete cascade,
  company_name text not null,
  website_domain text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references public.profiles(id) on delete set null
);

create table if not exists public.notification_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  comments boolean not null default true,
  reactions boolean not null default true,
  company_updates boolean not null default true,
  updated_at timestamptz not null default now()
);
create table if not exists public.user_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  platform text not null check (platform in ('ios','android','web')),
  push_token text not null unique,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

-- Admin "Flash updates": sent to everyone, one user, or one company.
create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  message text not null check (char_length(message) between 1 and 500),
  audience text not null check (audience in ('everyone','user','company')),
  target_user_id uuid references public.profiles(id) on delete cascade,
  target_company_id uuid references public.companies(id) on delete cascade,
  created_at timestamptz not null default now(),
  check (
    (audience = 'everyone' and target_user_id is null and target_company_id is null)
    or (audience = 'user' and target_user_id is not null)
    or (audience = 'company' and target_company_id is not null)
  )
);
create index if not exists announcements_created_idx on public.announcements(created_at desc);
alter table public.announcements enable row level security;

-- Members following each other; following someone notifies them.
create table if not exists public.follows (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  following_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, following_id),
  check (follower_id <> following_id)
);
create index if not exists follows_following_idx on public.follows(following_id, created_at desc);
alter table public.follows enable row level security;

-- Sign-up codes issued when DEV_MASTER_OTP=dynamic, shown on the admin console's "OTP codes" page.
-- No policies: only the API's service role key may read these codes.
create table if not exists public.signup_otps (
  email text primary key,
  name text,
  code text not null check (code ~ '^[0-9]{6}$'),
  -- true once the code reached the inbox; only emailed codes mark an account as verified.
  emailed boolean not null default false,
  attempts integer not null default 0,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists signup_otps_created_idx on public.signup_otps(created_at desc);
alter table public.signup_otps enable row level security;

-- Account lifecycle: "Delete account" deactivates the account (hidden from everyone, sessions revoked) and
-- schedules a purge after a grace period. Signing in again with the same credentials offers to restore it.
-- Idempotent: safe to run on an existing database on its own.
alter table public.profiles
  add column if not exists account_status text not null default 'active',
  add column if not exists deactivated_at timestamptz,
  add column if not exists deactivated_by text,
  add column if not exists deactivation_reason text,
  add column if not exists purge_after timestamptz;
alter table public.profiles drop constraint if exists profiles_account_status_check;
alter table public.profiles add constraint profiles_account_status_check check (account_status in ('active','deactivated'));
alter table public.profiles drop constraint if exists profiles_deactivated_by_check;
alter table public.profiles add constraint profiles_deactivated_by_check check (deactivated_by in ('self','admin'));
create index if not exists profiles_purge_due_idx on public.profiles(purge_after) where account_status = 'deactivated';

-- Held posts: members whose requested company awaits admin approval can still post. Those posts have no
-- company, are visible only to their author, and are published to the company once it is approved.
-- Idempotent: safe to run on an existing database on its own.
alter table public.posts alter column company_id drop not null;
alter table public.posts drop constraint if exists posts_status_check;
alter table public.posts add constraint posts_status_check check (status in ('active','under_review','removed','pending_company'));
alter table public.posts drop constraint if exists posts_company_required_check;
alter table public.posts add constraint posts_company_required_check check (company_id is not null or status in ('pending_company','removed'));
create index if not exists posts_held_author_idx on public.posts(author_id) where status = 'pending_company';

-- Audit trail; no foreign key so the history outlives purged accounts.
create table if not exists public.account_events (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  email text,
  event text not null check (event in ('deactivated','restored','purged')),
  actor text not null check (actor in ('self','admin','system')),
  reason text,
  created_at timestamptz not null default now()
);
create index if not exists account_events_user_idx on public.account_events(user_id, created_at desc);
alter table public.account_events enable row level security;

-- One transaction for every side of a status change. auth.users.raw_app_meta_data mirrors the status because
-- the API checks it on each request without an extra query; deleting auth.sessions revokes refresh tokens.
create or replace function public.set_account_status(
  p_user_id uuid, p_status text, p_actor text, p_reason text default null, p_grace_days integer default 30
) returns public.profiles
language plpgsql security definer set search_path = public, auth as $$
declare
  v_email text;
  v_profile public.profiles;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
begin
  if p_status not in ('active','deactivated') then raise exception 'invalid account status %', p_status using errcode = '22023'; end if;
  select email into v_email from auth.users where id = p_user_id;
  if not found then raise exception 'account not found' using errcode = 'P0002'; end if;
  insert into public.profiles (id) values (p_user_id) on conflict (id) do nothing;
  update public.profiles set
    account_status = p_status,
    deactivated_at = case when p_status = 'deactivated' then now() end,
    deactivated_by = case when p_status = 'deactivated' then p_actor end,
    deactivation_reason = case when p_status = 'deactivated' then v_reason end,
    purge_after = case when p_status = 'deactivated' then now() + make_interval(days => greatest(p_grace_days, 0)) end,
    updated_at = now()
  where id = p_user_id
  returning * into v_profile;
  update auth.users set raw_app_meta_data = case when p_status = 'deactivated'
      then coalesce(raw_app_meta_data, '{}'::jsonb) || jsonb_build_object('account_status', 'deactivated', 'deactivated_by', p_actor)
      else (coalesce(raw_app_meta_data, '{}'::jsonb) - 'deactivated_by') || jsonb_build_object('account_status', 'active')
    end
  where id = p_user_id;
  if p_status = 'deactivated' then
    delete from auth.sessions where user_id = p_user_id;
    delete from public.user_devices where user_id = p_user_id;
  end if;
  insert into public.account_events (user_id, email, event, actor, reason)
  values (p_user_id, v_email, case when p_status = 'deactivated' then 'deactivated' else 'restored' end, p_actor, v_reason);
  return v_profile;
end $$;
revoke all on function public.set_account_status(uuid, text, text, text, integer) from public, anon, authenticated;
grant execute on function public.set_account_status(uuid, text, text, text, integer) to service_role;

-- Paginated, searchable account list for the admin console (emails live in auth.users).
create or replace function public.admin_list_accounts(
  p_status text default null, p_query text default null, p_limit integer default 50, p_offset integer default 0
) returns table (
  id uuid, email text, display_name text, company_name text, account_status text, deactivated_at timestamptz,
  deactivated_by text, deactivation_reason text, purge_after timestamptz, created_at timestamptz,
  last_sign_in_at timestamptz, total_count bigint
)
language sql stable security definer set search_path = public, auth as $$
  select u.id, u.email::text, p.display_name, c.name, p.account_status, p.deactivated_at, p.deactivated_by,
    p.deactivation_reason, p.purge_after, u.created_at, u.last_sign_in_at, count(*) over ()
  from public.profiles p
  join auth.users u on u.id = p.id
  left join lateral (
    select co.name from public.company_memberships m join public.companies co on co.id = m.company_id
    where m.user_id = p.id and m.status = 'active' limit 1
  ) c on true
  where (p_status is null or p.account_status = p_status)
    and (p_query is null or u.email ilike '%' || p_query || '%' or p.display_name ilike '%' || p_query || '%')
  order by coalesce(p.deactivated_at, u.created_at) desc
  limit least(greatest(p_limit, 1), 200) offset greatest(p_offset, 0);
$$;
revoke all on function public.admin_list_accounts(text, text, integer, integer) from public, anon, authenticated;
grant execute on function public.admin_list_accounts(text, text, integer, integer) to service_role;

-- RLS and policies must be added before exposing any table to client credentials.
-- Preferred Phase 1 architecture: clients call the API; privileged service key stays server-side.
