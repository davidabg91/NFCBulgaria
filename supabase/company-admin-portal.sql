-- =====================================================================
-- Фирмени админи — двама шефове виждат ВСИЧКИ визитки на фирмата
-- =====================================================================
-- По-чист модел от parent_boss_id: достъпът се решава по company_id +
-- членство в public.company_admins. Няколко шефа могат да виждат целия
-- екип едновременно, без Stripe пакет и без ограничение за места.
--
-- ПУСНИ СЛЕД elkabel-accounts.sql (шефовете трябва да имат user_id).
-- Изпълни в Supabase → SQL Editor. Идемпотентно.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Кой е фирмен админ (сигурна таблица — клиентът НЕ може да пише в нея)
-- ---------------------------------------------------------------------
create table if not exists public.company_admins (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  company_id uuid not null,
  created_at timestamptz not null default now()
);

alter table public.company_admins enable row level security;

-- Само четене на собствения ред. Няма INSERT/UPDATE/DELETE policy →
-- клиентският ключ не може да си вдигне права. Пише се само от SQL Editor.
drop policy if exists "read own admin row" on public.company_admins;
create policy "read own admin row"
  on public.company_admins
  for select
  using (user_id = auth.uid());


-- ---------------------------------------------------------------------
-- 2. company_id на текущия потребител, само ако е фирмен админ
-- ---------------------------------------------------------------------
create or replace function public.my_company_admin_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select ca.company_id
  from public.company_admins ca
  where ca.user_id = auth.uid()
  limit 1;
$$;

revoke all on function public.my_company_admin_id() from public;
grant execute on function public.my_company_admin_id() to authenticated;


-- ---------------------------------------------------------------------
-- 3. Обобщение на целия екип (за таблицата в портала)
-- ---------------------------------------------------------------------
-- Връща по един ред за всяка визитка от фирмата на извикващия админ,
-- със сканирания / записвания / брой лийдове. Ако извикващият не е
-- фирмен админ → връща нищо (нула редове).
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


-- ---------------------------------------------------------------------
-- 4. Лийдовете на конкретен служител (в рамките на фирмата)
-- ---------------------------------------------------------------------
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


-- ---------------------------------------------------------------------
-- 5. Вкарваме двамата шефове на ЕЛКАБЕЛ като фирмени админи
-- ---------------------------------------------------------------------
-- Взимаме company_id и user_id направо от техните профили.
insert into public.company_admins (user_id, company_id)
select p.user_id, p.company_id
from public.profiles p
where p.id in ('vasil-bozhinov', 'lyubomir-novakov')
  and p.user_id is not null
  and p.company_id is not null
on conflict (user_id) do update set company_id = excluded.company_id;
