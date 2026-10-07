-- Adds the sign-up name to codes on the admin console's "OTP codes" page.
-- Only needed if 002_signup_otps.sql was run before it included `name`. Run it in the Supabase SQL editor.
alter table public.signup_otps add column if not exists name text;
