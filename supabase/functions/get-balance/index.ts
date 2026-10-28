import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

/// Returns the caller's coin balance: SUM(ledger.amount_coins).
/// The app never computes or stores a balance itself.
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
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
    return new Response(JSON.stringify({ error: 'unauthorized' }), {
      status: 401,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
  const { data, error } = await supabase
    .from('ledger')
    .select('amount_coins')
    .eq('user_id', user.id);
  if (error) {
    return new Response(JSON.stringify({ error: 'query failed' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
  const balance = (data ?? []).reduce(
    (sum: number, row: { amount_coins: number }) => sum + row.amount_coins,
    0,
  );
  return new Response(JSON.stringify({ balance_coins: balance }), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
});
