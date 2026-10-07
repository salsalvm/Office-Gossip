-- Members following each other; following someone notifies them.
-- Safe to run on an existing database: it only adds this table. Run it in the Supabase SQL editor.
create table if not exists public.follows (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  following_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, following_id),
  check (follower_id <> following_id)
);
create index if not exists follows_following_idx on public.follows(following_id, created_at desc);
-- No policies: only the API's service role key reads and writes follows.
alter table public.follows enable row level security;
