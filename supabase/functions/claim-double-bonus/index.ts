import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

/// Double-reward bonus for a completed Unity rewarded video ad.
///
/// Jaani, 4 Nov 2026: after a reading claim (10 coins), the user may
/// OPT-IN to watch one Unity rewarded video (placement BP_Rewarded_Android)
/// to DOUBLE that claim. The bonus equals the original claim — credited
/// server-side, never trusted from the client.
///
/// Request body: { ref: string }
///   - App reading flow: ref = the article_id of the reading claim.
///   - (Future) web quiz flow: ref = the quiz claim's reference.
///
/// The server re-derives the original claim's ledger idempotency key:
///   `reading:<user_id>:<pkt_today>:<ref>`  (app flow)
///   `reading:<ref>`                        (web flow)
/// and validates the original claim exists, belongs to the caller, is a
/// `reading` ledger row created today (PKT), and was not already doubled.
/// The bonus is credited in the SAME amount as the original claim via a
/// `double_bonus` ledger row with idempotency key
/// `double_bonus:<user_id>:<pkt_today>:<ref>`.
///
/// Anti-abuse:
/// - JWT auth (401 if invalid)
/// - Original claim must exist + belong to caller + be today's (404)
/// - One double per claim — idempotent, replay returns ok/already (200)
/// - No amount is ever trusted from the client
/// - The app only shows the bonus when this function returns ok:true
///   (display must match actual payout — Jaani's honesty rule)
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const json = (body: unknown, status: number) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: 'invalid json' }, 400);
  }

  const ref = typeof body.ref === 'string' ? body.ref.trim() : '';
  if (!ref) return json({ error: 'ref required' }, 400);
  // Keep the key space clean — article/session ids are short alphanumerics.
  if (ref.length > 128) return json({ error: 'ref too long' }, 400);

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

  const pktDate = () =>
    new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Karachi' });
  const today = pktDate();

  // --- Find the original reading claim (server-derived keys only) ---
  const origKeys = [
    `reading:${user.id}:${today}:${ref}`,
    `reading:${ref}`,
  ];

  const { data: original, error: lookupError } = await service
    .from('ledger')
    .select('id, amount_coins, type, created_at')
    .eq('user_id', user.id)
    .eq('type', 'reading')
    .in('idempotency_key', origKeys)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (lookupError) return json({ error: 'db_error' }, 500);
  if (!original) return json({ error: 'claim_not_found' }, 404);

  // The claim must be today's (PKT) — yesterday's claims can't be doubled.
  const createdDay = new Date(original.created_at as string)
    .toLocaleDateString('en-CA', { timeZone: 'Asia/Karachi' });
  if (createdDay !== today) return json({ error: 'claim_not_found' }, 404);

  const bonusCoins = original.amount_coins as number;
  if (!Number.isInteger(bonusCoins) || bonusCoins <= 0) {
    return json({ error: 'invalid_claim' }, 422);
  }

  // --- Idempotency: one double per claim ---
  const doubleKey = `double_bonus:${user.id}:${today}:${ref}`;
  const { data: existing } = await service
    .from('ledger')
    .select('id, amount_coins')
    .eq('idempotency_key', doubleKey)
    .maybeSingle();
  if (existing) {
    return json(
      { ok: true, coins: existing.amount_coins as number, already: true },
      200,
    );
  }

  // --- Credit the bonus (same amount as the original claim) ---
  const { data, error: insertError } = await service
    .from('ledger')
    .insert({
      user_id: user.id,
      amount_coins: bonusCoins,
      type: 'double_bonus',
      provider: 'unity_ads',
      ref_id: original.id as string,
      idempotency_key: doubleKey,
    })
    .select('id')
    .single();

  if (insertError) {
    // 23505 = unique violation on idempotency_key: a replayed request.
    if ((insertError as { code?: string }).code === '23505') {
      return json({ ok: true, coins: bonusCoins, already: true }, 200);
    }
    return json({ error: 'db_error' }, 500);
  }

  await service.from('audit_logs').insert({
    actor: user.id,
    action: 'double_bonus_claimed',
    target: ref,
    details: { coins: bonusCoins, original_claim: original.id },
  });

  return json({ ok: true, coins: bonusCoins, id: data.id }, 200);
});
