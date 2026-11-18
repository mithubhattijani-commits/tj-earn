import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { createHmac } from 'node:crypto';
import { corsHeaders } from '../_shared/cors.ts';

/// Offerwall.GG server-to-server postback (Stage 2, real provider callback).
///
/// Contract: Offerwall docs (offerwall.gg/developers/postbacks).
/// Offerwall sends a GET request (query string) to the postback URL set on
/// the placement; POST application/x-www-form-urlencoded with the same
/// fields is also accepted. Fields: userId (our Supabase user UUID, passed
/// in the wall URL), transactionId (unique, stable, SAME on reversal),
/// offerId, offerName, goalId, currencyAmount (FRACTIONAL, up to 4
/// decimals, NEGATIVE on reversal), currencyName, payoutUsd (NOT signed —
/// reporting only, never trusted for credit), status ('credited' or
/// 'reversed'), test ('1' from the dashboard test button — NEVER credit),
/// timestamp, signature.
///
/// Verification (HMAC-SHA256, constant-time compare):
///   signature = hmac_sha256("userId:transactionId:currencyAmount", secret)
/// The RAW currencyAmount string exactly as received is hashed — it is NOT
/// reformatted or rounded before hashing. payoutUsd is outside the digest.
///
/// Amounts: currencyAmount is already in OUR currency (TJ Earn coins;
/// Offerwall converts payoutUsd at the placement's units-per-USD rate,
/// 28000 coins per $1). The ledger's amount_coins is integer-only, so
/// round ONCE per the Offerwall doc's safe pairing: credit = floor(amount),
/// reversal = ceil(amount) — the credit and its reversal then have the
/// same magnitude, so a rounded-up credit + rounded-down reversal can
/// never leave the user permanently ahead. Zero after rounding owes
/// nothing (the ledger bans amount 0) and is acknowledged without insert.
///
/// Reversals: only reverse a conversion currently held as credited (a
/// ledger row with idempotency_key `offerwall:<transactionId>:credited`
/// must exist). The negative amount is inserted as a deduction with
/// idempotency_key `offerwall:<transactionId>:reversed`. Idempotency is
/// keyed on (transactionId, status): idempotency_key =
/// `offerwall:<transactionId>:<status>` (the ledger's UNIQUE constraint
/// rejects replays with 23505 -> 200 already-processed).
///
/// Response: 200 ONLY after the ledger insert durably succeeded. 403 on
/// invalid request / bad signature / unknown user. 500 on insert failure
/// (so Offerwall retries). Any 2xx means "I have this".
///
/// Secrets (Supabase Edge Function secrets, never in code):
///   OFFERWALL_SECRET — from the Offerwall dashboard (placement secret
///   key). Until it is set the function answers 500 'not configured'.
/// Endpoint is public (verify_jwt=false): Offerwall calls with no JWT;
/// the HMAC signature is the authentication.
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  const json = (body: unknown, status: number) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  if (req.method !== 'GET' && req.method !== 'POST') {
    return json({ error: 'method not allowed' }, 405);
  }

  // GET: fields arrive as query string. POST: same fields as
  // application/x-www-form-urlencoded body.
  let params: URLSearchParams;
  if (req.method === 'GET') {
    params = new URL(req.url).searchParams;
  } else {
    const contentType = req.headers.get('content-type') ?? '';
    if (!contentType.includes('application/x-www-form-urlencoded')) {
      return json({ error: 'unsupported content type' }, 403);
    }
    params = new URLSearchParams(await req.text());
  }

  const userId = params.get('userId') ?? '';
  const transactionId = params.get('transactionId') ?? '';
  const status = params.get('status') ?? '';
  const currencyAmountRaw = params.get('currencyAmount') ?? '';
  const signature = (params.get('signature') ?? '').toLowerCase();
  const test = params.get('test') ?? '';

  if (
    userId.length === 0 || transactionId.length === 0 ||
    !['credited', 'reversed'].includes(status) ||
    currencyAmountRaw.length === 0 || signature.length === 0
  ) {
    return json({ error: 'invalid request' }, 403);
  }
  const currencyAmount = Number(currencyAmountRaw);
  if (!Number.isFinite(currencyAmount)) {
    return json({ error: 'invalid amount' }, 403);
  }
  // Reversals carry a negative amount; credits must not be negative.
  if (status === 'reversed' ? currencyAmount >= 0 : currencyAmount < 0) {
    return json({ error: 'invalid amount for status' }, 403);
  }

  const secret = Deno.env.get('OFFERWALL_SECRET') ?? '';
  if (secret.length === 0) {
    console.error('offerwall-postback: secret not configured');
    return json({ error: 'not configured' }, 500);
  }

  // Constant-time string compare (no Node Buffer global in the edge runtime).
  const safeEqual = (a: string, b: string) => {
    if (a.length !== b.length) return false;
    let diff = 0;
    for (let i = 0; i < a.length; i++) {
      diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
    }
    return diff === 0;
  };
  // HMAC over the RAW currencyAmount string exactly as received.
  const expected = createHmac('sha256', secret)
    .update(`${userId}:${transactionId}:${currencyAmountRaw}`)
    .digest('hex')
    .toLowerCase();
  if (!safeEqual(expected, signature)) {
    console.error('offerwall-postback: signature mismatch', {
      transactionId,
      status,
    });
    return json({ error: 'invalid signature' }, 403);
  }

  // Dashboard test button: signature verified above, but never credit.
  if (test === '1') {
    return json({ ok: true, test: true }, 200);
  }

  const service = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  // The ledger FK requires a real auth user; reject unknown users
  // outright instead of failing the insert and triggering retries.
  const { data: user, error: userError } =
    await service.auth.admin.getUserById(userId);
  if (userError || !user?.user) {
    return json({ error: 'unknown user' }, 403);
  }

  // Integer-only ledger: round once, safe pairing (credit down, reversal
  // up) so credit and reversal have the same magnitude.
  const isReversal = status === 'reversed';
  const amountCoins = isReversal
    ? Math.ceil(currencyAmount)
    : Math.floor(currencyAmount);

  // Zero-amount callbacks owe nothing; the ledger bans amount 0, so
  // there is nothing to insert — acknowledge without crediting.
  if (amountCoins === 0) {
    return json({ ok: true, credited: 0 }, 200);
  }

  const idempotencyKey = `offerwall:${transactionId}:${status}`;

  // A reversal only claws back a conversion currently held as credited.
  // If no credited row exists there is nothing to reverse (already
  // reversed, or never credited here) — acknowledge without inserting.
  if (isReversal) {
    const { data: credited } = await service
      .from('ledger')
      .select('id')
      .eq('idempotency_key', `offerwall:${transactionId}:credited`)
      .maybeSingle();
    if (!credited) {
      return json({ ok: true, nothing_to_reverse: true }, 200);
    }
  }

  const { data, error } = await service
    .from('ledger')
    .insert({
      user_id: userId,
      amount_coins: amountCoins,
      type: 'survey',
      provider: 'offerwall',
      ref_id: transactionId,
      idempotency_key: idempotencyKey,
    })
    .select('id')
    .single();
  if (error) {
    // 23505 = unique violation on idempotency_key: a replayed callback.
    if ((error as { code?: string }).code === '23505') {
      return json({ ok: true, already_processed: true }, 200);
    }
    console.error('offerwall-postback: ledger insert failed', error);
    return json({ error: 'insert failed' }, 500);
  }
  await service.from('audit_logs').insert({
    actor: 'system',
    action: isReversal
      ? 'offerwall_callback_reversal'
      : 'offerwall_callback_credited',
    target: data.id,
    details: {
      user_id: userId,
      amount_coins: amountCoins,
      transaction_id: transactionId,
      status,
    },
  });
  return json({ ok: true, id: data.id }, 200);
});
