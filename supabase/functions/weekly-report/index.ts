// =====================================================================
// Седмичен имейл-отчет за визитните профили.
//
// Веднъж седмично (задейства се от pg_cron — виж supabase/weekly-report-cron.sql)
// смята за всеки профил сканиранията и новите контакти за последните 7 дни
// (през RPC get_weekly_stats) и праща имейл на собственика чрез прост Make.com
// webhook (webhook → Email — същия тип сценарий като лийд-известието).
//
// Защита: изисква ?key=<CRON_SECRET>, за да не може да се задейства публично.
//
// Deploy:
//   supabase functions deploy weekly-report --no-verify-jwt
//
// Secrets (задават се веднъж):
//   supabase secrets set CRON_SECRET=<таен низ>
//   supabase secrets set REPORT_WEBHOOK_URL=<Make.com webhook URL за отчета>
// (SUPABASE_URL и SERVICE_KEY вече са налични на проекта.)
// =====================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
// Авто-вкараният SERVICE_ROLE_KEY е счупен на този проект (нови ключове) —
// ползваме секрета SERVICE_KEY, с fallback за всеки случай.
const SERVICE_KEY = Deno.env.get('SERVICE_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const REPORT_WEBHOOK_URL = Deno.env.get('REPORT_WEBHOOK_URL') ?? '';
const CRON_SECRET = Deno.env.get('CRON_SECRET') ?? '';

const supabase = createClient(SUPABASE_URL, SERVICE_KEY);

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });

Deno.serve(async (req) => {
  // Защита срещу публично задействане
  const url = new URL(req.url);
  if (CRON_SECRET && url.searchParams.get('key') !== CRON_SECRET) {
    return json({ ok: false, error: 'unauthorized' }, 401);
  }

  // Агрегирани числа за последните 7 дни (една заявка)
  const { data, error } = await supabase.rpc('get_weekly_stats');
  if (error) {
    return json({ ok: false, error: error.message }, 500);
  }

  const rows = (data ?? []) as Array<{
    profile_id: string; name: string; email: string; scans: number; leads: number;
  }>;

  let sent = 0;
  let skipped = 0;

  if (!REPORT_WEBHOOK_URL) {
    // Няма зададен webhook — връщаме само какво БИ пратило (за тест)
    return json({ ok: true, note: 'REPORT_WEBHOOK_URL не е зададен', profiles: rows.length, preview: rows });
  }

  for (const row of rows) {
    const scans = Number(row.scans) || 0;
    const leads = Number(row.leads) || 0;

    // Не пращаме имейл на хора без активност за седмицата
    if (scans === 0 && leads === 0) { skipped++; continue; }
    if (!row.email) { skipped++; continue; }

    const params = new URLSearchParams({
      owner_email: row.email,
      name: row.name ?? '',
      scans: String(scans),
      leads: String(leads),
    });

    try {
      await fetch(`${REPORT_WEBHOOK_URL}?${params.toString()}`);
      sent++;
    } catch (e) {
      console.error('Report send failed for', row.email, e);
    }
  }

  return json({ ok: true, profiles: rows.length, sent, skipped });
});
