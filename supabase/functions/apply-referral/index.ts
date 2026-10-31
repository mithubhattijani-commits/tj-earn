import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

/// Records a referral attribution: the caller was invited via {code}.
///
/// Rules, all enforced server-side:
/// - the code must exist (unknown code -> 404, no hint about valid codes)
/// - the caller cannot apply their own code (self-referral -> 400)
/// - the caller can have at most one referrer (referred_id is UNIQUE;
///   a different code afterwards -> 409)
/// - idempotent: re-applying the SAME code returns the existing row
///   (ok:true, already:true) — never a duplicate row
/// - rate limit: max 5 attempts/hour per user, tracked in audit_logs
///   (the attempt is recorded even when rejected, for abuse monitoring)
///
/// IMMEDIATE CREDIT (Jaani, 31 Oct 2026): a successful apply now credits
/// the referrer IMMEDIATELY — no admin review wait. The referral is
/// created with status 'approved', decided_at = now, decided_by =
/// 'system:auto-credit', and the ledger row is written in the same call
/// with idempotency_key 'referral:<referral_id>' (exactly-once: a replay
/// can never double-credit). The reward amount comes from
/// app_config.referral_reward_coins (owner-set, currently 200 coins).
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

  let body: { code?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'invalid json' }, 400);
  }
  const code =
    typeof body.code === 'string' ? body.code.trim().toUpperCase() : '';
  if (!/^[A-Z2-9]{8}$/.test(code)) {
    return json({ error: 'invalid code' }, 400);
  }

  const service = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  // Rate limit: 5 attempts per rolling hour, tracked in the audit trail.
  const hourAgo = new Date(Date.now() - 3600_000).toISOString();
  const { count } = await service
    .from('audit_logs')
    .select('id', { count: 'exact', head: true })
    .eq('actor', user.id)
    .eq('action', 'referral_apply_attempt')
    .gte('created_at', hourAgo);
  await service.from('audit_logs').insert({
    actor: user.id,
    action: 'referral_apply_attempt',
    details: { code },
  });
  if ((count ?? 0) >= 5) return json({ error: 'rate limited' }, 429);

  // Resolve the code to its owner.
  const { data: codeRow } = await service
    .from('referral_codes')
    .select('user_id')
    .eq('code', code)
    .maybeSingle();
  if (!codeRow || typeof codeRow.user_id !== 'string') {
    return json({ error: 'invalid code' }, 404);
  }
  const referrerId = codeRow.user_id as string;
  if (referrerId === user.id) {
    return json({ error: 'self referral not allowed' }, 400);
  }

  // The caller can only ever have one referrer.
  const { data: existing } = await service
    .from('referrals')
    .select('id,referrer_id,status')
    .eq('referred_id', user.id)
    .maybeSingle();
  if (existing) {
    if (existing.referrer_id === referrerId) {
      // Idempotent replay of the same code: same result, no new row.
      return json(
        { ok: true, already: true, id: existing.id, status: existing.status },
        200,
      );
    }
    return json({ error: 'referrer already set' }, 409);
  }

  const now = new Date().toISOString();
  const { data: inserted, error: insertError } = await service
    .from('referrals')
    .insert({
      referrer_id: referrerId,
      referred_id: user.id,
      status: 'approved',
      decided_at: now,
      decided_by: 'system:auto-credit',
    })
    .select('id,status')
    .single();
  if (insertError || !inserted) {
    return json({ error: 'could not record referral' }, 500);
  }

  // IMMEDIATE CREDIT: read the owner-set reward and credit the referrer
  // in the same call. The UNIQUE idempotency_key makes this exactly-once.
  const { data: rewardCfg } = await service
    .from('app_config')
    .select('value')
    .eq('key', 'referral_reward_coins')
    .maybeSingle();
  const reward = Math.max(0, parseInt(String(rewardCfg?.value ?? '0'), 10) || 0);
  if (reward > 0) {
    const { error: ledgerError } = await service.from('ledger').insert({
      user_id: referrerId,
      amount_coins: reward,
      type: 'referral',
      ref_id: inserted.id,
      provider: 'tjearn',
      idempotency_key: `referral:${inserted.id}`,
    });
    if (ledgerError) {
      const msg = String(
        (ledgerError as { message?: unknown }).message ?? '',
      ).toLowerCase();
      const isReplay =
        (ledgerError as { code?: unknown }).code === '23505' ||
        msg.includes('duplicate');
      if (!isReplay) {
        // Credit failed but the referral row exists as approved; a retry
        // of apply-referral hits the idempotent path. Surface the error
        // honestly so the client can retry.
        await service.from('audit_logs').insert({
          actor: user.id,
          action: 'referral_credit_failed',
          target: inserted.id,
          details: { referrer_id: referrerId, reward },
        });
        return json({ error: 'could not credit reward' }, 500);
      }
    }
  }

  await service.from('audit_logs').insert({
    actor: user.id,
    action: 'referral_applied',
    target: inserted.id,
    details: { referrer_id: referrerId, reward_coins: reward, auto_credited: true },
  });
  await service.from('audit_logs').insert({
    actor: 'system:auto-credit',
    action: 'referral_approved',
    target: inserted.id,
    details: { reward_coins: reward },
  });
  return json(
    {
      ok: true,
      already: false,
      id: inserted.id,
      status: inserted.status,
      reward_coins: reward,
    },
    200,
  );
});
