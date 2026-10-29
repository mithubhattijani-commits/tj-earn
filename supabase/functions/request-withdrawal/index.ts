import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

const MIN_WITHDRAWAL_COINS = 20000;
const MAX_PENDING = 2;
const RAILS = ['jazzcash', 'easypaisa', 'bank'];

function maskAccount(account: string): string {
  const digits = account.replace(/\s/g, '');
  if (digits.length <= 4) return '****';
  return '****' + digits.slice(-4);
}

/// Creates a withdrawal request in `pending` status.
///
/// Re-validates everything server-side: minimum (20,000 coins), whole
/// rupees (multiple of 100 coins), sufficient balance, pending-request cap.
/// Only the masked account is stored (see README: full payout details are
/// a Stage 3 decision — MVP payouts are manual and the admin obtains the
/// full account from the user for the transfer).
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

  let body: {
    amount_coins?: unknown;
    rail?: unknown;
    account_number?: unknown;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'invalid json' }, 400);
  }
  const amountCoins = body.amount_coins;
  const rail = body.rail;
  const account = body.account_number;
  if (
    typeof amountCoins !== 'number' || !Number.isInteger(amountCoins) ||
    typeof rail !== 'string' || !RAILS.includes(rail) ||
    typeof account !== 'string' || account.replace(/\s/g, '').length < 10
  ) {
    return json({ error: 'invalid request' }, 400);
  }
  if (amountCoins < MIN_WITHDRAWAL_COINS) {
    return json({ error: 'below minimum' }, 400);
  }
  if (amountCoins % 100 !== 0) {
    return json({ error: 'must be whole rupees' }, 400);
  }

  const service = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );
  const { data: ledger } = await service
    .from('ledger')
    .select('amount_coins')
    .eq('user_id', user.id);
  const balance = (ledger ?? []).reduce(
    (sum: number, row: { amount_coins: number }) => sum + row.amount_coins,
    0,
  );
  if (amountCoins > balance) {
    return json({ error: 'insufficient balance' }, 400);
  }
  const { data: pending } = await service
    .from('withdrawals')
    .select('id')
    .eq('user_id', user.id)
    .in('status', ['pending', 'fraud_hold']);
  if ((pending ?? []).length >= MAX_PENDING) {
    return json({ error: 'too many pending requests' }, 400);
  }

  const { data: inserted, error: insertError } = await service
    .from('withdrawals')
    .insert({
      user_id: user.id,
      amount_coins: amountCoins,
      rail,
      account_masked: maskAccount(account),
      status: 'pending',
    })
    .select('id')
    .single();
  if (insertError || !inserted) {
    return json({ error: 'could not create request' }, 500);
  }
  await service.from('audit_logs').insert({
    actor: user.id,
    action: 'withdrawal_requested',
    target: inserted.id,
    details: { amount_coins: amountCoins, rail },
  });
  return json({ ok: true, id: inserted.id }, 200);
});
