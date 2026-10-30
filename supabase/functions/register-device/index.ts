import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

/// Device registration for anti-fraud.
///
/// The app sends a device hash (SHA-256 of Android ID + model) on login.
/// The server stores it and counts how many distinct users share this device.
/// If a device has >3 users, it's flagged for admin review.
///
/// This is a lightweight anti-fraud signal (not a hard block) — it helps
/// the admin spot multi-account farms without false-positive bans.
///
/// Anti-abuse:
/// - JWT auth (401 if invalid)
/// - Upsert (one row per user+device)
/// - Returns the device user count (for admin awareness)
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

  let body: { device_hash?: string; device_model?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'invalid_json' }, 400);
  }

  const deviceHash = (body.device_hash ?? '').trim();
  if (!deviceHash || deviceHash.length < 16) {
    return json({ error: 'invalid_device_hash' }, 400);
  }

  // Upsert device record
  const { error: upsertError } = await supabase
    .from('devices')
    .upsert({
      user_id: user.id,
      device_hash: deviceHash,
      device_model: (body.device_model ?? '').slice(0, 100),
      last_seen: new Date().toISOString(),
    }, { onConflict: 'user_id,device_hash' });

  if (upsertError) return json({ error: 'db_error' }, 500);

  // Count distinct users on this device (for admin signal)
  const { data: deviceUsers } = await supabase
    .from('devices')
    .select('user_id')
    .eq('device_hash', deviceHash);

  const userCount = new Set((deviceUsers ?? []).map(d => d.user_id)).size;

  return json({
    ok: true,
    device_users: userCount,
    // Flagged if >3 users share this device (admin review, not auto-ban)
    flagged: userCount > 3,
  }, 200);
});
