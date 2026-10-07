-- Sign-up codes issued when DEV_MASTER_OTP=dynamic, shown to the admin console's "OTP codes" page.
-- Safe to run on an existing database: it only adds this table. Run it in the Supabase SQL editor.
create table if not exists public.signup_otps (
  email text primary key,
  code text not null check (code ~ '^[0-9]{6}$'),
  attempts integer not null default 0,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists signup_otps_created_idx on public.signup_otps(created_at desc);
-- No policies: only the API's service role key may read these codes.
alter table public.signup_otps enable row level security;
