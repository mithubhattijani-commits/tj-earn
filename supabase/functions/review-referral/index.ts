import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

/// Admin review of a referral: approve (credits the referrer exactly once)
/// or reject (records the reason). Decided rows are final.
///
/// Authorization: the caller must be authenticated AND their JWT email
/// must be listed in app_config.admin_emails (case-insensitive). The owner
/// identifies the admin by EMAIL (Jaani, 29 Oct 2026) because the Supabase
/// auth UUID for the owner is not known. An empty/unset list, a missing
/// email claim, or a non-listed email denies everyone: empty list ->
/// "admin not configured" (503), non-admin -> "forbidden" (403).
/// NOTE: the owner must sign up on /earn/ or in the app with the listed
/// email before review-referral will authorize them.
///
/// Approval credits app_config.referral_reward_coins (owner-set '1000',
/// Rs 10 per approved referral) to the REFERRER through the append-only
/// ledger with idempotency_key 'referral:<referral_id>': a replayed
/// approval can never double-credit. A zero reward still records the
/// approval honestly — no ledger row is written and no coins move.
///
/// Every decision writes an audit_logs row.
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

  // Admin gate: compare the caller's JWT email claim (case-insensitive)
  // against app_config.admin_emails. Fail closed on every miss.
  const { data: adminCfg } = await service
    .from('app_config')
    .select('value')
    .eq('key', 'admin_emails')
    .maybeSingle();
  const adminEmails = parseAdminEmails(adminCfg?.value);
  const callerEmail = (user.email ?? '').trim().toLowerCase();
  if (!callerEmail || !adminEmails.includes(callerEmail)) {
    return adminEmails.length === 0
      ? json({ error: 'admin not configured' }, 503)
      : json({ error: 'forbidden' }, 403);
  }

  let body: { referral_id?: unknown; action?: unknown; reason?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'invalid json' }, 400);
  }
  const referralId =
    typeof body.referral_id === 'string' ? body.referral_id.trim() : '';
  const action = typeof body.action === 'string' ? body.action : '';
  const reason =
    typeof body.reason === 'string' ? body.reason.trim().slice(0, 500) : null;
  if (!referralId || (action !== 'approve' && action !== 'reject')) {
    return json({ error: 'invalid request' }, 400);
  }

  const { data: ref } = await service
    .from('referrals')
    .select('id,referrer_id,referred_id,status')
    .eq('id', referralId)
    .maybeSingle();
  if (!ref) return json({ error: 'not found' }, 404);
  if (ref.status !== 'pending' && ref.status !== 'eligible') {
    return json({ error: 'already decided' }, 409);
  }

  const decidedAt = new Date().toISOString();

  if (action === 'approve') {
    const { data: rewardCfg } = await service
      .from('app_config')
      .select('value')
      .eq('key', 'referral_reward_coins')
      .maybeSingle();
    const reward = Math.max(0, parseInt(String(rewardCfg?.value ?? '0'), 10) || 0);

    if (reward > 0) {
      // Credit first, then mark decided: if the credit fails we stay
      // pending and a retry is safe; the UNIQUE idempotency_key makes a
      // replayed approval a no-op credit-wise (exactly-once).
      const { error: ledgerError } = await service.from('ledger').insert({
        user_id: ref.referrer_id,
        amount_coins: reward,
        type: 'referral',
        ref_id: ref.id,
        provider: 'tjearn',
        idempotency_key: `referral:${ref.id}`,
      });
      if (ledgerError) {
        const msg = String(
          (ledgerError as { message?: unknown }).message ?? '',
        ).toLowerCase();
        const isReplay =
          (ledgerError as { code?: unknown }).code === '23505' ||
          msg.includes('duplicate');
        if (!isReplay) {
          return json({ error: 'could not credit reward' }, 500);
        }
      }
    }

    const { error: updateError } = await service
      .from('referrals')
      .update({
        status: 'approved',
        decided_at: decidedAt,
        decided_by: user.id,
        decision_reason: reason,
      })
      .eq('id', ref.id);
    if (updateError) return json({ error: 'could not record decision' }, 500);

    await service.from('audit_logs').insert({
      actor: user.id,
      action: 'referral_approved',
      target: ref.id,
      details: { reward_coins: reward, reason },
    });
    return json({ ok: true, status: 'approved', reward_coins: reward }, 200);
  }

  const { error: updateError } = await service
    .from('referrals')
    .update({
      status: 'rejected',
      decided_at: decidedAt,
      decided_by: user.id,
      decision_reason: reason,
    })
    .eq('id', ref.id);
  if (updateError) return json({ error: 'could not record decision' }, 500);

  await service.from('audit_logs').insert({
    actor: user.id,
    action: 'referral_rejected',
    target: ref.id,
    details: { reason },
  });
  return json({ ok: true, status: 'rejected' }, 200);
});

/// Parses the admin email allow-list stored in app_config.admin_emails.
/// Accepts a postgres array literal ('{a@x.com,b@x.com}'), a JSON array
/// ('["a@x.com"]'), or a bare comma-separated string. All entries are
/// lowercased for the case-insensitive comparison. Anything
/// unparseable -> empty list (deny).
function parseAdminEmails(raw: unknown): string[] {
  const s = String(raw ?? '').trim();
  if (!s || s === '{}' || s === '[]') return [];
  if (s.startsWith('[')) {
    try {
      const arr = JSON.parse(s) as unknown;
      return Array.isArray(arr)
        ? arr.map((x) => String(x).trim().toLowerCase()).filter((x) => x.length > 0)
        : [];
    } catch {
      return [];
    }
  }
  const inner = s.replace(/^\{/, '').replace(/\}$/, '');
  if (!inner.trim()) return [];
  return inner
    .split(',')
    .map((x) => x.trim().replace(/^"|"$/g, '').toLowerCase())
    .filter((x) => x.length > 0);
}
