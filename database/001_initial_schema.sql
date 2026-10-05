-- Office Gossip schema for PostgreSQL / Supabase.
-- WARNING: this script DROPS every Office Gossip table first, permanently deleting all app data
-- (companies, posts, memberships, reports, ...). Supabase auth users in auth.users are kept.
-- Run the whole file in the Supabase SQL editor.
create extension if not exists pgcrypto;

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
  company_id uuid not null references public.companies(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 500),
  is_anonymous boolean not null default false,
  -- Archived posts are hidden from everyone except the author.
  is_archived boolean not null default false,
  -- Posts published by the Office Gossip team; clients show an "Admin" tag.
  is_admin boolean not null default false,
  status text not null default 'active' check (status in ('active','under_review','removed')),
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

-- RLS and policies must be added before exposing any table to client credentials.
-- Preferred Phase 1 architecture: clients call the API; privileged service key stays server-side.
