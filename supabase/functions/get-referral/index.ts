import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

/// Returns the caller's referral code (auto-minted on first call),
/// share link, referral totals, and a privacy-conscious history.
///
/// Code: 8 chars from an unambiguous alphabet (no 0/O, 1/I/L), drawn
/// with crypto.getRandomValues; unique-violation retries on collision.
/// History never exposes emails — the other party is a masked id only.
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

  // Fetch the caller's code, minting one if this is the first call.
  let code: string | null = null;
  const { data: existing } = await service
    .from('referral_codes')
    .select('code')
    .eq('user_id', user.id)
    .maybeSingle();
  if (existing && typeof existing.code === 'string') {
    code = existing.code;
  } else {
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    for (let attempt = 0; attempt < 5 && !code; attempt++) {
      const bytes = new Uint8Array(8);
      crypto.getRandomValues(bytes);
      const candidate = Array.from(
        bytes,
        (b) => alphabet[b % alphabet.length],
      ).join('');
      const { error } = await service
        .from('referral_codes')
        .insert({ user_id: user.id, code: candidate });
      if (!error) {
        code = candidate;
        break;
      }
      // On any conflict (code collision OR a concurrent first call that
      // already created this user's row) re-read before retrying.
      const { data: reread } = await service
        .from('referral_codes')
        .select('code')
        .eq('user_id', user.id)
        .maybeSingle();
      if (reread && typeof reread.code === 'string') {
        code = reread.code;
        break;
      }
    }
  }
  if (!code) return json({ error: 'could not create code' }, 500);

  // Totals for referrals made BY this user.
  const { data: mine } = await service
    .from('referrals')
    .select('id,status')
    .eq('referrer_id', user.id);
  const rows = (mine ?? []) as Array<{ id: string; status: string }>;
  const total = rows.length;
  const pending = rows.filter(
    (r) => r.status === 'pending' || r.status === 'eligible',
  ).length;
  const approved = rows.filter((r) => r.status === 'approved').length;

  // Privacy-conscious history: masked counterpart id, status, dates.
  // No emails, no display names — nothing linkable leaves the server.
  const { data: hist } = await service
    .from('referrals')
    .select('id,status,created_at,decided_at,referred_id,referrer_id')
    .or(`referrer_id.eq.${user.id},referred_id.eq.${user.id}`)
    .order('created_at', { ascending: false })
    .limit(50);
  const history = ((hist ?? []) as Array<Record<string, unknown>>).map((r) => {
    const asReferrer = r['referrer_id'] === user.id;
    const other = String(asReferrer ? r['referred_id'] : r['referrer_id']);
    return {
      id: r['id'],
      role: asReferrer ? 'referrer' : 'referred',
      other_masked: maskId(other),
      status: r['status'],
      created_at: r['created_at'],
      decided_at: r['decided_at'],
    };
  });

  // TEAM LEVELS (Jaani, 2 Nov 2026): multi-level downline for "My Team".
  // L1 = direct referrals, L2 = their referrals, L3+ = deeper (grouped).
  // Single efficient walk: max 10 levels, grouped to avoid N+1.
  const team: { l1: number; l2: number; l3plus: number } = { l1: 0, l2: 0, l3plus: 0 };
  const teamCoins: { l1: number; l2: number; l3plus: number } = { l1: 0, l2: 0, l3plus: 0 };
  try {
    // L1: direct referrals
    const { data: l1rows } = await service
      .from('referrals')
      .select('referred_id')
      .eq('referrer_id', user.id)
      .eq('status', 'approved');
    const l1ids = ((l1rows ?? []) as Array<{ referred_id: string }>).map((r) => r.referred_id);
    team.l1 = l1ids.length;

    if (l1ids.length > 0) {
      // L2: referrals of L1 members (single query with IN)
      const { data: l2rows } = await service
        .from('referrals')
        .select('referred_id')
        .in('referrer_id', l1ids)
        .eq('status', 'approved');
      const l2ids = ((l2rows ?? []) as Array<{ referred_id: string }>).map((r) => r.referred_id);
      team.l2 = l2ids.length;

      // L3+: walk deeper, grouped (cap 8 more levels = 10 total)
      let currentIds = l2ids;
      for (let d = 0; d < 8 && currentIds.length > 0; d++) {
        const { data: deeper } = await service
          .from('referrals')
          .select('referred_id')
          .in('referrer_id', currentIds)
          .eq('status', 'approved');
        const nextIds = ((deeper ?? []) as Array<{ referred_id: string }>).map((r) => r.referred_id);
        team.l3plus += nextIds.length;
        currentIds = nextIds;
        if (nextIds.length === 0) break;
      }
    }

    // Coins earned per level from ledger (single query, grouped client-side)
    const { data: ledgerRows } = await service
      .from('ledger')
      .select('amount_coins,type')
      .eq('user_id', user.id)
      .in('type', ['referral', 'referral_l2', 'referral_l3plus']);
    for (const row of (ledgerRows ?? []) as Array<{ amount_coins: number; type: string }>) {
      const amt = Number(row.amount_coins) || 0;
      if (row.type === 'referral') teamCoins.l1 += amt;
      else if (row.type === 'referral_l2') teamCoins.l2 += amt;
      else if (row.type === 'referral_l3plus') teamCoins.l3plus += amt;
    }
  } catch {
    // Team data is supplementary — never fail the whole call.
  }

  // PENDING BONUSES (Jaani, 2 Nov 2026 — claim model): unclaimed bonuses
  // with masked from_user for the "X registered under you" notification.
  let pendingBonuses: Array<Record<string, unknown>> = [];
  let pendingTotal = 0;
  try {
    const { data: pb } = await service
      .from('pending_referral_bonuses')
      .select('id,coins,level,from_user_id,created_at')
      .eq('user_id', user.id)
      .eq('status', 'pending')
      .order('created_at', { ascending: false })
      .limit(50);
    pendingBonuses = ((pb ?? []) as Array<Record<string, unknown>>).map((b) => ({
      id: b['id'],
      coins: b['coins'],
      level: b['level'],
      from_masked: maskId(String(b['from_user_id'] ?? '')),
      created_at: b['created_at'],
    }));
    pendingTotal = pendingBonuses.reduce(
      (s, b) => s + (Number(b['coins']) || 0),
      0,
    );
  } catch {
    // Pending list is supplementary.
  }

  return json(
    {
      code,
      link: `https://nigraantv.xyz/earn/?ref=${code}`,
      total,
      pending,
      approved,
      history,
      team,
      team_coins: teamCoins,
      pending_bonuses: pendingBonuses,
      pending_total: pendingTotal,
    },
    200,
  );
});

/// Masks a UUID for display: first 4 + **** + last 4. UUIDs are random,
/// so the masked form cannot be linked back to a person.
function maskId(id: string): string {
  const s = String(id ?? '');
  if (s.length <= 8) return '****';
  return s.slice(0, 4) + '****' + s.slice(-4);
}
