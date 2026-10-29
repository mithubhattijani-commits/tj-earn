import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

/// TEST ONLY — Stage 1 stand-in for real provider callbacks.
///
/// Credits coins to a user so the wallet, history and withdrawal flows can
/// be tested end to end before any provider is connected. A replayed
/// `idempotency_key` is rejected with 409 (the ledger's UNIQUE constraint).
///
/// SAFETY: this function refuses to run unless the Supabase project sets
/// ALLOW_TEST_CALLBACKS=true. Delete it (or set the flag to false) before
/// any production use. Stage 2 replaces it with signed provider callbacks
/// (Unity Offerwall / AdGem) that verify signatures server-side.
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  const json = (body: unknown, status: number) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  if (Deno.env.get('ALLOW_TEST_CALLBACKS') !== 'true') {
    return json({ error: 'test callbacks disabled' }, 403);
  }
  let body: {
    user_id?: unknown;
    amount_coins?: unknown;
    idempotency_key?: unknown;
    provider?: unknown;
    type?: unknown;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'invalid json' }, 400);
  }
  if (
    typeof body.user_id !== 'string' || body.user_id.length === 0 ||
    typeof body.amount_coins !== 'number' ||
    !Number.isInteger(body.amount_coins) || body.amount_coins <= 0 ||
    typeof body.idempotency_key !== 'string' ||
    body.idempotency_key.length === 0
  ) {
    return json({ error: 'invalid request' }, 400);
  }
  const service = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );
  const { data, error } = await service
    .from('ledger')
    .insert({
      user_id: body.user_id,
      amount_coins: body.amount_coins,
      type: typeof body.type === 'string' ? body.type : 'offer',
      provider: typeof body.provider === 'string' ? body.provider : 'test',
      idempotency_key: body.idempotency_key,
    })
    .select('id')
    .single();
  if (error) {
    // 23505 = unique violation on idempotency_key: a replayed callback.
    if ((error as { code?: string }).code === '23505') {
      return json({ error: 'already_credited' }, 409);
    }
    return json({ error: 'insert failed' }, 500);
  }
  await service.from('audit_logs').insert({
    actor: 'system',
    action: 'test_callback_credited',
    target: data.id,
    details: {
      user_id: body.user_id,
      amount_coins: body.amount_coins,
      idempotency_key: body.idempotency_key,
    },
  });
  return json({ ok: true, id: data.id }, 200);
});
