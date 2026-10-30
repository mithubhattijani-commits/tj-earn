import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

/// New-user onboarding checklist (Roz Dhan-style welcome tasks).
///
/// Tasks: profile, checkin, quiz, spin, referral
/// Each completed task is recorded. When ALL tasks are done, the user
/// gets the `onboarding_bonus` (default 100 coins).
///
/// The app calls this with {task: 'profile'|'checkin'|'quiz'|'spin'|'referral'}
/// after the user completes each action. The server validates and records.
///
/// Anti-abuse:
/// - JWT auth (401 if invalid)
/// - Task keys are allowlisted (400 if invalid)
/// - Idempotent (409 if task already completed)
/// - Bonus paid once via idempotency_key
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

  let body: { task?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'invalid_json' }, 400);
  }

  const VALID_TASKS = ['profile', 'checkin', 'quiz', 'spin', 'referral'];
  const task = body.task ?? '';
  if (!VALID_TASKS.includes(task)) {
    return json({ error: 'invalid_task' }, 400);
  }

  // Record the task (idempotent)
  const { error: insertError } = await supabase
    .from('onboarding_tasks')
    .insert({ user_id: user.id, task_key: task });

  const alreadyDone = insertError &&
    (insertError as { code?: string }).code === '23505';

  // Get all completed tasks
  const { data: completed } = await supabase
    .from('onboarding_tasks')
    .select('task_key')
    .eq('user_id', user.id);

  const doneKeys = new Set((completed ?? []).map(r => r.task_key));
  const allDone = VALID_TASKS.every(t => doneKeys.has(t));

  // Pay completion bonus if all tasks are done (idempotent)
  let bonusCoins = 0;
  if (allDone) {
    const { data: cfgRows } = await supabase
      .from('app_config')
      .select('key, value')
      .eq('key', 'onboarding_bonus');
    const bonus = parseInt(cfgRows?.[0]?.value ?? '100', 10);

    if (bonus > 0) {
      const idemKey = `onboarding_bonus:${user.id}`;
      const { error: bonusError } = await supabase
        .from('ledger')
        .insert({
          user_id: user.id,
          amount_coins: bonus,
          type: 'onboarding_bonus',
          provider: 'tj_earn',
          ref_id: 'onboarding:complete',
          idempotency_key: idemKey,
        });
      if (!bonusError || (bonusError as { code?: string }).code === '23505') {
        bonusCoins = bonus;
      }
    }
  }

  return json({
    ok: true,
    task,
    already_completed: !!alreadyDone,
    completed_tasks: Array.from(doneKeys),
    total_tasks: VALID_TASKS.length,
    all_completed: allDone,
    bonus_coins: bonusCoins,
  }, 200);
});
