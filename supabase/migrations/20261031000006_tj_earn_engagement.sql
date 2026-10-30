-- TJ Earn: Engagement mechanics (31 Oct 2026).
--
-- Competitive analysis (Swagbucks, Roz Dhan, Attapoll) identified these
-- high-impact retention mechanics. All coin grants happen ONLY in Edge
-- Functions (service role). The app never writes to the ledger.
--
-- Tables:
--   streaks            Daily check-in streak tracking + milestone bonuses
--   spins              Daily spin-wheel rewards
--   onboarding_tasks   New-user welcome checklist
--   devices            Device anti-fraud (one row per user+device hash)
--
-- Config keys (owner-tunable in app_config):
--   streak_bonus_7     '50'    coins for 7-day streak
--   streak_bonus_14    '120'   coins for 14-day streak
--   streak_bonus_21    '250'   coins for 21-day streak
--   streak_bonus_30    '500'   coins for 30-day streak
--   spin_rewards       '1,2,3,5,10,20'  weighted spin outcomes (coins)
--   spin_daily_limit   '1'     free spins per day
--   onboarding_bonus   '100'   coins for completing all onboarding tasks
--   referral_milestone_5   '2000'   bonus at 5 approved referrals
--   referral_milestone_10  '5000'   bonus at 10 approved referrals
--   referral_milestone_25  '15000'  bonus at 25 approved referrals

-- ============================================================
-- STREAKS: daily check-in streak tracking
-- ============================================================
create table if not exists public.streaks (
  user_id uuid primary key references auth.users(id) on delete cascade,
  current_streak int not null default 0,
  longest_streak int not null default 0,
  last_checkin_date date,
  total_checkins int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.streaks enable row level security;

-- Users can read their own streak; writes happen only via Edge Functions.
create policy "streaks_select_own"
  on public.streaks for select
  using (auth.uid() = user_id);

-- ============================================================
-- SPINS: daily spin-wheel rewards
-- ============================================================
create table if not exists public.spins (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  reward_coins int not null,
  spin_date date not null,
  created_at timestamptz not null default now()
);

alter table public.spins enable row level security;

create policy "spins_select_own"
  on public.spins for select
  using (auth.uid() = user_id);

create index if not exists spins_user_date_idx
  on public.spins (user_id, spin_date);

-- ============================================================
-- ONBOARDING_TASKS: new-user welcome checklist
-- ============================================================
create table if not exists public.onboarding_tasks (
  user_id uuid not null references auth.users(id) on delete cascade,
  task_key text not null,
  completed_at timestamptz not null default now(),
  primary key (user_id, task_key)
);

alter table public.onboarding_tasks enable row level security;

create policy "onboarding_select_own"
  on public.onboarding_tasks for select
  using (auth.uid() = user_id);

-- Valid task keys (enforced in Edge Function):
--   'profile'      Set display name
--   'checkin'      First daily check-in
--   'quiz'         First quiz completed
--   'spin'         First spin
--   'referral'     First referral share (copied link)

-- ============================================================
-- DEVICES: anti-fraud device tracking
-- ============================================================
create table if not exists public.devices (
  user_id uuid not null references auth.users(id) on delete cascade,
  device_hash text not null,
  device_model text,
  first_seen timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  primary key (user_id, device_hash)
);

alter table public.devices enable row level security;

-- Users cannot read devices (admin-only via Edge Function).
-- No select policy = no access.

create index if not exists devices_hash_idx
  on public.devices (device_hash);

-- ============================================================
-- REFERRAL MILESTONES: track which tier bonuses were paid
-- ============================================================
create table if not exists public.referral_milestones (
  user_id uuid not null references auth.users(id) on delete cascade,
  milestone int not null,
  paid_at timestamptz not null default now(),
  primary key (user_id, milestone)
);

alter table public.referral_milestones enable row level security;

create policy "referral_milestones_select_own"
  on public.referral_milestones for select
  using (auth.uid() = user_id);

-- ============================================================
-- CONFIG: engagement mechanic tuning
-- ============================================================
insert into public.app_config (key, value) values
  ('streak_bonus_7', '50'),
  ('streak_bonus_14', '120'),
  ('streak_bonus_21', '250'),
  ('streak_bonus_30', '500'),
  ('spin_rewards', '1,2,3,5,10,20'),
  ('spin_daily_limit', '1'),
  ('onboarding_bonus', '100'),
  ('referral_milestone_5', '2000'),
  ('referral_milestone_10', '5000'),
  ('referral_milestone_25', '15000')
on conflict (key) do nothing;
