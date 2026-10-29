import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

/// Admin-only, READ-ONLY ledger viewer.
///
/// Query params: `limit` (default 50, clamped max 200), `offset`
/// (default 0), optional `user_id` (uuid filter), optional `type`
/// (ledger type filter).
///
/// Returns `{ entries: [...], total: n }` where each entry is the ledger
/// columns (id, user_id, amount_coins, type, ref_id, provider,
/// idempotency_key, created_at) plus `user_email` (from auth.users via the
/// service_role client; null-safe when a user row is missing). Ordered
/// created_at DESC. No writes happen here, ever.
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

  const url = new URL(req.url);
  const limit = clampInt(url.searchParams.get('limit'), 50, 1, 200);
  const offset = clampInt(url.searchParams.get('offset'), 0, 0, 1000000);
  const userId = (url.searchParams.get('user_id') ?? '').trim();
  const type = (url.searchParams.get('type') ?? '').trim();

  let query = service
    .from('ledger')
    .select(
      'id,user_id,amount_coins,type,ref_id,provider,idempotency_key,created_at',
      { count: 'exact' },
    );
  if (userId) query = query.eq('user_id', userId);
  if (type) query = query.eq('type', type);
  const { data: rows, count, error } = await query
    .order('created_at', { ascending: false })
    .range(offset, offset + limit - 1);
  if (error) return json({ error: 'query failed' }, 500);

  const list = rows ?? [];
  const userIds = [...new Set(list.map((r) => r.user_id))];
  const emails = await lookupEmails(service, userIds);

  const entries = list.map((r) => ({
    ...r,
    user_email: emails.get(r.user_id) ?? null,
  }));

  return json({ entries, total: count ?? 0 }, 200);
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

/// Maps auth user ids -> email via the service_role client. Missing users
/// are skipped (null-safe: callers fall back to null).
async function lookupEmails(
  service: ReturnType<typeof createClient>,
  ids: string[],
): Promise<Map<string, string>> {
  const map = new Map<string, string>();
  for (const id of ids) {
    if (!id) continue;
    try {
      const { data, error } = await service.auth.admin.getUserById(id);
      if (!error && data?.user?.email) map.set(id, data.user.email);
    } catch {
      // ignore: email stays null
    }
  }
  return map;
}

/// Parses an integer query param with default + clamp. Unparseable ->
/// default.
function clampInt(
  raw: string | null,
  fallback: number,
  min: number,
  max: number,
): number {
  const n = parseInt(String(raw ?? ''), 10);
  if (!Number.isFinite(n)) return fallback;
  return Math.min(max, Math.max(min, n));
}
