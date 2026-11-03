import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
const corsHeaders = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' };

/// Daily check-in with streak progression (Jaani, 3 Nov 2026).
///
/// Reward formula: Day 1 = 10 coins, Day 2 = 15, Day 3 = 20, ...
///   coins = min(10 + (streak_day - 1) * 5, 100)
/// The daily reward caps at 100 coins (reached on Day 19).
///
/// Rules:
/// - One check-in per PKT calendar day (409 if already checked in).
/// - Consecutive PKT day continues the streak; a missed day resets to Day 1.
/// - Idempotent ledger entry per user per day.
/// - JWT auth required (401 if invalid).
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

  // PKT calendar day boundaries.
  const pkt = (d: Date) =>
    d.toLocaleDateString('en-CA', { timeZone: 'Asia/Karachi' });
  const now = new Date();
  const today = pkt(now);
  const yesterday = pkt(new Date(now.getTime() - 86400000));

  // Reward config (overridable via app_config).
  const { data: cfgRows } = await service
    .from('app_config')
    .select('key,value')
    .in('key', ['checkin_base_coins', 'checkin_step_coins', 'checkin_max_coins']);
  const cfg: Record<string, string> = {};
  for (const r of cfgRows ?? []) cfg[r.key] = String(r.value ?? '');
  const base = Math.max(0, parseInt(cfg['checkin_base_coins'] ?? '10', 10) || 0);
  const step = Math.max(0, parseInt(cfg['checkin_step_coins'] ?? '5', 10) || 0);
  const maxCoins = Math.max(1, parseInt(cfg['checkin_max_coins'] ?? '100', 10) || 0);
  const coinsForDay = (day: number) => Math.min(base + (day - 1) * step, maxCoins);

  // Load or create the streak row.
  let { data: streak } = await service
    .from('streaks')
    .select('*')
    .eq('user_id', user.id)
    .maybeSingle();

  if (!streak) {
    const { data: created, error } = await service
      .from('streaks')
      .insert({
        user_id: user.id,
        current_streak: 1,
        longest_streak: 1,
        last_checkin_date: today,
        total_checkins: 1,
      })
      .select()
      .single();
    if (error) return json({ error: 'db_error' }, 500);
    streak = created;
  } else {
    // Already checked in today?
    if (streak.last_checkin_date === today) {
      const day = streak.current_streak as number;
      return json({
        error: 'already_claimed',
        already_claimed: true,
        streak_day: day,
        coins_today: coinsForDay(day),
        next_coins: coinsForDay(day + 1),
      }, 409);
    }

    // Consecutive day continues; a miss resets to Day 1.
    const newStreak = streak.last_checkin_date === yesterday
      ? (streak.current_streak as number) + 1
      : 1;

    const { data: updated, error } = await service
      .from('streaks')
      .update({
        current_streak: newStreak,
        longest_streak: Math.max(streak.longest_streak as number, newStreak),
        last_checkin_date: today,
        total_checkins: (streak.total_checkins as number) + 1,
        updated_at: new Date().toISOString(),
      })
      .eq('user_id', user.id)
      .select()
      .single();
    if (error) return json({ error: 'db_error' }, 500);
    streak = updated;
  }

  const streakDay = streak.current_streak as number;
  const coins = coinsForDay(streakDay);

  // Idempotent coin grant (one per user per PKT day).
  const idemKey = `checkin:${user.id}:${today}`;
  const { data: existing } = await service
    .from('ledger')
    .select('id')
    .eq('idempotency_key', idemKey)
    .maybeSingle();

  if (!existing && coins > 0) {
    const { error: ledgerError } = await service.from('ledger').insert({
      user_id: user.id,
      amount_coins: coins,
      type: 'checkin',
      ref_id: `day-${streakDay}`,
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

  // Record in task_completions for the daily-cap/audit trail.
  await service.from('task_completions').insert({
    user_id: user.id,
    task_key: 'checkin',
    task_date: today,
    slot: 0,
    coins,
    meta: { streak_day: streakDay, source: 'app' },
  });

  await service.from('audit_logs').insert({
    actor: user.id,
    action: 'checkin_claimed',
    target: `day-${streakDay}`,
    details: { coins, streak_day: streakDay },
  });

  return json({
    ok: true,
    coins,
    streak_day: streakDay,
    next_coins: coinsForDay(streakDay + 1),
    longest_streak: streak.longest_streak,
    total_checkins: streak.total_checkins,
  }, 200);
});
