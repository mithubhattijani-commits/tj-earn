import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

/// Daily spin wheel.
///
/// One free spin per day (Roz Dhan-style). Rewards are weighted random
/// from the `spin_rewards` config (default: 1,2,3,5,10,20 coins).
/// Higher rewards are rarer — the server picks using a weighted distribution.
///
/// Anti-abuse:
/// - JWT auth (401 if invalid)
/// - Daily limit from `spin_daily_limit` config (409 if exceeded)
/// - Server-side random (app cannot influence the outcome)
/// - Idempotent ledger entries
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

  const authHeader = req.headers.get('Authorization') ?? '';
  const { data: { user }, error: authError } = await supabase.auth.getUser(
    authHeader.replace('Bearer ', '')
  );
  if (authError || !user) {
    return json({ error: 'unauthorized' }, 401);
  }

  // Config
  const { data: cfgRows } = await supabase
    .from('app_config')
    .select('key, value')
    .in('key', ['spin_rewards', 'spin_daily_limit']);
  const cfg: Record<string, string> = {};
  for (const r of cfgRows ?? []) cfg[r.key] = r.value;

  const rewards = (cfg['spin_rewards'] ?? '1,2,3,5,10,20')
    .split(',')
    .map(s => parseInt(s.trim(), 10))
    .filter(n => n > 0);
  const dailyLimit = parseInt(cfg['spin_daily_limit'] ?? '1', 10);

  if (rewards.length === 0) {
    return json({ error: 'disabled' }, 200);
  }

  const today = new Date().toISOString().split('T')[0];

  // Check daily limit
  const { data: todaySpins, error: countError } = await supabase
    .from('spins')
    .select('id')
    .eq('user_id', user.id)
    .eq('spin_date', today);

  if (countError) return json({ error: 'db_error' }, 500);
  if ((todaySpins ?? []).length >= dailyLimit) {
    return json({ error: 'limit_reached', remaining: 0 }, 409);
  }

  // Weighted random: lower rewards are more likely.
  // Weight = 1 / reward (e.g., 1 coin has 20x the weight of 20 coins).
  const weights = rewards.map(r => 1 / r);
  const totalWeight = weights.reduce((a, b) => a + b, 0);
  let roll = Math.random() * totalWeight;
  let rewardCoins = rewards[0];
  for (let i = 0; i < rewards.length; i++) {
    roll -= weights[i];
    if (roll <= 0) {
      rewardCoins = rewards[i];
      break;
    }
  }

  // Record the spin
  const { data: spin, error: spinError } = await supabase
    .from('spins')
    .insert({
      user_id: user.id,
      reward_coins: rewardCoins,
      spin_date: today,
    })
    .select('id')
    .single();

  if (spinError) return json({ error: 'db_error' }, 500);

  // Credit coins via ledger (idempotent)
  const idemKey = `spin:${user.id}:${today}:${spin.id}`;
  const { error: ledgerError } = await supabase
    .from('ledger')
    .insert({
      user_id: user.id,
      amount_coins: rewardCoins,
      type: 'spin_reward',
      provider: 'tj_earn',
      ref_id: `spin:${spin.id}`,
      idempotency_key: idemKey,
    });

  if (ledgerError && (ledgerError as { code?: string }).code !== '23505') {
    return json({ error: 'db_error' }, 500);
  }

  return json({
    ok: true,
    reward_coins: rewardCoins,
    spins_used: (todaySpins ?? []).length + 1,
    spins_remaining: dailyLimit - (todaySpins ?? []).length - 1,
  }, 200);
});
