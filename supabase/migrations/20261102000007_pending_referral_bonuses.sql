-- Migration: pending_referral_bonuses for claim-based multi-level referrals
-- (Jaani, 2 Nov 2026): bonuses accumulate as pending, user claims them.
-- L1=200, L2=100, L3+=50, unlimited depth.

create table if not exists public.pending_referral_bonuses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  from_user_id uuid not null references public.profiles (id) on delete cascade,
  referral_id uuid not null references public.referrals (id) on delete cascade,
  level int not null check (level >= 1),
  coins int not null check (coins > 0),
  status text not null default 'pending'
    check (status in ('pending', 'claimed')),
  created_at timestamptz not null default now(),
  claimed_at timestamptz,
  -- Exactly-once: one pending record per (referral, level, user)
  unique (referral_id, level, user_id)
);

create index if not exists pending_bonuses_user_idx
  on public.pending_referral_bonuses (user_id);
create index if not exists pending_bonuses_status_idx
  on public.pending_referral_bonuses (status);

alter table public.pending_referral_bonuses enable row level security;

-- Users read their own pending bonuses.
drop policy if exists pending_bonuses_select_own on public.pending_referral_bonuses;
create policy pending_bonuses_select_own on public.pending_referral_bonuses
  for select to authenticated using (auth.uid() = user_id);

-- Only service role writes (Edge Functions).
revoke insert, update, delete on public.pending_referral_bonuses from anon, authenticated;
grant select on public.pending_referral_bonuses to authenticated;
