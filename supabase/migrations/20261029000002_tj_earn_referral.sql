-- TJ Earn Stage 2 migration: referral system (Phase 2).
-- Apply with the Supabase SQL editor or `supabase db push`.
-- This file creates schema ONLY. No code changes ride along.
--
-- Tables:
--   referral_codes — one unique, unguessable code per user.
--   referrals      — referrer -> referred attribution rows.
-- All writes go through Edge Functions (service_role). The app roles get
-- SELECT-only policies; there are deliberately NO insert/update/delete
-- policies for authenticated/anon, plus explicit revokes below.
--
-- Config keys (safe defaults — owner configures the budget later):
--   referral_reward_coins   '0'                 (no invented reward amount)
--   referral_eligibility_rule 'verified_activity'
--   referral_daily_cap      '20'
--   admin_user_ids          '{}'  (empty = review function denies everyone)

-- ------------------------------------------------------- referral_codes
create table if not exists public.referral_codes (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  code text not null unique,
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------ referrals
-- One referrer per referred user (referred_id UNIQUE). A referral pays out
-- at most once: approval writes a ledger row with idempotency_key
-- 'referral:<referral_id>', and approval is only allowed from
-- pending/eligible -> approved exactly once.
create table if not exists public.referrals (
  id uuid primary key default gen_random_uuid(),
  referrer_id uuid not null references public.profiles (id) on delete cascade,
  referred_id uuid not null unique references public.profiles (id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'eligible', 'approved', 'rejected')),
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  decided_by text,
  decision_reason text,
  check (referrer_id <> referred_id)
);

create index if not exists referrals_referrer_idx
  on public.referrals (referrer_id);
create index if not exists referrals_status_idx
  on public.referrals (status);

-- ---------------------------------------------------------------- config
insert into public.app_config (key, value) values
  ('referral_reward_coins', '0'),
  ('referral_eligibility_rule', 'verified_activity'),
  ('referral_daily_cap', '20'),
  ('admin_user_ids', '{}')
on conflict (key) do nothing;

-- ------------------------------------------------------------------ RLS
alter table public.referral_codes enable row level security;
alter table public.referrals enable row level security;

-- Users read only their own code.
drop policy if exists referral_codes_select_own on public.referral_codes;
create policy referral_codes_select_own on public.referral_codes
  for select to authenticated using (auth.uid() = user_id);

-- Users read referrals they are part of (as referrer or as referred).
-- No emails or other PII are stored here; history masking happens in the
-- Edge Function before anything reaches the client.
drop policy if exists referrals_select_involved on public.referrals;
create policy referrals_select_involved on public.referrals
  for select to authenticated
  using (auth.uid() = referrer_id or auth.uid() = referred_id);

-- Defense in depth: no write privileges for app roles on either table
-- (service_role is unaffected by these revokes; Edge Functions write).
revoke insert, update, delete on public.referral_codes from anon, authenticated;
revoke insert, update, delete on public.referrals from anon, authenticated;

-- ======================================================================
-- DOWN MIGRATION (run manually to reverse; kept as comments so the file
-- stays apply-only for `supabase db push`).
--
-- delete from public.app_config
--  where key in ('referral_reward_coins', 'referral_eligibility_rule',
--                'referral_daily_cap', 'admin_user_ids');
-- drop policy if exists referrals_select_involved on public.referrals;
-- drop policy if exists referral_codes_select_own on public.referral_codes;
-- drop table if exists public.referrals;
-- drop table if exists public.referral_codes;
-- ======================================================================
