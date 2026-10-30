import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

/// Referral milestone tier bonuses (Attapoll-style).
///
/// Beyond the flat 1000-coin per-referral reward, users earn tier bonuses:
///   5 approved referrals  -> bonus from `referral_milestone_5` (default 2000)
///   10 approved referrals -> bonus from `referral_milestone_10` (default 5000)
///   25 approved referrals -> bonus from `referral_milestone_25` (default 15000)
///
/// Called after a referral is approved (or on-demand from the app).
/// Each milestone is paid once per user (idempotent).
///
/// Anti-abuse:
/// - JWT auth (401 if invalid)
/// - Counts only APPROVED referrals (server-side)
/// - Idempotent via referral_milestones table + ledger idempotency_key
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

  // Config: milestone thresholds and bonuses
  const { data: cfgRows } = await supabase
    .from('app_config')
    .select('key, value')
    .in('key', [
      'referral_milestone_5',
      'referral_milestone_10',
      'referral_milestone_25',
    ]);
  const cfg: Record<string, string> = {};
  for (const r of cfgRows ?? []) cfg[r.key] = r.value;

  const tiers: Array<{ count: number; bonus: number }> = [
    { count: 5, bonus: parseInt(cfg['referral_milestone_5'] ?? '2000', 10) },
    { count: 10, bonus: parseInt(cfg['referral_milestone_10'] ?? '5000', 10) },
    { count: 25, bonus: parseInt(cfg['referral_milestone_25'] ?? '15000', 10) },
  ];

  // Count approved referrals where this user is the referrer
  const { data: referrals, error: refError } = await supabase
    .from('referrals')
    .select('id')
    .eq('referrer_id', user.id)
    .eq('status', 'approved');

  if (refError) return json({ error: 'db_error' }, 500);
  const approvedCount = (referrals ?? []).length;

  // Check which milestones are already paid
  const { data: paid } = await supabase
    .from('referral_milestones')
    .select('milestone')
    .eq('user_id', user.id);
  const paidSet = new Set((paid ?? []).map(r => r.milestone));

  let totalBonus = 0;
  const newlyPaid: number[] = [];

  for (const tier of tiers) {
    if (approvedCount >= tier.count && !paidSet.has(tier.count) && tier.bonus > 0) {
      // Mark as paid first (prevents double-pay on race)
      const { error: markError } = await supabase
        .from('referral_milestones')
        .insert({ user_id: user.id, milestone: tier.count });

      if (markError && (markError as { code?: string }).code !== '23505') {
        continue;
      }

      // Credit the bonus
      const idemKey = `referral_milestone:${user.id}:${tier.count}`;
      const { error: ledgerError } = await supabase
        .from('ledger')
        .insert({
          user_id: user.id,
          amount_coins: tier.bonus,
          type: 'referral_milestone',
          provider: 'tj_earn',
          ref_id: `referral_milestone:${tier.count}`,
          idempotency_key: idemKey,
        });

      if (!ledgerError || (ledgerError as { code?: string }).code === '23505') {
        totalBonus += tier.bonus;
        newlyPaid.push(tier.count);
      }
    }
  }

  // Next milestone info
  const nextTier = tiers.find(t => t.count > approvedCount);

  return json({
    ok: true,
    approved_referrals: approvedCount,
    bonus_coins: totalBonus,
    milestones_paid: newlyPaid,
    next_milestone: nextTier
      ? { count: nextTier.count, bonus: nextTier.bonus,
          remaining: nextTier.count - approvedCount }
      : null,
  }, 200);
});
