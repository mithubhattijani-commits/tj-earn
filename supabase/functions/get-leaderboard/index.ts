import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

/// Weekly leaderboard: top earners by coins earned in the last 7 days.
///
/// Returns the top 20 users (anonymized: first 3 chars of email + ***)
/// plus the caller's own rank. Drives competition and retention
/// (social proof mechanic).
///
/// Privacy: only shows masked identifiers, never full emails.
/// The caller's own entry is marked with `is_me: true`.
///
/// Anti-abuse:
/// - JWT auth (401 if invalid)
/// - Read-only (no writes)
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

  const weekAgo = new Date(Date.now() - 7 * 86400000).toISOString();

  // Sum positive ledger entries (earnings) per user in the last 7 days
  const { data: earnings, error } = await supabase
    .from('ledger')
    .select('user_id, amount_coins')
    .gte('created_at', weekAgo)
    .gt('amount_coins', 0);

  if (error) return json({ error: 'db_error' }, 500);

  // Aggregate by user
  const totals = new Map<string, number>();
  for (const e of earnings ?? []) {
    totals.set(e.user_id, (totals.get(e.user_id) ?? 0) + e.amount_coins);
  }

  // Sort and take top 20
  const sorted = Array.from(totals.entries())
    .sort((a, b) => b[1] - a[1])
    .slice(0, 20);

  // Get masked identifiers for top users
  // (We use the first 3 chars of the user_id hash for anonymity)
  const leaderboard = sorted.map(([uid, coins], idx) => ({
    rank: idx + 1,
    // Anonymous display: "User #XXXX" (last 4 of UUID)
    display: `User #${uid.slice(-4).toUpperCase()}`,
    coins,
    is_me: uid === user.id,
  }));

  // Caller's rank (if not in top 20)
  const myCoins = totals.get(user.id) ?? 0;
  const myRank = Array.from(totals.entries())
    .filter(([, c]) => c > myCoins).length + 1;

  return json({
    ok: true,
    leaderboard,
    my_rank: myRank,
    my_coins: myCoins,
    period: 'last_7_days',
  }, 200);
});
