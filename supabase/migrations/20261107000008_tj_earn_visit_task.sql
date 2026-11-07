-- TJ Earn: Visit task (Jaani, 7 Nov 2026).
--
-- Meta-compliant audience task: reward for VISITING the Nigraan TV
-- Facebook Page or the website — never for following/liking (prohibited
-- by Meta Platform Policy and unverifiable via the Graph API).
--
-- Reward: first-ever visit = 50 coins (one-time per user), then 5 coins
-- once per PKT calendar day. All coin grants happen ONLY in the
-- `claim-visit` Edge Function (service role). The app never writes to
-- the ledger.
--
-- Tables:
--   visits             One row per user: first visit + daily claims
--
-- Config keys (owner-tunable in app_config):
--   visit_first_reward '50'   coins for the first-ever visit
--   visit_daily_reward '5'    coins per daily visit after the first

-- ============================================================
-- VISITS: one row per user
-- ============================================================
create table if not exists public.visits (
  user_id uuid primary key references auth.users(id) on delete cascade,
  first_visit_at timestamptz not null default now(),
  last_visit_date date not null,
  last_destination text not null default 'website'
    check (last_destination in ('facebook', 'website')),
  total_visits int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.visits enable row level security;

-- Users can read their own visit row; writes happen only via Edge Functions.
create policy "visits_select_own"
  on public.visits for select
  using (auth.uid() = user_id);

-- ============================================================
-- CONFIG: visit reward tuning
-- ============================================================
insert into public.app_config (key, value) values
  ('visit_first_reward', '50'),
  ('visit_daily_reward', '5')
on conflict (key) do nothing;
