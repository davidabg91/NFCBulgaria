-- =====================================================================
-- Заключване на фирмения портал зад активен абонамент (сървърно)
-- =====================================================================
-- Дотук get_company_team_summary / get_company_employee_leads връщаха данни
-- само при членство в company_admins. Сега добавяме и изискване за
-- АКТИВЕН абонамент — за да не се вижда статистиката без плащане (важи и
-- ако някой извика RPC-то директно, не само през UI-а).
--
-- При триал абонаментът е 'active' (current_period_end = край на триала) →
-- отключено. Изтече ли без плащане → заключено.
--
-- Изпълни в Supabase → SQL Editor. Идемпотентно.
-- =====================================================================


-- Помощна: има ли фирмата активен абонамент
create or replace function public.company_has_active_sub(p_company uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.team_subscriptions s
    where s.company_id = p_company
      and s.status = 'active'
      and s.current_period_end > now()
  );
$$;

revoke all on function public.company_has_active_sub(uuid) from public;
grant execute on function public.company_has_active_sub(uuid) to authenticated;


-- Обобщение на екипа — само при активен абонамент
create or replace function public.get_company_team_summary()
returns table (
  employee_id     text,
  employee_name   text,
  employee_title  text,
  employee_avatar text,
  scans_count     bigint,
  employee_saves  bigint,
  leads_count     bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_company uuid;
begin
  select public.my_company_admin_id() into v_company;
  if v_company is null then
    return;
  end if;

  -- Заключено без активен абонамент.
  if not public.company_has_active_sub(v_company) then
    return;
  end if;

  return query
  select
    p.id,
    p.name,
    p.title,
    p.avatar_url,
    (select count(*) from public.analytics a where a.profile_id = p.id),
    coalesce(p.saves_count, 0)::bigint,
    (select count(*) from public.leads l where l.profile_id = p.id)
  from public.profiles p
  where p.company_id = v_company
  order by p.name;
end;
$$;

revoke all on function public.get_company_team_summary() from public;
grant execute on function public.get_company_team_summary() to authenticated;


-- Лийдовете на служител — само при активен абонамент
create or replace function public.get_company_employee_leads(target_employee_id text)
returns table (
  created_at   timestamptz,
  client_name  text,
  client_phone text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_company uuid;
begin
  select public.my_company_admin_id() into v_company;
  if v_company is null then
    return;
  end if;

  if not public.company_has_active_sub(v_company) then
    return;
  end if;

  return query
  select l.created_at, l.client_name, l.client_phone
  from public.leads l
  join public.profiles p on p.id = l.profile_id
  where l.profile_id = target_employee_id
    and p.company_id = v_company
  order by l.created_at desc;
end;
$$;

revoke all on function public.get_company_employee_leads(text) from public;
grant execute on function public.get_company_employee_leads(text) to authenticated;
