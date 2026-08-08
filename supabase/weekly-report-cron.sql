-- =====================================================================
-- Седмичен график — задейства edge функцията `weekly-report`
-- =====================================================================
-- Пуска отчета всеки ПОНЕДЕЛНИК в 06:00 UTC (≈ 09:00 българско лятно време).
-- Ползва pg_cron (график) + pg_net (HTTP заявка).
--
-- ПРЕДИ да пуснеш това: активирай разширенията pg_cron и pg_net от
--   Supabase → Database → Extensions (търси "cron" и "http"/"pg_net").
-- Изпълни веднъж в Supabase → SQL Editor. Безопасно за повторно пускане.
-- =====================================================================

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- (Пре)създава задачата. Ако вече съществува със същото име, се обновява.
select cron.schedule(
  'weekly-report',
  '0 6 * * 1',   -- мин час ден месец ден-от-седмицата (1 = понеделник)
  $$
  select net.http_post(
    url     := 'https://upjwsqfrblxzhyuxeumj.supabase.co/functions/v1/weekly-report?key=f1f73f094699e1c2be66270fbf792856',
    headers := jsonb_build_object('Content-Type', 'application/json'),
    body    := '{}'::jsonb
  );
  $$
);

-- Проверка кои задачи са планирани:
--   select jobname, schedule, active from cron.job;
-- Ръчно спиране при нужда:
--   select cron.unschedule('weekly-report');
