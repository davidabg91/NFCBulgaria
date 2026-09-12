-- =====================================================================
-- Админ справки — всичко, което админ панелът показва
-- =====================================================================
-- Изпълни в Supabase → SQL Editor. Идемпотентно (безопасно за повторно
-- пускане). НЕ пипа съществуващи функции — само добавя нови.
--
-- ИЗИСКВА ПРЕДИ СЕБЕ СИ: team-portal.sql (за is_app_admin())
--                        billing-plans-upgrade.sql (business_offers, interval)
--
-- Какво добавя:
--   1. profiles.updated_at + тригер  → кога визитката е пипана последно
--   2. admin_activity_log            → КОЙ какво е променил (одит)
--   3. checkout_intents              → КОЙ е натиснал бутона за плащане
--   4. admin_* справки (security definer, само за is_app_admin())
--
-- Всички справки минават през is_app_admin() — същите имейли, които са
-- в ADMIN_EMAILS в admin.html. Ако добавиш админ, добави го и в
-- team-portal.sql → is_app_admin(), и пусни пак този файл не е нужно.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Кога профилът е променян последно
-- ---------------------------------------------------------------------
alter table public.profiles
  add column if not exists updated_at timestamptz;

create or replace function public.touch_profile_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists profiles_touch_updated_at on public.profiles;
create trigger profiles_touch_updated_at
  before update on public.profiles
  for each row execute function public.touch_profile_updated_at();


-- ---------------------------------------------------------------------
-- 2. Одит — кой какво е променил по визитките
-- ---------------------------------------------------------------------
create table if not exists public.admin_activity_log (
  id            bigserial primary key,
  created_at    timestamptz not null default now(),
  actor_user_id uuid,
  actor_email   text,
  profile_id    text,
  profile_name  text,
  action        text not null,          -- 'update' | 'insert' | 'delete'
  changed       text[],                 -- имената на променените колони
  details       jsonb
);

create index if not exists admin_activity_created_idx
  on public.admin_activity_log (created_at desc);
create index if not exists admin_activity_profile_idx
  on public.admin_activity_log (profile_id);

alter table public.admin_activity_log enable row level security;
-- Няма нито една policy → клиентският ключ не вижда и не пише нищо.
-- Четенето става само през admin_activity_feed() (security definer).


-- Тригерът НИКОГА не бива да чупи запис на профил — при всяка грешка
-- просто пропуска логването.
create or replace function public.log_profile_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_changed text[] := '{}';
  v_email   text;
  v_col     text;
  v_old     jsonb;
  v_new     jsonb;
begin
  begin
    v_email := nullif(auth.jwt() ->> 'email', '');
    if v_email is null and auth.uid() is not null then
      select u.email into v_email from auth.users u where u.id = auth.uid();
    end if;

    if tg_op = 'UPDATE' then
      v_old := to_jsonb(old);
      v_new := to_jsonb(new);
      for v_col in select jsonb_object_keys(v_new) loop
        if v_col <> 'updated_at'
           and (v_old -> v_col) is distinct from (v_new -> v_col) then
          v_changed := array_append(v_changed, v_col);
        end if;
      end loop;

      if array_length(v_changed, 1) is null then
        return new;  -- нищо смислено не се е променило
      end if;

      insert into public.admin_activity_log
        (actor_user_id, actor_email, profile_id, profile_name, action, changed)
      values (auth.uid(), v_email, new.id, new.name, 'update', v_changed);

    elsif tg_op = 'INSERT' then
      insert into public.admin_activity_log
        (actor_user_id, actor_email, profile_id, profile_name, action)
      values (auth.uid(), v_email, new.id, new.name, 'insert');

    elsif tg_op = 'DELETE' then
      insert into public.admin_activity_log
        (actor_user_id, actor_email, profile_id, profile_name, action)
      values (auth.uid(), v_email, old.id, old.name, 'delete');
      return old;
    end if;
  exception when others then
    null;  -- логът е второстепенен, записът на профила е важният
  end;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists profiles_activity_log on public.profiles;
create trigger profiles_activity_log
  after insert or update or delete on public.profiles
  for each row execute function public.log_profile_change();


-- ---------------------------------------------------------------------
-- 3. Кой е натиснал бутона за плащане
-- ---------------------------------------------------------------------
-- Пише се от dashboard.html точно преди пренасочването към Stripe.
-- Така се вижда и кой е стигнал до плащане, но НЕ е платил.
create table if not exists public.checkout_intents (
  id          bigserial primary key,
  created_at  timestamptz not null default now(),
  user_id     uuid,
  user_email  text,
  profile_id  text,
  profile_name text,
  company_id  uuid,
  plan        text,
  interval    text,
  outcome     text not null default 'clicked'   -- 'clicked' | 'redirected' | 'failed'
);

create index if not exists checkout_intents_created_idx
  on public.checkout_intents (created_at desc);

alter table public.checkout_intents enable row level security;
-- Пак без policy — пише се само през RPC-то долу, чете се само от админ.

create or replace function public.log_checkout_intent(
  p_plan     text,
  p_interval text default 'month',
  p_outcome  text default 'clicked'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_p public.profiles%rowtype;
  v_email text;
begin
  if auth.uid() is null then
    return;
  end if;

  select * into v_p from public.profiles p where p.user_id = auth.uid() limit 1;
  v_email := nullif(auth.jwt() ->> 'email', '');
  if v_email is null then
    select u.email into v_email from auth.users u where u.id = auth.uid();
  end if;

  insert into public.checkout_intents
    (user_id, user_email, profile_id, profile_name, company_id, plan, interval, outcome)
  values
    (auth.uid(), v_email, v_p.id, v_p.name, v_p.company_id,
     p_plan, coalesce(p_interval, 'month'), coalesce(p_outcome, 'clicked'));
exception when others then
  null;  -- плащането никога не бива да се чупи заради лога
end;
$$;

revoke all on function public.log_checkout_intent(text, text, text) from public;
grant execute on function public.log_checkout_intent(text, text, text) to authenticated;


-- =====================================================================
-- СПРАВКИ ЗА АДМИН ПАНЕЛА
-- =====================================================================

-- ---------------------------------------------------------------------
-- 4.1 Обобщени числа за началния екран
-- ---------------------------------------------------------------------
create or replace function public.admin_dashboard_stats()
returns json
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v json;
begin
  if not public.is_app_admin() then
    return json_build_object('ok', false, 'message', 'Нямате администраторски права.');
  end if;

  select json_build_object(
    'ok', true,
    'profiles_total',   (select count(*) from public.profiles),
    'profiles_active',  (select count(*) from public.profiles p
                          where exists (select 1 from public.analytics a
                                        where a.profile_id = p.id)),
    'bosses',           (select count(*) from public.profiles where is_boss),
    'companies',        (select count(distinct company_id) from public.profiles
                          where company_id is not null),
    'orphans',          (select count(*) from public.profiles where company_id is null),

    'scans_total',      (select count(*) from public.analytics),
    'scans_7d',         (select count(*) from public.analytics
                          where scanned_at > now() - interval '7 days'),
    'scans_30d',        (select count(*) from public.analytics
                          where scanned_at > now() - interval '30 days'),

    'leads_total',      (select count(*) from public.leads),
    'leads_7d',         (select count(*) from public.leads
                          where created_at > now() - interval '7 days'),
    'leads_30d',        (select count(*) from public.leads
                          where created_at > now() - interval '30 days'),

    'saves_total',      (select coalesce(sum(coalesce(saves_count, 0)), 0) from public.profiles),

    'subs_active',      (select count(*) from public.team_subscriptions
                          where status = 'active' and current_period_end > now()),
    -- "interval" е ключова дума в Postgres → винаги квалифицирана с алиас
    'mrr_cents',        (select coalesce(sum(case when t.interval = 'year'
                                                  then t.price_cents / 12
                                                  else t.price_cents end), 0)
                          from public.team_subscriptions t
                          where t.status = 'active' and t.current_period_end > now()),
    'offers_total',     (select count(*) from public.business_offers),

    'edits_7d',         (select count(*) from public.admin_activity_log
                          where created_at > now() - interval '7 days'
                            and action = 'update'),
    'pay_clicks_30d',   (select count(*) from public.checkout_intents
                          where created_at > now() - interval '30 days')
  ) into v;

  return v;
end;
$$;

revoke all on function public.admin_dashboard_stats() from public;
grant execute on function public.admin_dashboard_stats() to authenticated;


-- ---------------------------------------------------------------------
-- 4.2 Всички визитки с употребата им — сърцето на панела
-- ---------------------------------------------------------------------
create or replace function public.admin_profiles_overview()
returns table (
  profile_id     text,
  name           text,
  title          text,
  company        text,
  company_id     uuid,
  is_boss        boolean,
  boss_name      text,
  boss_profile   text,
  login_email    text,
  card_email     text,
  phone          text,
  avatar_url     text,
  scans          bigint,
  scans_30d      bigint,
  leads          bigint,
  leads_30d      bigint,
  saves          bigint,
  last_scan      timestamptz,
  last_lead      timestamptz,
  last_login     timestamptz,
  last_edit      timestamptz,
  created_at     timestamptz,
  has_account    boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_app_admin() then
    return;
  end if;

  return query
  select
    p.id,
    p.name,
    p.title,
    p.company,
    p.company_id,
    coalesce(p.is_boss, false),
    b.name,
    b.id,
    u.email::text,          -- auth.users.email е varchar, OUT-ът е text
    p.email,
    p.phone,
    p.avatar_url,
    coalesce(a.cnt, 0),
    coalesce(a.cnt30, 0),
    coalesce(l.cnt, 0),
    coalesce(l.cnt30, 0),
    coalesce(p.saves_count, 0)::bigint,
    a.last_at,
    l.last_at,
    u.last_sign_in_at,
    p.updated_at,
    p.created_at,
    (p.user_id is not null)
  from public.profiles p
  left join public.profiles b on b.user_id = p.parent_boss_id
  left join auth.users u      on u.id = p.user_id
  left join lateral (
    select count(*) as cnt,
           count(*) filter (where x.scanned_at > now() - interval '30 days') as cnt30,
           max(x.scanned_at) as last_at
    from public.analytics x where x.profile_id = p.id
  ) a on true
  left join lateral (
    select count(*) as cnt,
           count(*) filter (where y.created_at > now() - interval '30 days') as cnt30,
           max(y.created_at) as last_at
    from public.leads y where y.profile_id = p.id
  ) l on true
  order by coalesce(a.cnt, 0) desc, p.name;
end;
$$;

revoke all on function public.admin_profiles_overview() from public;
grant execute on function public.admin_profiles_overview() to authenticated;


-- ---------------------------------------------------------------------
-- 4.3 Фирмите — кой е шефът, колко души, какво плащат
-- ---------------------------------------------------------------------
create or replace function public.admin_companies_overview()
returns table (
  company_id      uuid,
  company_name    text,
  members         bigint,
  bosses          text,
  boss_profiles   text,
  scans           bigint,
  leads           bigint,
  saves           bigint,
  sub_plan        text,
  sub_status      text,
  sub_seats       int,
  sub_interval    text,
  sub_price_cents int,
  sub_period_end  timestamptz,
  offer_seats     int,
  offer_price_cents int,
  offer_label     text,
  pay_clicks      bigint,
  last_pay_click  timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_app_admin() then
    return;
  end if;

  return query
  with comp as (
    select
      p.company_id as cid,
      coalesce(
        max(p.company) filter (where p.is_boss),
        max(p.company),
        'Без име'
      ) as cname,
      count(*) as members,
      string_agg(p.name, ', ' order by p.name) filter (where p.is_boss) as bosses,
      string_agg(p.id,   ', ' order by p.name) filter (where p.is_boss) as boss_profiles,
      coalesce(sum(coalesce(p.saves_count, 0)), 0)::bigint as saves
    from public.profiles p
    where p.company_id is not null
    group by p.company_id
  )
  select
    c.cid,
    c.cname,
    c.members,
    c.bosses,
    c.boss_profiles,
    (select count(*) from public.analytics a
      join public.profiles p2 on p2.id = a.profile_id
      where p2.company_id = c.cid),
    (select count(*) from public.leads l
      join public.profiles p3 on p3.id = l.profile_id
      where p3.company_id = c.cid),
    c.saves,
    s.plan, s.status, s.seats, s.interval, s.price_cents, s.current_period_end,
    o.seats, o.monthly_price_cents, o.label,
    (select count(*) from public.checkout_intents ci where ci.company_id = c.cid),
    (select max(ci.created_at) from public.checkout_intents ci where ci.company_id = c.cid)
  from comp c
  left join lateral (
    select * from public.team_subscriptions t
    where t.company_id = c.cid
    order by t.current_period_end desc
    limit 1
  ) s on true
  left join public.business_offers o on o.company_id = c.cid
  order by c.members desc, c.cname;
end;
$$;

revoke all on function public.admin_companies_overview() from public;
grant execute on function public.admin_companies_overview() to authenticated;


-- ---------------------------------------------------------------------
-- 4.4 Последните събрани контакти (лийдове) от всички визитки
-- ---------------------------------------------------------------------
create or replace function public.admin_recent_leads(p_limit int default 200)
returns table (
  created_at     timestamptz,
  profile_id     text,
  profile_name   text,
  company        text,
  client_name    text,
  client_phone   text,
  client_email   text,
  client_message text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_app_admin() then
    return;
  end if;

  return query
  select l.created_at, l.profile_id, p.name, p.company,
         l.client_name, l.client_phone, l.client_email, l.client_message
  from public.leads l
  left join public.profiles p on p.id = l.profile_id
  order by l.created_at desc
  limit greatest(1, least(coalesce(p_limit, 200), 1000));
end;
$$;

revoke all on function public.admin_recent_leads(int) from public;
grant execute on function public.admin_recent_leads(int) to authenticated;


-- ---------------------------------------------------------------------
-- 4.5 Сканирания по дни (за графиката) + най-активните визитки
-- ---------------------------------------------------------------------
create or replace function public.admin_scans_by_day(p_days int default 30)
returns table (day date, scans bigint, leads bigint)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_days int := greatest(1, least(coalesce(p_days, 30), 365));
begin
  if not public.is_app_admin() then
    return;
  end if;

  return query
  with span as (
    -- явният ::timestamp маха двусмислието между двете generate_series
    select generate_series(
      (current_date - (v_days - 1))::timestamp,
      current_date::timestamp,
      interval '1 day'
    )::date as day
  )
  select
    s.day,
    (select count(*) from public.analytics a where a.scanned_at::date = s.day),
    (select count(*) from public.leads    l where l.created_at::date = s.day)
  from span s
  order by s.day;
end;
$$;

revoke all on function public.admin_scans_by_day(int) from public;
grant execute on function public.admin_scans_by_day(int) to authenticated;


-- ---------------------------------------------------------------------
-- 4.6 Дневник на промените — кой какво е пипал
-- ---------------------------------------------------------------------
create or replace function public.admin_activity_feed(p_limit int default 100)
returns table (
  created_at   timestamptz,
  actor_email  text,
  profile_id   text,
  profile_name text,
  action       text,
  changed      text[]
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_app_admin() then
    return;
  end if;

  return query
  select g.created_at, g.actor_email, g.profile_id, g.profile_name, g.action, g.changed
  from public.admin_activity_log g
  order by g.created_at desc
  limit greatest(1, least(coalesce(p_limit, 100), 1000));
end;
$$;

revoke all on function public.admin_activity_feed(int) from public;
grant execute on function public.admin_activity_feed(int) to authenticated;


-- ---------------------------------------------------------------------
-- 4.7 Плащания — абонаменти, оферти и натискания на бутона
-- ---------------------------------------------------------------------
create or replace function public.admin_payments_overview()
returns json
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_subs    json;
  v_offers  json;
  v_clicks  json;
begin
  if not public.is_app_admin() then
    return json_build_object('ok', false, 'message', 'Нямате администраторски права.');
  end if;

  select coalesce(json_agg(x order by x.created_at desc), '[]'::json) into v_subs
  from (
    select s.created_at, s.company_id, s.plan, s.seats, s.price_cents,
           s.interval, s.status, s.current_period_end, s.trial_end,
           s.stripe_customer_id, s.stripe_subscription_id,
           bp.name as boss_name, bp.id as boss_profile, bu.email::text as boss_email,
           (select coalesce(max(p.company) filter (where p.is_boss), max(p.company))
              from public.profiles p
             where p.company_id = s.company_id) as company_name,
           (s.status = 'active' and s.current_period_end > now()) as is_live
    from public.team_subscriptions s
    left join public.profiles bp on bp.user_id = s.boss_user_id
    left join auth.users    bu on bu.id = s.boss_user_id
  ) x;

  select coalesce(json_agg(y order by y.updated_at desc), '[]'::json) into v_offers
  from (
    select o.company_id, o.seats, o.monthly_price_cents, o.trial, o.label,
           o.created_at, o.updated_at,
           (select coalesce(max(p.company) filter (where p.is_boss), max(p.company))
              from public.profiles p
             where p.company_id = o.company_id) as company_name,
           (select string_agg(p.name, ', ' order by p.name)
              from public.profiles p
             where p.company_id = o.company_id and p.is_boss) as bosses,
           (select count(*) from public.profiles p
             where p.company_id = o.company_id) as members,
           exists (select 1 from public.team_subscriptions s
                    where s.company_id = o.company_id
                      and s.status = 'active'
                      and s.current_period_end > now()) as activated
    from public.business_offers o
  ) y;

  select coalesce(json_agg(z order by z.created_at desc), '[]'::json) into v_clicks
  from (
    select ci.created_at, ci.user_email, ci.profile_id, ci.profile_name,
           ci.company_id, ci.plan, ci.interval, ci.outcome,
           -- платено ли е след това натискане (в рамките на седмица)
           exists (select 1 from public.team_subscriptions s
                    where s.company_id = ci.company_id
                      and s.created_at between ci.created_at - interval '1 hour'
                                           and ci.created_at + interval '7 days') as converted
    from public.checkout_intents ci
    order by ci.created_at desc
    limit 200
  ) z;

  return json_build_object(
    'ok', true,
    'subscriptions', v_subs,
    'offers', v_offers,
    'clicks', v_clicks
  );
end;
$$;

revoke all on function public.admin_payments_overview() from public;
grant execute on function public.admin_payments_overview() to authenticated;


-- ---------------------------------------------------------------------
-- 5. Проверка (по избор)
-- ---------------------------------------------------------------------
-- select public.admin_dashboard_stats();
-- select * from public.admin_profiles_overview() limit 5;
-- select * from public.admin_companies_overview();
