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

  return json(
    {
      code,
      link: `https://nigraantv.xyz/earn/?ref=${code}`,
      total,
      pending,
      approved,
      history,
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
