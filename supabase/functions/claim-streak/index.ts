import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

/// Claim daily check-in streak.
///
/// Called after a successful daily check-in (claim-checkin). Tracks the
/// user's consecutive-day streak and pays milestone bonuses at 7/14/21/30
/// days (Swagbucks-style retention mechanic).
///
/// Anti-abuse:
/// - JWT auth (401 if invalid)
/// - One streak claim per day (409 if already claimed today)
/// - Streak resets if a day is missed
/// - Milestone bonuses are idempotent (one payout per milestone)
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

  // Config: milestone bonuses
  const { data: cfgRows } = await supabase
    .from('app_config')
    .select('key, value')
    .in('key', [
      'streak_bonus_7', 'streak_bonus_14',
      'streak_bonus_21', 'streak_bonus_30',
    ]);
  const cfg: Record<string, string> = {};
  for (const r of cfgRows ?? []) cfg[r.key] = r.value;

  const milestones: Record<number, number> = {
    7: parseInt(cfg['streak_bonus_7'] ?? '50', 10),
    14: parseInt(cfg['streak_bonus_14'] ?? '120', 10),
    21: parseInt(cfg['streak_bonus_21'] ?? '250', 10),
    30: parseInt(cfg['streak_bonus_30'] ?? '500', 10),
  };

  const today = new Date().toISOString().split('T')[0];
  const yesterday = new Date(Date.now() - 86400000).toISOString().split('T')[0];

  // Get or create streak row
  let { data: streak } = await supabase
    .from('streaks')
    .select('*')
    .eq('user_id', user.id)
    .single();

  if (!streak) {
    const { data: created, error } = await supabase
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
    // Already claimed today?
    if (streak.last_checkin_date === today) {
      return json({
        error: 'already_claimed',
        current_streak: streak.current_streak,
      }, 409);
    }

    // Consecutive day? (yesterday = continue, else reset to 1)
    const newStreak = streak.last_checkin_date === yesterday
      ? streak.current_streak + 1
      : 1;

    const { data: updated, error } = await supabase
      .from('streaks')
      .update({
        current_streak: newStreak,
        longest_streak: Math.max(streak.longest_streak, newStreak),
        last_checkin_date: today,
        total_checkins: streak.total_checkins + 1,
        updated_at: new Date().toISOString(),
      })
      .eq('user_id', user.id)
      .select()
      .single();
    if (error) return json({ error: 'db_error' }, 500);
    streak = updated;
  }

  // Milestone bonus? (idempotent via ledger idempotency_key)
  let bonusCoins = 0;
  const milestone = milestones[streak.current_streak];
  if (milestone && milestone > 0) {
    const idemKey = `streak_bonus:${user.id}:${streak.current_streak}`;
    const { error: bonusError } = await supabase
      .from('ledger')
      .insert({
        user_id: user.id,
        amount_coins: milestone,
        type: 'streak_bonus',
        provider: 'tj_earn',
        ref_id: `streak:${streak.current_streak}`,
        idempotency_key: idemKey,
      });
    // 23505 = already paid (idempotent)
    if (!bonusError || (bonusError as { code?: string }).code === '23505') {
      bonusCoins = milestone;
    }
  }

  return json({
    ok: true,
    current_streak: streak.current_streak,
    longest_streak: streak.longest_streak,
    total_checkins: streak.total_checkins,
    bonus_coins: bonusCoins,
    next_milestone: [7, 14, 21, 30].find(m => m > streak.current_streak) ?? null,
  }, 200);
});
