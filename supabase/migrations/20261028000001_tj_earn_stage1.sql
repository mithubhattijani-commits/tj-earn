-- TJ Earn Stage 1 migration (Supabase / PostgreSQL).
-- Apply with the Supabase SQL editor or `supabase db push`.
-- This file creates the schema ONLY. No live project exists yet for Stage 1.

-- ---------------------------------------------------------------- profiles
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '',
  language_pref text not null default 'en'
    check (language_pref in ('en', 'ur')),
  created_at timestamptz not null default now()
);

-- Every new auth user gets a profile row automatically. The app never
-- creates profiles itself.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'display_name', '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ------------------------------------------------------------------ ledger
-- Append-only coin ledger. Balance = SUM(amount_coins) per user.
-- Positive = credit, negative = debit. Never edited, never deleted.
create table if not exists public.ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  amount_coins integer not null check (amount_coins <> 0),
  type text not null,
  ref_id text,
  provider text,
  idempotency_key text unique,
  created_at timestamptz not null default now()
);

-- -------------------------------------------------------------- withdrawals
create table if not exists public.withdrawals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  amount_coins integer not null check (amount_coins > 0),
  amount_pkr numeric(12, 2)
    generated always as (amount_coins::numeric / 100) stored,
  rail text not null check (rail in ('jazzcash', 'easypaisa', 'bank')),
  account_masked text not null,
  status text not null default 'pending'
    check (status in ('pending', 'fraud_hold', 'approved', 'rejected', 'paid')),
  tx_id text,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);

-- -------------------------------------------------------------- audit logs
-- Append-only. actor is a user id or 'system'.
create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor text not null,
  action text not null,
  target text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------------ config
create table if not exists public.app_config (
  key text primary key,
  value text not null
);

insert into public.app_config (key, value) values
  ('coin_rate_pkr', '0.01'),
  ('min_withdrawal_coins', '20000'),
  ('max_pending_withdrawals', '2'),
  ('daily_reward_cap', '20')
on conflict (key) do nothing;

-- ----------------------------------------------------------------- versions
-- One row per published build. The updater reads the highest version_code.
create table if not exists public.app_versions (
  version_code integer primary key,
  version_name text not null,
  apk_url text not null default '',
  notes text not null default '',
  force_update boolean not null default false,
  created_at timestamptz not null default now()
);

insert into public.app_versions
  (version_code, version_name, apk_url, notes, force_update)
values
  (1, '1.0.0', '', 'Stage 1 foundation build', false)
on conflict (version_code) do nothing;

-- ------------------------------------------------------- append-only guard
create or replace function public.prevent_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception 'append-only table: % is not allowed', TG_OP;
end;
$$;

drop trigger if exists ledger_no_update on public.ledger;
create trigger ledger_no_update
  before update or delete on public.ledger
  for each row execute function public.prevent_mutation();

drop trigger if exists audit_no_update on public.audit_logs;
create trigger audit_no_update
  before update or delete on public.audit_logs
  for each row execute function public.prevent_mutation();

-- ---------------------------------------------------------------------- RLS
alter table public.profiles enable row level security;
alter table public.ledger enable row level security;
alter table public.withdrawals enable row level security;
alter table public.audit_logs enable row level security;
alter table public.app_config enable row level security;
alter table public.app_versions enable row level security;

-- profiles: users read/update only their own row.
drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles
  for select to authenticated using (auth.uid() = id);
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (auth.uid() = id) with check (auth.uid() = id);

-- ledger: users read only their own rows. No INSERT/UPDATE/DELETE policy
-- exists for the authenticated role, so app-side writes are denied; only
-- the service role (Edge Functions) may write.
drop policy if exists ledger_select_own on public.ledger;
create policy ledger_select_own on public.ledger
  for select to authenticated using (auth.uid() = user_id);

-- withdrawals: users read their own rows and may insert their own row as
-- pending. Status changes have no policy for authenticated users, so they
-- can only happen through an Edge Function (service role).
drop policy if exists withdrawals_select_own on public.withdrawals;
create policy withdrawals_select_own on public.withdrawals
  for select to authenticated using (auth.uid() = user_id);
drop policy if exists withdrawals_insert_own on public.withdrawals;
create policy withdrawals_insert_own on public.withdrawals
  for insert to authenticated
  with check (auth.uid() = user_id and status = 'pending');

-- audit_logs: no policy for app roles at all (service role only).
-- app_config / app_versions: public read (rates, minimums, release info
-- are not secrets).
drop policy if exists app_config_select_public on public.app_config;
create policy app_config_select_public on public.app_config
  for select to anon, authenticated using (true);
drop policy if exists app_versions_select_public on public.app_versions;
create policy app_versions_select_public on public.app_versions
  for select to anon, authenticated using (true);

-- Defense in depth: revoke write privileges from app roles on the
-- append-only tables (service_role is unaffected by these revokes).
revoke update, delete on public.ledger from anon, authenticated;
revoke insert, update, delete on public.ledger from anon, authenticated;
revoke update, delete on public.audit_logs from anon, authenticated;
revoke update, delete on public.withdrawals from anon, authenticated;
