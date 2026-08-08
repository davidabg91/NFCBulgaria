-- =====================================================================
-- Седмичен отчет — агрегираща функция
-- =====================================================================
-- Връща за всеки профил (с имейл) броя сканирания и нови контакти за
-- последните 7 дни. Ползва се от edge функцията `weekly-report`.
--
-- SECURITY DEFINER: минава над RLS, но връща само агрегирани числа + име и
-- имейл на собственика (не сурови данни). Правата за изпълнение са само за
-- service_role (edge функцията).
--
-- Изпълни веднъж в Supabase → SQL Editor. Безопасно за повторно пускане.
-- =====================================================================

create or replace function public.get_weekly_stats()
returns table (
  profile_id text,
  name       text,
  email      text,
  scans      bigint,
  leads      bigint
)
language sql
security definer
set search_path = public
as $$
  select
    p.id,
    p.name,
    p.email,
    coalesce((
      select count(*) from analytics a
      where a.profile_id = p.id
        and a.scanned_at >= now() - interval '7 days'
    ), 0) as scans,
    coalesce((
      select count(*) from leads l
      where l.profile_id = p.id
        and l.created_at >= now() - interval '7 days'
    ), 0) as leads
  from profiles p
  where p.email is not null and p.email <> '';
$$;

revoke all on function public.get_weekly_stats() from public;
grant execute on function public.get_weekly_stats() to service_role;
