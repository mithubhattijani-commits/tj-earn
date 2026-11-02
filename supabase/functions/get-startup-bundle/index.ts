import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

/// Bundled startup API (Jaani, 2 Nov 2026).
///
/// ONE call returns everything the app needs at startup: balance, streak,
/// onboarding progress, and the admin flag. This replaces 4 separate calls
/// (get-balance, streaks query, onboarding_tasks query, admin probe) that
/// fired on every login and piled up on slow/stalling connections,
/// hanging the app (ANR). All DB queries run in parallel server-side via
/// Promise.all — the app sees a single round trip.
///
/// Response:
/// {
///   "balance_coins": 10,
///   "streak": { "current_streak": 5, ... } | null,
///   "onboarding_completed": ["checkin", "quiz"],
///   "is_admin": false
/// }
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  const json = (body: unknown, status = 200) =>
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

  // All four data sources in parallel — one round trip from the app.
  const [ledgerRes, streakRes, onboardingRes, adminRes] = await Promise.all([
    service.from('ledger').select('amount_coins').eq('user_id', user.id),
    service.from('streaks').select().eq('user_id', user.id).maybeSingle(),
    service.from('onboarding_tasks').select('task_key').eq('user_id', user.id),
    service
      .from('app_config')
      .select('value')
      .eq('key', 'admin_emails')
      .maybeSingle(),
  ]);

  if (ledgerRes.error) return json({ error: 'balance query failed' }, 500);

  const balance_coins = (ledgerRes.data ?? []).reduce(
    (sum: number, row: { amount_coins: number }) =>
      sum + (Number(row.amount_coins) || 0),
    0,
  );

  const streak = streakRes.error ? null : (streakRes.data ?? null);

  const onboarding_completed = onboardingRes.error
    ? []
    : (onboardingRes.data ?? []).map(
        (r: { task_key: string }) => r.task_key,
      );

  // Admin gate: same logic as referral-stats — caller's JWT email must be
  // listed in app_config.admin_emails (case-insensitive). Fail closed.
  const adminEmails = parseAdminEmails(adminRes.data?.value);
  const callerEmail = (user.email ?? '').trim().toLowerCase();
  const is_admin =
    callerEmail.length > 0 && adminEmails.includes(callerEmail);

  return json({ balance_coins, streak, onboarding_completed, is_admin });
});

/// Parses the admin email allow-list (same as referral-stats): accepts a
/// postgres array literal ('{a@x.com,b@x.com}'), a JSON array, or a bare
/// comma-separated string. Unparseable -> empty list (deny).
function parseAdminEmails(raw: unknown): string[] {
  const s = String(raw ?? '').trim();
  if (!s || s === '{}' || s === '[]') return [];
  if (s.startsWith('[')) {
    try {
      const arr = JSON.parse(s) as unknown;
      return Array.isArray(arr)
        ? arr
            .map((x) => String(x).trim().toLowerCase())
            .filter((x) => x.length > 0)
        : [];
    } catch {
      return [];
    }
  }
  const inner = s.startsWith('{') && s.endsWith('}') ? s.slice(1, -1) : s;
  return inner
    .split(',')
    .map((x) => x.trim().toLowerCase().replace(/^"|"$/g, ''))
    .filter((x) => x.length > 0);
}
