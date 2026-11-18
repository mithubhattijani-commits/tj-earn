import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { createHash } from 'node:crypto';
import { corsHeaders } from '../_shared/cors.ts';

/// RapidoReach server-to-server postback (Stage 2, real provider callback).
///
/// Contract: RapidoReach v2 docs (docs.rapidoreach.com/docs/v2/sdk/callbacks).
/// RapidoReach sends a GET request to this endpoint when a transaction
/// completes. Query params: transactionId, offerInvitationId, endUserId
/// (our Supabase user UUID), userId (RapidoReach UID), status/cmd,
/// currencyAmt, amt, offerHash, txnHash, currencyName, offerType,
/// deviceType, intergrationMethod (misspelling is RapidoReach's).
///
/// Verification (lowercase MD5, constant-time compare):
///   offerHash = md5(transactionId + AppKey)
///   txnHash   = md5(transactionId + AppSecret)
/// The hashes cover ONLY the transactionId — NOT currencyAmt or any other
/// field. So the amount is trusted ONLY after both hashes verify (they
/// prove the callback came from RapidoReach for this transactionId).
///
/// Statuses (v2): C = complete, F = screenout, P = overquota,
/// R = reversal (currencyAmt can be negative). Credit exactly the
/// currencyAmt RapidoReach sends for C/F/P; for R insert the negative
/// amount as a deduction. Each transactionId + status is processed once:
/// idempotency_key = `rapidoreach:<transactionId>:<status>` (the ledger's
/// UNIQUE constraint rejects replays with 409 -> 200 already-processed).
///
/// Response: the delivery code checks the HTTP STATUS, not a body "1"/"0".
/// 200 only after successful processing; non-200 when processing fails.
///
/// Secrets (Supabase Edge Function secrets, never in code):
///   RAPIDOREACH_APP_KEY, RAPIDOREACH_APP_SECRET — from the saved TJ Earn
///   app's Credentials tab in the RapidoReach dashboard.
/// Endpoint is public (verify_jwt=false): RapidoReach calls with no JWT;
/// the MD5 hashes are the authentication.
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  const json = (body: unknown, status: number) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  if (req.method !== 'GET') {
    return json({ error: 'method not allowed' }, 405);
  }

  const url = new URL(req.url);
  const q = url.searchParams;
  const transactionId = q.get('transactionId') ?? '';
  const endUserId = q.get('endUserId') ?? '';
  const status = q.get('status') ?? q.get('cmd') ?? '';
  const currencyAmtRaw = q.get('currencyAmt') ?? '';
  const offerHash = (q.get('offerHash') ?? '').toLowerCase();
  const txnHash = (q.get('txnHash') ?? '').toLowerCase();

  if (
    transactionId.length === 0 || endUserId.length === 0 ||
    !['C', 'F', 'P', 'R'].includes(status) ||
    currencyAmtRaw.length === 0 || offerHash.length === 0 ||
    txnHash.length === 0
  ) {
    return json({ error: 'invalid request' }, 403);
  }
  const currencyAmt = Number(currencyAmtRaw);
  if (!Number.isInteger(currencyAmt)) {
    return json({ error: 'invalid amount' }, 403);
  }
  // Reversals deduct (negative amount); any other status must not be negative.
  if (status === 'R' ? currencyAmt >= 0 : currencyAmt < 0) {
    return json({ error: 'invalid amount for status' }, 403);
  }

  const appKey = Deno.env.get('RAPIDOREACH_APP_KEY') ?? '';
  const appSecret = Deno.env.get('RAPIDOREACH_APP_SECRET') ?? '';
  if (appKey.length === 0 || appSecret.length === 0) {
    console.error('rapidoreach-postback: secrets not configured');
    return json({ error: 'not configured' }, 500);
  }

  const md5 = (s: string) =>
    createHash('md5').update(s).digest('hex').toLowerCase();
  // Constant-time string compare (no Node Buffer global in the edge runtime).
  const safeEqual = (a: string, b: string) => {
    if (a.length !== b.length) return false;
    let diff = 0;
    for (let i = 0; i < a.length; i++) {
      diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
    }
    return diff === 0;
  };
  const offerOk = safeEqual(md5(transactionId + appKey), offerHash);
  const txnOk = safeEqual(md5(transactionId + appSecret), txnHash);
  if (!offerOk || !txnOk) {
    console.error('rapidoreach-postback: hash mismatch', {
      transactionId,
      status,
    });
    return json({ error: 'invalid signature' }, 403);
  }

  const service = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  // The wall signs UIDs with the hyphen-stripped UUID (32 hex chars —
  // see rapidoreach-wall-url), so endUserId may arrive without hyphens.
  // Re-hyphenate a 32-hex id (8-4-4-4-12) and retry the lookup once;
  // the plain hyphenated-UUID path is unchanged. [userId] below is
  // always the canonical hyphenated UUID used for the ledger + audit.
  let userId = endUserId;
  let { data: user, error: userError } =
    await service.auth.admin.getUserById(userId);
  if ((userError || !user?.user) && /^[0-9a-fA-F]{32}$/.test(endUserId)) {
    userId =
      `${endUserId.slice(0, 8)}-${endUserId.slice(8, 12)}-` +
      `${endUserId.slice(12, 16)}-${endUserId.slice(16, 20)}-` +
      endUserId.slice(20);
    ({ data: user, error: userError } =
      await service.auth.admin.getUserById(userId));
  }
  if (userError || !user?.user) {
    return json({ error: 'unknown user' }, 403);
  }

  // Zero-amount callbacks owe nothing; the ledger bans amount 0, so
  // there is nothing to insert — acknowledge without crediting.
  if (currencyAmt === 0) {
    return json({ ok: true, credited: 0 }, 200);
  }

  const isReversal = status === 'R';
  const idempotencyKey = `rapidoreach:${transactionId}:${status}`;
  const { data, error } = await service
    .from('ledger')
    .insert({
      user_id: userId,
      amount_coins: currencyAmt,
      type: 'survey',
      provider: 'rapidoreach',
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
    console.error('rapidoreach-postback: ledger insert failed', error);
    return json({ error: 'insert failed' }, 500);
  }
  await service.from('audit_logs').insert({
    actor: 'system',
    action: isReversal
      ? 'rapidoreach_callback_reversal'
      : 'rapidoreach_callback_credited',
    target: data.id,
    details: {
      user_id: userId,
      amount_coins: currencyAmt,
      transaction_id: transactionId,
      status,
    },
  });
  return json({ ok: true, id: data.id }, 200);
});
