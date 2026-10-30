import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

/// Admin-only, READ-ONLY referral statistics. No params.
///
/// Returns `{ counts: {pending, eligible, approved, rejected},
/// total_referrers, total_coins_credited }` where total_coins_credited =
/// SUM(amount_coins) FROM ledger WHERE type='referral' AND amount_coins > 0
/// ('referral' is exactly the type the review-referral function writes when
/// it credits an approved referral).
///
/// Authorization: same fail-closed admin gate as review-referral — caller
/// must be authenticated and their JWT email listed in
/// app_config.admin_emails (case-insensitive); empty list -> 503
/// "admin not configured", non-listed email -> 403 "forbidden".
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  const json = (body: unknown, status: number) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  const admin = await authorizeAdmin(req);
  if (!admin.ok) return json({ error: admin.error }, admin.status);
  const service = admin.service;

  const counts: Record<string, number> = {
    pending: 0,
    eligible: 0,
    approved: 0,
    rejected: 0,
  };
  for (const status of Object.keys(counts)) {
    const { count, error } = await service
      .from('referrals')
      .select('id', { count: 'exact', head: true })
      .eq('status', status);
    if (error) return json({ error: 'query failed' }, 500);
    counts[status] = count ?? 0;
  }

  // Distinct referrers that have at least one referral row.
  const { data: referrerRows, error: refError } = await service
    .from('referrals')
    .select('referrer_id');
  if (refError) return json({ error: 'query failed' }, 500);
  const total_referrers = new Set(
    (referrerRows ?? []).map((r) => r.referrer_id).filter((x) => x),
  ).size;

  // Sum of positive referral credits from the append-only ledger.
  const { data: creditRows, error: ledgerError } = await service
    .from('ledger')
    .select('amount_coins')
    .eq('type', 'referral')
    .gt('amount_coins', 0);
  if (ledgerError) return json({ error: 'query failed' }, 500);
  const total_coins_credited = (creditRows ?? []).reduce(
    (sum, r) => sum + (Number(r.amount_coins) || 0),
    0,
  );

  return json({ counts, total_referrers, total_coins_credited }, 200);
});

/// Copies of the admin-gate helpers shared across the admin read
/// functions. Duplicated (not in _shared) so each function file stays
/// self-contained and deploys the same under the CLI and the dashboard.

async function authorizeAdmin(
  req: Request,
): Promise<
  | { ok: true; service: ReturnType<typeof createClient> }
  | { ok: false; error: string; status: number }
> {
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
  if (authError || !user) return { ok: false, error: 'unauthorized', status: 401 };

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
      ? { ok: false, error: 'admin not configured', status: 503 }
      : { ok: false, error: 'forbidden', status: 403 };
  }
  return { ok: true, service };
}

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
