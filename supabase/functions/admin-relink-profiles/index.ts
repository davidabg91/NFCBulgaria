// Изравнява profiles.user_id с реалния auth акаунт по имейл.
// Лекува профили, закачени за грешен вътрешен user_id (заради разминаване
// при създаване в админа).
//
// Изисква таен ключ с права за писане, зададен като SERVICE_KEY:
//   supabase secrets set SERVICE_KEY=sb_secret_...
// (авто-вкараният SUPABASE_SERVICE_ROLE_KEY на този проект е без права).
//
// Пуска се веднъж, после се трие.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

Deno.serve(async () => {
  const writeKey = Deno.env.get('SERVICE_KEY');
  if (!writeKey) {
    return new Response(
      JSON.stringify({ error: 'Липсва SERVICE_KEY (таен ключ с права за писане).' }),
      { status: 400, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const url = Deno.env.get('SUPABASE_URL')!;
  const admin = createClient(url, writeKey);        // за писане
  const authAdmin = createClient(url, writeKey);    // за listUsers

  const emailToUid = new Map<string, string[]>();
  let page = 1;
  while (page <= 50) {
    const { data, error } = await authAdmin.auth.admin.listUsers({ page, perPage: 200 });
    if (error) return new Response(JSON.stringify({ error: error.message }), { status: 500 });
    if (!data.users.length) break;
    for (const u of data.users) {
      const em = (u.email ?? '').toLowerCase().trim();
      if (!em) continue;
      (emailToUid.get(em) ?? emailToUid.set(em, []).get(em)!).push(u.id);
    }
    page++;
  }

  const { data: profiles, error: pErr } = await admin
    .from('profiles').select('id, email, user_id');
  if (pErr) return new Response(JSON.stringify({ error: pErr.message }), { status: 500 });

  const changed: unknown[] = [];
  const skipped: unknown[] = [];
  for (const p of profiles ?? []) {
    const em = (p.email ?? '').toLowerCase().trim();
    if (!em) { skipped.push({ id: p.id, reason: 'няма имейл' }); continue; }
    const uids = emailToUid.get(em);
    if (!uids?.length) { skipped.push({ id: p.id, email: em, reason: 'няма auth акаунт' }); continue; }
    if (uids.length > 1) { skipped.push({ id: p.id, email: em, reason: 'няколко акаунта' }); continue; }
    if (p.user_id === uids[0]) { skipped.push({ id: p.id, reason: 'вече коректен' }); continue; }
    const { error } = await admin.from('profiles').update({ user_id: uids[0] }).eq('id', p.id);
    changed.push({ id: p.id, email: em, from: p.user_id, to: uids[0], error: error?.message ?? null });
  }

  return new Response(JSON.stringify({ ok: true, changed, skipped }, null, 2), {
    headers: { 'Content-Type': 'application/json' },
  });
});
