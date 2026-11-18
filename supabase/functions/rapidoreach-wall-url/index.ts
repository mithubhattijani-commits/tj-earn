import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { createHash } from 'node:crypto';
import { corsHeaders } from '../_shared/cors.ts';

/// Play & Earn wall URL (RapidoReach, v1.0.25) — server-side UID signing.
///
/// The RapidoReach web wall needs a signed UID per user:
///   UID      = `<internalUserId>-<appId>-<checksum>`
///   checksum = MD5(`"<internalUserId>-<appId>-<appKey>"`)
///   wall     = `https://www.rapidoreach.com/ofw/?userId=<urlencoded UID>`
/// (docs.rapidoreach.com/docs/sdk/GenerateUserID, v2 — the single
/// authoritative UID definition for the web iframe.)
///
/// The App Key signs the UID, so it MUST stay on the server — the app
/// never sees it. This function (called by the app with the user's JWT)
/// builds the UID from the caller's Supabase UUID and returns the wall
/// URL. The app opens that URL in a WebView; completions credit through
/// the `rapidoreach-postback` Edge Function into the server ledger.
///
/// Hyphen-stripped user id: a Supabase UUID contains hyphens, and the
/// UID itself is hyphen-joined (`user-appId-checksum`) — a hyphenated
/// user id makes the UID ambiguous to parse. The 32-hex-char stripped
/// form keeps the UID to exactly two hyphens under any parsing scheme.
/// `rapidoreach-postback` re-hyphenates a 32-hex endUserId before the
/// user lookup, so the stripped form still credits the right user.
/// VERIFY with one live test completion (dashboard test user) before
/// promoting the Games section.
///
/// Auth: JWT verification ON (default) — only a signed-in user can ask
/// for their own wall URL. Deploy WITHOUT --no-verify-jwt.
///
/// Secrets (Supabase Edge Function secrets, never in code):
///   RAPIDOREACH_APP_ID  — TJ Earn app's App ID (dashboard Credentials
///     tab; NOT the SDK token)
///   RAPIDOREACH_APP_KEY — TJ Earn app's App Key (dashboard Credentials
///     tab; already set for rapidoreach-postback)
/// Until both are set the function answers 500 "not configured" and the
/// app shows its fail-soft "not available yet" state.
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  const json = (body: unknown, status: number) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  if (req.method !== 'GET') {
    return json({ error: 'method not allowed' }, 405);
  }

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
  if (authError || !user) {
    return json({ error: 'unauthorized' }, 401);
  }

  const appId = Deno.env.get('RAPIDOREACH_APP_ID') ?? '';
  const appKey = Deno.env.get('RAPIDOREACH_APP_KEY') ?? '';
  if (appId.length === 0 || appKey.length === 0) {
    console.error('rapidoreach-wall-url: secrets not configured');
    return json({ error: 'not configured' }, 500);
  }

  // Hyphen-stripped UUID (see header note): keeps the UID to exactly
  // two hyphens so RapidoReach can split user / appId / checksum.
  const internalUserId = user.id.replace(/-/g, '');
  const checksum = createHash('md5')
    .update(`${internalUserId}-${appId}-${appKey}`)
    .digest('hex')
    .toLowerCase();
  const uid = `${internalUserId}-${appId}-${checksum}`;
  const wallUrl =
    `https://www.rapidoreach.com/ofw/?userId=${encodeURIComponent(uid)}`;
  return json({ wall_url: wallUrl }, 200);
});
