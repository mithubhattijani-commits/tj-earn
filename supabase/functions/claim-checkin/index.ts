import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

/// Daily check-in — FLAT payout (compliant model, v1.0.25).
///
/// Replaces the deployed v7, which hardcoded an escalating streak payout
/// (min(10 + (streak_day - 1) * 5, 100)) against the user-approved flat
/// 10 coins/day. This version credits exactly
/// app_config `daily_checkin_coins` (default 10) on every claim, no matter
/// the streak. The streak is still tracked in `checkin_claims` (for
/// display and for the separate `claim-streak` milestone bonuses) but it
/// no longer changes the daily amount.
///
/// Contract (matches the v1.0.25 app, `SupabaseService.claimCheckin`):
/// - POST with the caller's JWT (verify_jwt ON).
/// - 200 { ok: true, coins, already: false, streak_day } on a fresh claim.
/// - 409 { ok: false, already: true, coins, streak_day } when the user
///   already claimed today (the app renders this as state, not an error).
/// - One claim per user per UTC day, enforced by the
///   UNIQUE (user_id, claim_date) constraint on `checkin_claims` and by
///   the ledger idempotency key `checkin-<user_id>-<YYYY-MM-DD>`.
///
/// Exactly-once: the ledger insert carries the idempotency key, so a
/// retry after a partial failure can never double-credit. If a claim row
/// exists but its ledger row is missing (old partial failure), the
/// duplicate branch credits the ledger before answering, so the user is
/// never marked claimed without receiving the coins.
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

  // UTC day (matches the deployed v7 and the existing claim rows).
  const now = new Date();
  const today = now.toISOString().slice(0, 10);
  const idemKey = `checkin-${user.id}-${today}`;

  // Flat daily amount from app_config (approved 10/day); 10 when unset.
  const { data: cfg } = await service
    .from('app_config')
    .select('value')
    .eq('key', 'daily_checkin_coins')
    .maybeSingle();
  const parsed = parseInt(String(cfg?.value ?? '10'), 10);
  const coins = Number.isFinite(parsed) && parsed >= 0 ? parsed : 10;

  // (a) Duplicate check — already claimed today?
  const { data: existing } = await service
    .from('checkin_claims')
    .select('id, coins_earned, streak_day')
    .eq('user_id', user.id)
    .eq('claim_date', today)
    .maybeSingle();
  if (existing) {
    const row = existing as {
      coins_earned: number;
      streak_day: number;
    };
    // Self-heal an old partial failure: claim row exists but no ledger
    // credit yet — credit it now, then report success.
    const { data: led } = await service
      .from('ledger')
      .select('id')
      .eq('idempotency_key', idemKey)
      .maybeSingle();
    if (!led) {
      const { error: healErr } = await service.from('ledger').insert({
        user_id: user.id,
        amount_coins: row.coins_earned,
        type: 'checkin',
        provider: 'tj_earn',
        ref_id: `checkin:${today}`,
        idempotency_key: idemKey,
      });
      if (!healErr) {
        return json(
          {
            ok: true,
            coins: row.coins_earned,
            already: false,
            streak_day: row.streak_day,
          },
          200,
        );
      }
    }
    return json(
      {
        ok: false,
        already: true,
        coins: row.coins_earned,
        streak_day: row.streak_day,
      },
      409,
    );
  }

  // (b) Streak — consecutive UTC days only (display + milestones).
  const yesterday = new Date(now.getTime() - 24 * 60 * 60 * 1000)
    .toISOString()
    .slice(0, 10);
  const { data: last } = await service
    .from('checkin_claims')
    .select('claim_date, streak_day')
    .eq('user_id', user.id)
    .order('claim_date', { ascending: false })
    .limit(1)
    .maybeSingle();
  const streakDay =
    last && (last as { claim_date: string }).claim_date === yesterday
      ? ((last as { streak_day: number }).streak_day ?? 0) + 1
      : 1;

  // (c) Credit the ledger first (idempotent — a replay is a 23505, not a
  // double credit). If this is a replay of a partial failure, the coins
  // are already in; report already-claimed.
  const { error: ledErr } = await service.from('ledger').insert({
    user_id: user.id,
    amount_coins: coins,
    type: 'checkin',
    provider: 'tj_earn',
    ref_id: `checkin:${today}`,
    idempotency_key: idemKey,
  });
  if (ledErr) {
    const code = String((ledErr as { code?: unknown }).code ?? '');
    const msg = String((ledErr as { message?: unknown }).message ?? '')
      .toLowerCase();
    if (code === '23505' || msg.includes('duplicate')) {
      return json({ ok: false, already: true, coins, streak_day: streakDay }, 409);
    }
    return json({ error: 'could not credit check-in' }, 500);
  }

  // (d) Record the claim (streak + amount). If this fails the credit
  // above still stands; the next attempt hits the ledger replay path.
  const { error: claimErr } = await service.from('checkin_claims').insert({
    user_id: user.id,
    claim_date: today,
    streak_day: streakDay,
    coins_earned: coins,
  });
  if (claimErr) {
    const code = String((claimErr as { code?: unknown }).code ?? '');
    if (code === '23505') {
      return json({ ok: false, already: true, coins, streak_day: streakDay }, 409);
    }
    // Credit succeeded; claim row failed (transient). Still a success —
    // the retry path will see the ledger row and answer already-claimed.
  }

  await service.from('audit_logs').insert({
    actor: user.id,
    action: 'checkin_claimed',
    details: { coins, streak_day: streakDay, claim_date: today },
  });

  return json({ ok: true, coins, already: false, streak_day: streakDay }, 200);
});
