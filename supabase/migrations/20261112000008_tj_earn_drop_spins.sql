-- Final build scope: drop the spin-wheel storage.
-- The spin wheel was removed (Task A); the spins table and its
-- app_config keys are no longer used.

drop table if exists public.spins cascade;

delete from public.app_config where key in ('spin_rewards', 'spin_daily_limit');
