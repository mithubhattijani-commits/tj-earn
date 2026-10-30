-- TJ Earn: Unity Ads rewarded video config (30 Oct 2026).
--
-- Unity Ads account: mithubhattijani@gmail.com (Individual)
-- Game ID: 800417967 (Android, "TJ Earn" project)
-- Rewarded placement: BP_Rewarded_Android (Active)
--
-- Config keys (owner-tunable):
--   unity_reward_coins     '10'   coins per completed rewarded ad
--   unity_reward_daily_cap '10'   max rewarded-ad claims per user per day
--
-- Rewards are coins (virtual currency), never cash — per Unity policy.
-- Coin grants happen ONLY in the claim-unity-reward Edge Function
-- (service role). The app never writes to the ledger.

insert into public.app_config (key, value) values
  ('unity_reward_coins', '10'),
  ('unity_reward_daily_cap', '10')
on conflict (key) do nothing;
