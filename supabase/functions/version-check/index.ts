import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

/// Public: returns the latest published build for the in-app updater.
/// Deploy with --no-verify-jwt so the app can check before signing in.
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  const service = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );
  const { data, error } = await service
    .from('app_versions')
    .select('version_code, version_name, apk_url, notes, force_update')
    .order('version_code', { ascending: false })
    .limit(1)
    .single();
  if (error || !data) {
    return new Response(JSON.stringify({ error: 'no version published' }), {
      status: 404,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
  return new Response(JSON.stringify(data), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
});
