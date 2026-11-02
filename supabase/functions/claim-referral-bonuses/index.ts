import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

/// Claims pending referral bonuses: moves them from pending_referral_bonuses
/// to the ledger, then marks them claimed. (Jaani, 2 Nov 2026 — claim model:
/// bonuses accumulate as pending, user taps CLAIM for the satisfaction +
/// visibility.)
///
/// Body: { ids?: string[] } — specific bonus IDs to claim, or omit/empty
/// to claim ALL pending for the caller.
///
/// Exactly-once: ledger insert uses idempotency_key
/// `referral-bonus:<bonus_id>`; the bonus row is marked claimed only after
/// the ledger write succeeds. Replays are safe.
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

  let body: { ids?: unknown };
  try {
    body = await req.json();
  } catch {
    body = {};
  }
  const ids = Array.isArray(body.ids)
    ? (body.ids as unknown[]).filter((x) => typeof x === 'string') as string[]
    : [];

  const service = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  // Fetch the caller's pending bonuses (optionally filtered by IDs).
  let query = service
    .from('pending_referral_bonuses')
    .select('id,coins,level,from_user_id,referral_id')
    .eq('user_id', user.id)
    .eq('status', 'pending');
  if (ids.length > 0) {
    query = query.in('id', ids);
  }
  const { data: pending, error: fetchErr } = await query;
  if (fetchErr) return json({ error: 'could not load bonuses' }, 500);

  const rows = (pending ?? []) as Array<{
    id: string;
    coins: number;
    level: number;
    from_user_id: string;
    referral_id: string;
  }>;
  if (rows.length === 0) {
    return json({ ok: true, claimed: 0, coins: 0 }, 200);
  }

  let claimed = 0;
  let coins = 0;
  const now = new Date().toISOString();
  for (const b of rows) {
    try {
      // 1. Write ledger entry (idempotent).
      const { error: ledErr } = await service.from('ledger').insert({
        user_id: user.id,
        amount_coins: b.coins,
        type: b.level === 1 ? 'referral' : b.level === 2 ? 'referral_l2' : 'referral_l3plus',
        ref_id: b.referral_id,
        provider: 'tjearn',
        idempotency_key: `referral-bonus:${b.id}`,
      });
      if (ledErr) {
        const msg = String(
          (ledErr as { message?: unknown }).message ?? '',
        ).toLowerCase();
        const isReplay =
          (ledErr as { code?: unknown }).code === '23505' ||
          msg.includes('duplicate');
        if (!isReplay) continue; // Skip this one, try others.
      }
      // 2. Mark claimed (only if still pending — prevents double-claim races).
      const { data: updated } = await service
        .from('pending_referral_bonuses')
        .update({ status: 'claimed', claimed_at: now })
        .eq('id', b.id)
        .eq('status', 'pending')
        .select('id');
      if (updated && (updated as unknown[]).length > 0) {
        claimed++;
        coins += b.coins;
      }
    } catch {
      // Individual failure shouldn't block others.
    }
  }

  await service.from('audit_logs').insert({
    actor: user.id,
    action: 'referral_bonuses_claimed',
    details: { claimed, coins },
  });

  return json({ ok: true, claimed, coins }, 200);
});
