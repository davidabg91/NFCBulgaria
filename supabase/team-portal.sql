-- =====================================================================
-- Фирмен Портал (HubSpot Lite) — абонаменти за екипи
-- =====================================================================
-- Изпълни този файл в Supabase → SQL Editor.
-- Безопасен е за повторно изпълнение (idempotent).
--
-- Модел:
--   * Всеки профил принадлежи на фирма (profiles.company_id).
--     company_id се задава от админ панела при създаване на клиента.
--   * Шеф с ПЛАТЕН и ВАЛИДЕН абонамент може да закачи към себе си
--     само профили от СЪЩАТА фирма — не произволен линк от сайта.
--   * Абонаментът се активира ЕДИНСТВЕНО от service_role (Stripe webhook
--     или админ). Клиентският ключ няма право да пише в него.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Фирма върху профилите
-- ---------------------------------------------------------------------
alter table public.profiles
  add column if not exists company_id uuid;

create index if not exists profiles_company_id_idx  on public.profiles (company_id);
create index if not exists profiles_parent_boss_idx on public.profiles (parent_boss_id);


-- ---------------------------------------------------------------------
-- 2. Абонаменти
-- ---------------------------------------------------------------------
create table if not exists public.team_subscriptions (
  id                  uuid primary key default gen_random_uuid(),
  company_id          uuid not null,
  boss_user_id        uuid not null references auth.users (id) on delete cascade,

  plan                text not null check (plan in ('team5', 'team10', 'team20')),
  seats               int  not null check (seats > 0),
  price_cents         int  not null,

  status              text not null default 'active'
                      check (status in ('active', 'canceled', 'expired')),
  current_period_end  timestamptz not null,

  stripe_customer_id     text,
  stripe_subscription_id text unique,
  stripe_session_id      text unique,

  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index if not exists team_subs_boss_idx    on public.team_subscriptions (boss_user_id);
create index if not exists team_subs_company_idx on public.team_subscriptions (company_id);

alter table public.team_subscriptions enable row level security;

-- Шефът вижда САМО своя абонамент. Никой клиентски ключ не може да пише.
drop policy if exists "boss reads own subscription" on public.team_subscriptions;
create policy "boss reads own subscription"
  on public.team_subscriptions
  for select
  using (boss_user_id = auth.uid());


-- ---------------------------------------------------------------------
-- 3. Пакетите — една дефиниция, ползвана и от webhook-а, и от UI-а
-- ---------------------------------------------------------------------
create or replace function public.team_plan_specs()
returns table (plan text, seats int, price_cents int)
language sql
immutable
as $$
  select * from (values
    ('team5',   5, 600),   -- 6 €
    ('team10', 10, 1000),  -- 10 €
    ('team20', 20, 1800)   -- 18 €
  ) as t(plan, seats, price_cents);
$$;


-- ---------------------------------------------------------------------
-- 4. Състояние на абонамента за текущия потребител
-- ---------------------------------------------------------------------
-- Връща един ред дори когато няма абонамент, за да може UI-ът винаги
-- да знае какво да покаже (празно състояние с пакетите).
create or replace function public.get_my_team_subscription()
returns table (
  has_subscription   boolean,
  is_active          boolean,
  plan               text,
  seats              int,
  seats_used         bigint,
  current_period_end timestamptz,
  company_id         uuid
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
  v_sub        public.team_subscriptions%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Няма активна сесия.';
  end if;

  select p.company_id into v_company_id
  from public.profiles p
  where p.user_id = auth.uid()
  limit 1;

  select * into v_sub
  from public.team_subscriptions s
  where s.boss_user_id = auth.uid()
  order by s.current_period_end desc
  limit 1;

  if v_sub.id is null then
    return query select false, false, null::text, 0, 0::bigint, null::timestamptz, v_company_id;
    return;
  end if;

  return query
  select
    true,
    (v_sub.status = 'active' and v_sub.current_period_end > now()),
    v_sub.plan,
    v_sub.seats,
    (select count(*) from public.profiles e where e.parent_boss_id = auth.uid()),
    v_sub.current_period_end,
    v_company_id;
end;
$$;

revoke all on function public.get_my_team_subscription() from public;
grant execute on function public.get_my_team_subscription() to authenticated;


-- ---------------------------------------------------------------------
-- 5. Закачане на служител към шефа
-- ---------------------------------------------------------------------
-- Приема слug-а на профила (това, което стои в profile.html?id=...).
-- Отказва, ако:
--   * няма валиден абонамент
--   * местата са изчерпани
--   * профилът е от друга фирма  ← това пази чужди данни
create or replace function public.claim_company_employee(employee_slug text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_boss_company uuid;
  v_sub          public.team_subscriptions%rowtype;
  v_emp          public.profiles%rowtype;
  v_seats_used   int;
begin
  if auth.uid() is null then
    return json_build_object('ok', false, 'code', 'no_session',
      'message', 'Няма активна сесия.');
  end if;

  select p.company_id into v_boss_company
  from public.profiles p
  where p.user_id = auth.uid()
  limit 1;

  select * into v_sub
  from public.team_subscriptions s
  where s.boss_user_id = auth.uid()
    and s.status = 'active'
    and s.current_period_end > now()
  order by s.current_period_end desc
  limit 1;

  if v_sub.id is null then
    return json_build_object('ok', false, 'code', 'no_subscription',
      'message', 'Нямате активен пакет. Изберете и заплатете пакет, за да добавяте служители.');
  end if;

  select count(*) into v_seats_used
  from public.profiles e
  where e.parent_boss_id = auth.uid();

  if v_seats_used >= v_sub.seats then
    return json_build_object('ok', false, 'code', 'no_seats',
      'message', format('Заетите места са %s от %s. Надградете пакета, за да добавите още.',
                        v_seats_used, v_sub.seats));
  end if;

  select * into v_emp
  from public.profiles p
  where lower(p.id) = lower(trim(employee_slug))
  limit 1;

  if v_emp.id is null then
    return json_build_object('ok', false, 'code', 'not_found',
      'message', 'Няма такъв профил. Проверете линка.');
  end if;

  if v_emp.user_id = auth.uid() then
    return json_build_object('ok', false, 'code', 'self',
      'message', 'Това е вашият собствен профил.');
  end if;

  if v_emp.parent_boss_id = auth.uid() then
    return json_build_object('ok', false, 'code', 'already_mine',
      'message', format('%s вече е в екипа ви.', v_emp.name));
  end if;

  if v_emp.parent_boss_id is not null then
    return json_build_object('ok', false, 'code', 'other_team',
      'message', 'Този профил вече е закачен към друг фирмен акаунт.');
  end if;

  -- Правилото: само карти, купени от същата фирма.
  if v_boss_company is null or v_emp.company_id is distinct from v_boss_company then
    return json_build_object('ok', false, 'code', 'other_company',
      'message', 'Този профил не е издаден на вашата фирма. Свържете се с нас, за да го добавим.');
  end if;

  update public.profiles
  set parent_boss_id = auth.uid()
  where id = v_emp.id;

  update public.profiles
  set is_boss = true
  where user_id = auth.uid() and is_boss is distinct from true;

  return json_build_object(
    'ok', true,
    'message', format('%s е добавен(а) в екипа ви.', v_emp.name),
    'employee_name', v_emp.name,
    'seats_used', v_seats_used + 1,
    'seats', v_sub.seats
  );
end;
$$;

revoke all on function public.claim_company_employee(text) from public;
grant execute on function public.claim_company_employee(text) to authenticated;


-- ---------------------------------------------------------------------
-- 6. Премахване на служител от екипа
-- ---------------------------------------------------------------------
create or replace function public.release_company_employee(employee_slug text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_emp public.profiles%rowtype;
begin
  if auth.uid() is null then
    return json_build_object('ok', false, 'message', 'Няма активна сесия.');
  end if;

  select * into v_emp
  from public.profiles p
  where lower(p.id) = lower(trim(employee_slug))
    and p.parent_boss_id = auth.uid()
  limit 1;

  if v_emp.id is null then
    return json_build_object('ok', false, 'message', 'Този служител не е във вашия екип.');
  end if;

  update public.profiles
  set parent_boss_id = null
  where id = v_emp.id;

  return json_build_object('ok', true,
    'message', format('%s е премахнат(а) от екипа.', v_emp.name));
end;
$$;

revoke all on function public.release_company_employee(text) from public;
grant execute on function public.release_company_employee(text) to authenticated;


-- ---------------------------------------------------------------------
-- 7. Ръчно активиране от админ (банков превод / поддръжка)
-- ---------------------------------------------------------------------
-- Извиква се САМО със service_role ключ — не от браузъра.
create or replace function public.admin_activate_subscription(
  p_boss_user_id uuid,
  p_plan         text,
  p_months       int default 1
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_spec       record;
  v_company_id uuid;
begin
  select * into v_spec from public.team_plan_specs() where plan = p_plan;
  if v_spec.plan is null then
    return json_build_object('ok', false, 'message', 'Непознат пакет: ' || p_plan);
  end if;

  select p.company_id into v_company_id
  from public.profiles p where p.user_id = p_boss_user_id limit 1;

  if v_company_id is null then
    return json_build_object('ok', false,
      'message', 'Профилът няма зададена фирма (company_id). Задайте я първо.');
  end if;

  insert into public.team_subscriptions
    (company_id, boss_user_id, plan, seats, price_cents, status, current_period_end)
  values
    (v_company_id, p_boss_user_id, v_spec.plan, v_spec.seats, v_spec.price_cents,
     'active', now() + (p_months || ' months')::interval);

  update public.profiles set is_boss = true where user_id = p_boss_user_id;

  return json_build_object('ok', true, 'message', 'Пакетът е активиран.');
end;
$$;

revoke all on function public.admin_activate_subscription(uuid, text, int) from public;
revoke all on function public.admin_activate_subscription(uuid, text, int) from authenticated;


-- ---------------------------------------------------------------------
-- 8. Кой е администратор на сайта
-- ---------------------------------------------------------------------
-- Проверката ползва имейла от токена — същият списък като ADMIN_EMAILS
-- в admin.html. Няма отделна таблица за поддръжка. За да добавиш/махнеш
-- админ, редактирай списъка тук И в admin.html, после пусни пак този блок.
create or replace function public.is_app_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    lower(auth.jwt() ->> 'email') in (
      'office@nfcbulgaria.com',
      'sjv_gold@abv.bg'
    ),
    false
  );
$$;

revoke all on function public.is_app_admin() from public;
grant execute on function public.is_app_admin() to authenticated;


-- Задава фирмата на профил. p_company_id = null → генерира нова фирма.
create or replace function public.admin_set_profile_company(
  p_target_id  text,
  p_company_id uuid default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company uuid;
  v_name    text;
begin
  if not public.is_app_admin() then
    return json_build_object('ok', false, 'message', 'Нямате администраторски права.');
  end if;

  select name into v_name from public.profiles where id = p_target_id;
  if v_name is null then
    return json_build_object('ok', false, 'message', 'Няма такъв профил.');
  end if;

  v_company := coalesce(p_company_id, gen_random_uuid());

  update public.profiles set company_id = v_company where id = p_target_id;

  return json_build_object('ok', true, 'company_id', v_company,
    'message', format('Фирмата на %s е записана.', v_name));
end;
$$;

revoke all on function public.admin_set_profile_company(text, uuid) from public;
grant execute on function public.admin_set_profile_company(text, uuid) to authenticated;


-- ---------------------------------------------------------------------
-- 9. Изтичане на абонаменти
-- ---------------------------------------------------------------------
-- Маркира изтеклите. Порталът и без това проверява current_period_end,
-- така че това е само за чистота на данните.
-- Пусни го по график: Supabase → Database → Cron (pg_cron), дневно.
create or replace function public.expire_team_subscriptions()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
begin
  with expired as (
    update public.team_subscriptions
    set status = 'expired', updated_at = now()
    where status = 'active' and current_period_end <= now()
    returning boss_user_id
  )
  select count(*) into v_count from expired;

  return v_count;
end;
$$;
