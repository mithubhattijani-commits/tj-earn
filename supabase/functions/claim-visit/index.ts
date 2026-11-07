import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
const corsHeaders = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' };

/// Visit task (Jaani, 7 Nov 2026) — Meta-compliant way to bring app users
/// to the Nigraan TV Facebook Page and the website.
///
/// Reward: FIRST-EVER visit = 50 coins (one-time per user), then 5 coins
/// once per PKT calendar day. The reward is for VISITING only.
///
/// Meta policy: paying coins for FOLLOWING / liking a Page is prohibited
/// (Platform Policy: "You must not incentivize people to use social
/// plugins or to like a Page") and unverifiable — the Graph API reveals
/// no individual followers. This function never asks about, checks, or
/// rewards a follow or a like. The app opens the destination in the
/// external browser; the user taps Claim afterwards. Trust-based, like
/// check-in: the server enforces one claim per day, never the visit itself.
///
/// Rules:
/// - One claim per PKT calendar day (409 if already claimed today).
/// - First-ever claim pays visit_first_reward (default 50); later claims
///   pay visit_daily_reward (default 5). Both overridable via app_config.
/// - Idempotent ledger entry per user per day (first-visit key is
///   per-user, daily keys are per-user-per-day).
/// - JWT auth required (401 if invalid).
/// - `destination` must be 'facebook' or 'website' (400 otherwise);
///   it is recorded for analytics only and never changes the reward.
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
    Deno.env.get('SUPABASE_ANON_KEY')!,
    {
      global: {
        headers: { Authorization: req.headers.get('Authorization') ?? '' },
      },
    },
  );
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser();
  if (authError || !user) return json({ error: 'unauthorized' }, 401);

  const service = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  let body: { destination?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'invalid_json' }, 400);
  }
  const destination = body.destination ?? '';
  if (destination !== 'facebook' && destination !== 'website') {
    return json({ error: 'invalid_destination' }, 400);
  }

  // PKT calendar day boundaries (same as claim-checkin).
  const pkt = (d: Date) =>
    d.toLocaleDateString('en-CA', { timeZone: 'Asia/Karachi' });
  const today = pkt(new Date());

  // Reward config (overridable via app_config).
  const { data: cfgRows } = await service
    .from('app_config')
    .select('key,value')
    .in('key', ['visit_first_reward', 'visit_daily_reward']);
  const cfg: Record<string, string> = {};
  for (const r of cfgRows ?? []) cfg[r.key] = String(r.value ?? '');
  const firstReward = Math.max(0, parseInt(cfg['visit_first_reward'] ?? '50', 10) || 0);
  const dailyReward = Math.max(0, parseInt(cfg['visit_daily_reward'] ?? '5', 10) || 0);

  // Load the user's visit row (one row per user).
  const { data: visit } = await service
    .from('visits')
    .select('*')
    .eq('user_id', user.id)
    .maybeSingle();

  // Already claimed today?
  if (visit && visit.last_visit_date === today) {
    return json({
      error: 'already_claimed',
      already_claimed: true,
      first_visit: false,
      reward_coins: dailyReward,
      total_visits: visit.total_visits as number,
    }, 409);
  }

  const firstVisit = !visit;
  const coins = firstVisit ? firstReward : dailyReward;

  // Record the visit (insert on first visit, update afterwards).
  if (firstVisit) {
    const { error } = await service.from('visits').insert({
      user_id: user.id,
      first_visit_at: new Date().toISOString(),
      last_visit_date: today,
      last_destination: destination,
      total_visits: 1,
    });
    if (error) return json({ error: 'db_error' }, 500);
  } else {
    const { error } = await service
      .from('visits')
      .update({
        last_visit_date: today,
        last_destination: destination,
        total_visits: (visit.total_visits as number) + 1,
        updated_at: new Date().toISOString(),
      })
      .eq('user_id', user.id);
    if (error) return json({ error: 'db_error' }, 500);
  }

  // Idempotent coin grant (one per user for the first visit, one per
  // user per PKT day afterwards).
  const idemKey = firstVisit
    ? `visit:first:${user.id}`
    : `visit:daily:${user.id}:${today}`;
  const { data: existing } = await service
    .from('ledger')
    .select('id')
    .eq('idempotency_key', idemKey)
    .maybeSingle();

  if (!existing && coins > 0) {
    const { error: ledgerError } = await service.from('ledger').insert({
      user_id: user.id,
      amount_coins: coins,
      type: 'task_visit',
      ref_id: firstVisit ? 'visit:first' : `visit:${today}`,
      provider: 'tjearn',
      idempotency_key: idemKey,
    });
    if (ledgerError) {
      const msg = String(
        (ledgerError as { message?: unknown }).message ?? '',
      ).toLowerCase();
      const isReplay =
        (ledgerError as { code?: unknown }).code === '23505' ||
        msg.includes('duplicate');
      if (!isReplay) return json({ error: 'could not credit reward' }, 500);
    }
  }

  // Audit trail (best-effort: a failure here must never fail a claim
  // whose coins are already credited).
  try {
    await service.from('task_completions').insert({
      user_id: user.id,
      task_key: 'visit',
      task_date: today,
      slot: 0,
      coins,
      meta: { destination, first_visit: firstVisit, source: 'app' },
    });
  } catch { /* audit only */ }
  try {
    await service.from('audit_logs').insert({
      actor: user.id,
      action: 'visit_claimed',
      target: destination,
      details: { coins, first_visit: firstVisit, destination },
    });
  } catch { /* audit only */ }

  return json({
    ok: true,
    coins,
    first_visit: firstVisit,
    total_visits: firstVisit ? 1 : (visit.total_visits as number) + 1,
  }, 200);
});
