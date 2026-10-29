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
/// A successful apply creates a `pending` referral only. No coins move
/// here — payout happens exclusively through review-referral approval.
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

  const { data: inserted, error: insertError } = await service
    .from('referrals')
    .insert({
      referrer_id: referrerId,
      referred_id: user.id,
      status: 'pending',
    })
    .select('id,status')
    .single();
  if (insertError || !inserted) {
    return json({ error: 'could not record referral' }, 500);
  }
  await service.from('audit_logs').insert({
    actor: user.id,
    action: 'referral_applied',
    target: inserted.id,
    details: { referrer_id: referrerId },
  });
  return json(
    { ok: true, already: false, id: inserted.id, status: inserted.status },
    200,
  );
});
