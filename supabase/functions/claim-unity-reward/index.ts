import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

/// Claim coins for completing a Unity rewarded video ad.
///
/// The app shows the ad via the Unity Ads SDK (Game ID 800417967,
/// placement BP_Rewarded_Android). When the user watches the FULL ad,
/// the app calls this function. Coins are credited server-side
/// (service role) — the app never writes to the ledger.
///
/// Rewards are coins (virtual currency), never cash — per Unity policy
/// and the app's own rules.
///
/// Anti-abuse:
/// - JWT auth (401 if invalid)
/// - Daily cap from app_config unity_reward_daily_cap (default 10)
/// - Reward from app_config unity_reward_coins (default 10)
/// - Minimum 30 seconds between claims (429 if too soon)
/// - Idempotent ledger entries via idempotency_key (409 on replay)
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const json = (body: unknown, status: number) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  // --- Auth: the caller's JWT must be valid ---
  const authHeader = req.headers.get('Authorization') ?? '';
  const { data: { user }, error: authError } = await supabase.auth.getUser(
    authHeader.replace('Bearer ', '')
  );
  if (authError || !user) {
    return json({ error: 'unauthorized' }, 401);
  }

  // --- Config: reward amount + daily cap (owner-tunable) ---
  const { data: cfgRows } = await supabase
    .from('app_config')
    .select('key, value')
    .in('key', ['unity_reward_coins', 'unity_reward_daily_cap']);

  const cfg: Record<string, string> = {};
  for (const r of cfgRows ?? []) cfg[r.key] = r.value;

  const rewardCoins = parseInt(cfg['unity_reward_coins'] ?? '10', 10);
  const dailyCap = parseInt(cfg['unity_reward_daily_cap'] ?? '10', 10);

  // A non-positive reward means the feature is disabled by the owner.
  if (rewardCoins <= 0) {
    return json({ error: 'disabled' }, 200);
  }

  const today = new Date().toISOString().split('T')[0];
  const now = new Date();

  // --- Daily cap: count today's unity_reward ledger entries ---
  const { data: todayEntries, error: countError } = await supabase
    .from('ledger')
    .select('id, created_at')
    .eq('user_id', user.id)
    .eq('type', 'unity_reward')
    .gte('created_at', `${today}T00:00:00Z`)
    .order('created_at', { ascending: false });

  if (countError) {
    return json({ error: 'db_error' }, 500);
  }

  const usedToday = (todayEntries ?? []).length;
  if (usedToday >= dailyCap) {
    return json({ error: 'cap_reached', remaining: 0, cap: dailyCap }, 409);
  }

  // --- Anti-spam: minimum 30 seconds between claims ---
  const lastEntry = (todayEntries ?? [])[0];
  if (lastEntry) {
    const elapsedSec =
      (now.getTime() - new Date(lastEntry.created_at).getTime()) / 1000;
    if (elapsedSec < 30) {
      return json({
        error: 'too_soon',
        retry_after_seconds: Math.ceil(30 - elapsedSec),
      }, 429);
    }
  }

  // --- Credit coins via the ledger (idempotent) ---
  const idemKey =
    `unity_reward:${user.id}:${today}:${usedToday + 1}:${Math.floor(now.getTime() / 30000)}`;

  const { data, error: insertError } = await supabase
    .from('ledger')
    .insert({
      user_id: user.id,
      amount_coins: rewardCoins,
      type: 'unity_reward',
      provider: 'unity_ads',
      ref_id: 'placement:BP_Rewarded_Android',
      idempotency_key: idemKey,
    })
    .select('id')
    .single();

  if (insertError) {
    // 23505 = unique violation on idempotency_key: a replayed claim.
    if ((insertError as { code?: string }).code === '23505') {
      return json({
        ok: true,
        coins: rewardCoins,
        remaining: dailyCap - usedToday - 1,
        duplicate: true,
      }, 200);
    }
    return json({ error: 'db_error' }, 500);
  }

  return json({
    ok: true,
    coins: rewardCoins,
    remaining: dailyCap - usedToday - 1,
    id: data.id,
  }, 200);
});
