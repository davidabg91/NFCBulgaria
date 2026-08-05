-- =====================================================================
-- Билинг ъпгрейд: годишно плащане (×11), бизнес план (20+), триал
-- =====================================================================
-- Изпълни в Supabase → SQL Editor. Идемпотентно.
--
-- Какво добавя:
--   * team_subscriptions.interval  ('month' | 'year')
--   * team_subscriptions.trial_end (край на безплатния период)
--   * business_offers               — договорена оферта за фирма (20+):
--       места + месечна цена + триал. Цената НЕ идва от браузъра —
--       checkout функцията я чете оттук.
--   * get_my_business_offer()       — офертата за фирмата на текущия шеф
--   * admin_set_business_offer(...)  — админ задава/променя оферта
--
-- Годишната цена = месечна × 11 (една такса безплатна) се смята в
-- edge функцията create-checkout-session, не тук.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Нови колони по абонамента
-- ---------------------------------------------------------------------
alter table public.team_subscriptions
  add column if not exists interval  text not null default 'month'
    check (interval in ('month', 'year')),
  add column if not exists trial_end timestamptz;


-- ---------------------------------------------------------------------
-- 2. Бизнес оферти (договорени пакети за 20+ служители)
-- ---------------------------------------------------------------------
create table if not exists public.business_offers (
  company_id          uuid primary key,
  seats               int  not null check (seats > 0),
  monthly_price_cents int  not null check (monthly_price_cents >= 0),
  trial               boolean not null default true,   -- първи месец безплатно
  label               text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

alter table public.business_offers enable row level security;

-- Шефът може да ЧЕТЕ офертата само за своята фирма. Писане — само админ
-- (през RPC долу) или SQL Editor. Няма client INSERT/UPDATE policy.
drop policy if exists "read own company offer" on public.business_offers;
create policy "read own company offer"
  on public.business_offers
  for select
  using (
    exists (
      select 1 from public.profiles p
      where p.user_id = auth.uid()
        and p.company_id = business_offers.company_id
    )
  );


-- ---------------------------------------------------------------------
-- 3. Офертата за фирмата на текущия потребител
-- ---------------------------------------------------------------------
-- Ползва се и от dashboard.html (да покаже картата), и от edge функцията
-- create-checkout-session (да вземе цената сървърно).
create or replace function public.get_my_business_offer()
returns table (
  company_id          uuid,
  seats               int,
  monthly_price_cents int,
  trial               boolean,
  label               text
)
language sql
stable
security definer
set search_path = public
as $$
  select bo.company_id, bo.seats, bo.monthly_price_cents, bo.trial, bo.label
  from public.business_offers bo
  join public.profiles p on p.company_id = bo.company_id
  where p.user_id = auth.uid()
  limit 1;
$$;

revoke all on function public.get_my_business_offer() from public;
grant execute on function public.get_my_business_offer() to authenticated;


-- ---------------------------------------------------------------------
-- 4. Админ: задаване/промяна на бизнес оферта
-- ---------------------------------------------------------------------
create or replace function public.admin_set_business_offer(
  p_company_id          uuid,
  p_seats               int,
  p_monthly_price_cents int,
  p_trial               boolean default true,
  p_label               text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_app_admin() then
    return json_build_object('ok', false, 'message', 'Нямате администраторски права.');
  end if;

  if p_seats is null or p_seats <= 0 then
    return json_build_object('ok', false, 'message', 'Местата трябва да са положително число.');
  end if;

  insert into public.business_offers (company_id, seats, monthly_price_cents, trial, label)
  values (p_company_id, p_seats, p_monthly_price_cents, coalesce(p_trial, true), p_label)
  on conflict (company_id) do update set
    seats               = excluded.seats,
    monthly_price_cents = excluded.monthly_price_cents,
    trial               = excluded.trial,
    label               = excluded.label,
    updated_at          = now();

  return json_build_object('ok', true, 'message', 'Бизнес офертата е записана.');
end;
$$;

revoke all on function public.admin_set_business_offer(uuid, int, int, boolean, text) from public;
grant execute on function public.admin_set_business_offer(uuid, int, int, boolean, text) to authenticated;


-- ---------------------------------------------------------------------
-- 5. Има ли фирмата на текущия админ активен абонамент?
-- ---------------------------------------------------------------------
-- Ползва се от портала, за да покаже банер „активирайте плана", докато
-- някой от шефовете не плати. И двамата шефове връщат едно и също.
create or replace function public.company_subscription_active()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.team_subscriptions s
    join public.company_admins ca on ca.company_id = s.company_id
    where ca.user_id = auth.uid()
      and s.status = 'active'
      and s.current_period_end > now()
  );
$$;

revoke all on function public.company_subscription_active() from public;
grant execute on function public.company_subscription_active() to authenticated;
