-- =====================================================================
-- Портфолио във визитката — снимки и видеа (платен абонамент)
-- =====================================================================
-- Пуска се с:  npx supabase db query --linked -f supabase/portfolio.sql
-- Идемпотентно.
--
-- Пакети (цените живеят в Stripe и в portfolio-checkout, тук са лимитите):
--   foto   — 20 снимки                       8,99 €/мес · 89,90 €/год
--   video  — 40 снимки + 4 видеа до 60 сек   16,99 €/мес · 169,90 €/год
--   pro    — 60 снимки + 12 видеа до 60 сек  25,99 €/мес · 259,90 €/год
--
-- Модел:
--   * portfolio_subscriptions — абонаментът. Пише го САМО сървърът
--     (portfolio-checkout / stripe-webhook) със SERVICE_KEY.
--   * portfolio_items         — снимките и видеата. Клиентът пише само през
--     RPC-тата долу, които проверяват пакета и лимита.
--   * Storage bucket „portfolio" — файловете. Публично четим, качване само
--     в своята папка {user_id}/… и само при активен пакет с място.
--   * При изтекъл абонамент нищо не се трие — портфолиото просто не се
--     показва на визитката, докато не се поднови.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Лимити по пакет
-- ---------------------------------------------------------------------
create or replace function public.portfolio_limits(p_plan text)
returns table (photos int, videos int, max_video_sec int)
language sql
immutable
as $$
  select
    case p_plan when 'foto' then 20 when 'video' then 40 when 'pro' then 60 else 0 end,
    case p_plan when 'video' then 4 when 'pro' then 12 else 0 end,
    case p_plan when 'video' then 60 when 'pro' then 60 else 0 end;
$$;


-- ---------------------------------------------------------------------
-- 2. Абонаменти
-- ---------------------------------------------------------------------
create table if not exists public.portfolio_subscriptions (
  id                     bigserial primary key,
  user_id                uuid not null references auth.users (id) on delete cascade,
  profile_id             text,
  plan                   text not null check (plan in ('foto', 'video', 'pro')),
  interval               text not null default 'month' check (interval in ('month', 'year')),
  price_cents            int  not null default 0,
  status                 text not null default 'active',
  cancel_at_period_end   boolean not null default false,
  current_period_end     timestamptz not null,
  stripe_customer_id     text,
  stripe_subscription_id text unique,
  stripe_session_id      text,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

create index if not exists portfolio_subscriptions_user_idx
  on public.portfolio_subscriptions (user_id, current_period_end desc);

alter table public.portfolio_subscriptions enable row level security;

drop policy if exists "read own portfolio subscription" on public.portfolio_subscriptions;
create policy "read own portfolio subscription"
  on public.portfolio_subscriptions for select
  using (user_id = auth.uid());

grant select on public.portfolio_subscriptions to authenticated;
grant select, insert, update on public.portfolio_subscriptions to service_role;
grant usage, select on sequence public.portfolio_subscriptions_id_seq to service_role;


-- Активният пакет на потребител (или null). 3 дни толеранс след края на
-- периода — подновяването в Stripe понякога идва с малко закъснение.
create or replace function public.portfolio_plan_of(p_user uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select s.plan
  from public.portfolio_subscriptions s
  where s.user_id = p_user
    and s.status in ('active', 'trialing', 'past_due')
    and s.current_period_end + interval '3 days' > now()
  order by case s.plan when 'pro' then 3 when 'video' then 2 else 1 end desc,
           s.current_period_end desc
  limit 1;
$$;

revoke all on function public.portfolio_plan_of(uuid) from public;


-- ---------------------------------------------------------------------
-- 3. Елементите
-- ---------------------------------------------------------------------
create table if not exists public.portfolio_items (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users (id) on delete cascade,
  kind         text not null check (kind in ('image', 'video')),
  url          text not null,           -- снимка 1600px webp / видео 720p mp4
  thumb_url    text not null,           -- 600px webp за мрежата
  poster_url   text,                    -- само за видео: 1280px кадър
  caption      text check (char_length(caption) <= 300),
  width        int,
  height       int,
  duration_sec numeric(6, 1),
  size_bytes   bigint not null default 0,
  sort_order   int not null default 0,
  created_at   timestamptz not null default now()
);

create index if not exists portfolio_items_user_idx
  on public.portfolio_items (user_id, sort_order, created_at);

alter table public.portfolio_items enable row level security;

-- Собственикът си вижда своите. Публичният показ минава през
-- get_portfolio(), което гледа и дали абонаментът е активен.
drop policy if exists "read own portfolio items" on public.portfolio_items;
create policy "read own portfolio items"
  on public.portfolio_items for select
  using (user_id = auth.uid());

grant select on public.portfolio_items to authenticated;
grant select, insert, update, delete on public.portfolio_items to service_role;


-- ---------------------------------------------------------------------
-- 4. Storage bucket
-- ---------------------------------------------------------------------
-- 30 MB на файл: компресираното видео е ~10 MB за минута, но браузъри
-- без WebCodecs качват оригинала (там таблото пуска само до 25 MB).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('portfolio', 'portfolio', true, 31457280,
        array['image/webp', 'image/jpeg', 'video/mp4', 'video/webm'])
on conflict (id) do update set
  public             = true,
  file_size_limit    = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Може ли текущият потребител да качи още един файл: активен пакет и
-- брой файлове под тавана (снимка = 2 файла, видео = 3) + малко резерв
-- за прекъснати качвания.
create or replace function public.portfolio_upload_allowed()
returns boolean
language plpgsql
stable
security definer
set search_path = public, storage
as $$
declare
  v_plan  text := public.portfolio_plan_of(auth.uid());
  v_lim   record;
  v_files int;
begin
  if auth.uid() is null or v_plan is null then
    return false;
  end if;

  select * into v_lim from public.portfolio_limits(v_plan);

  select count(*) into v_files
  from storage.objects o
  where o.bucket_id = 'portfolio'
    and (storage.foldername(o.name))[1] = auth.uid()::text;

  return v_files < (v_lim.photos * 2 + v_lim.videos * 3 + 6);
end;
$$;

revoke all on function public.portfolio_upload_allowed() from public;
grant execute on function public.portfolio_upload_allowed() to authenticated;

drop policy if exists "portfolio owner upload" on storage.objects;
create policy "portfolio owner upload"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'portfolio'
    and (storage.foldername(name))[1] = auth.uid()::text
    and public.portfolio_upload_allowed()
  );

drop policy if exists "portfolio owner delete" on storage.objects;
create policy "portfolio owner delete"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'portfolio'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Storage API-то прави SELECT след DELETE, затова собственикът трябва да
-- вижда своите редове. Публичното четене на файлове не минава оттук.
drop policy if exists "portfolio owner read" on storage.objects;
create policy "portfolio owner read"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'portfolio'
    and (storage.foldername(name))[1] = auth.uid()::text
  );


-- ---------------------------------------------------------------------
-- 5. Моето портфолио — за таблото
-- ---------------------------------------------------------------------
create or replace function public.get_my_portfolio()
returns json
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_plan text;
  v_sub  record;
  v_lim  record;
begin
  if v_uid is null then
    return json_build_object('ok', false, 'message', 'Няма активна сесия.');
  end if;

  v_plan := public.portfolio_plan_of(v_uid);
  select * into v_lim from public.portfolio_limits(v_plan);

  select s.plan, s.interval, s.status, s.current_period_end, s.cancel_at_period_end,
         (s.stripe_subscription_id is null or s.stripe_subscription_id like 'manual-%') as manual
    into v_sub
  from public.portfolio_subscriptions s
  where s.user_id = v_uid and s.plan = v_plan
    and s.current_period_end + interval '3 days' > now()
  order by s.current_period_end desc
  limit 1;

  return json_build_object(
    'ok', true,
    'plan', v_plan,
    'interval', v_sub.interval,
    'status', v_sub.status,
    'period_end', v_sub.current_period_end,
    'cancel_at_period_end', coalesce(v_sub.cancel_at_period_end, false),
    'manual', coalesce(v_sub.manual, false),
    'limits', json_build_object('photos', v_lim.photos, 'videos', v_lim.videos,
                                'max_video_sec', v_lim.max_video_sec),
    'items', coalesce((
      select json_agg(json_build_object(
        'id', i.id, 'kind', i.kind, 'url', i.url, 'thumb_url', i.thumb_url,
        'poster_url', i.poster_url, 'caption', i.caption, 'width', i.width,
        'height', i.height, 'duration_sec', i.duration_sec, 'size_bytes', i.size_bytes
      ) order by i.sort_order, i.created_at)
      from public.portfolio_items i where i.user_id = v_uid
    ), '[]'::json)
  );
end;
$$;

revoke all on function public.get_my_portfolio() from public;
grant execute on function public.get_my_portfolio() to authenticated;


-- ---------------------------------------------------------------------
-- 6. Добавяне / описание / подредба / изтриване
-- ---------------------------------------------------------------------
create or replace function public.portfolio_add_item(
  p_kind         text,
  p_url          text,
  p_thumb_url    text,
  p_poster_url   text,
  p_caption      text,
  p_width        int,
  p_height       int,
  p_duration_sec numeric,
  p_size_bytes   bigint
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_plan   text;
  v_lim    record;
  v_used   int;
  v_prefix text;
  v_id     uuid;
begin
  if v_uid is null then
    return json_build_object('ok', false, 'message', 'Няма активна сесия.');
  end if;

  v_plan := public.portfolio_plan_of(v_uid);
  if v_plan is null then
    return json_build_object('ok', false, 'code', 'no_plan',
      'message', 'Портфолиото не е активно. Изберете пакет.');
  end if;
  select * into v_lim from public.portfolio_limits(v_plan);

  if p_kind not in ('image', 'video') then
    return json_build_object('ok', false, 'message', 'Непознат вид файл.');
  end if;

  select count(*) into v_used
  from public.portfolio_items i where i.user_id = v_uid and i.kind = p_kind;

  if p_kind = 'image' and v_used >= v_lim.photos then
    return json_build_object('ok', false, 'code', 'limit',
      'message', format('Пакетът ви е до %s снимки.', v_lim.photos));
  end if;

  if p_kind = 'video' then
    if v_lim.videos = 0 then
      return json_build_object('ok', false, 'code', 'no_video',
        'message', 'Видеата са включени от пакет „Фото + Видео“ нагоре.');
    end if;
    if v_used >= v_lim.videos then
      return json_build_object('ok', false, 'code', 'limit',
        'message', format('Пакетът ви е до %s видеа.', v_lim.videos));
    end if;
    if coalesce(p_duration_sec, 0) > v_lim.max_video_sec + 1 then
      return json_build_object('ok', false,
        'message', format('Видеото е до %s секунди.', v_lim.max_video_sec));
    end if;
  end if;

  -- Адресите трябва да сочат в НЕГОВАТА папка в нашия bucket — иначе
  -- някой може да закачи чужди файлове или външни линкове.
  v_prefix := '/storage/v1/object/public/portfolio/' || v_uid::text || '/';
  if position(v_prefix in coalesce(p_url, '')) = 0
     or position(v_prefix in coalesce(p_thumb_url, '')) = 0
     or (p_poster_url is not null and position(v_prefix in p_poster_url) = 0) then
    return json_build_object('ok', false, 'message', 'Невалиден адрес на файла.');
  end if;

  insert into public.portfolio_items
    (user_id, kind, url, thumb_url, poster_url, caption, width, height,
     duration_sec, size_bytes, sort_order)
  values
    (v_uid, p_kind, p_url, p_thumb_url, p_poster_url,
     nullif(left(trim(coalesce(p_caption, '')), 300), ''),
     p_width, p_height, p_duration_sec, coalesce(p_size_bytes, 0),
     coalesce((select max(sort_order) + 1 from public.portfolio_items where user_id = v_uid), 0))
  returning id into v_id;

  return json_build_object('ok', true, 'id', v_id);
end;
$$;

revoke all on function public.portfolio_add_item(text, text, text, text, text, int, int, numeric, bigint) from public;
grant execute on function public.portfolio_add_item(text, text, text, text, text, int, int, numeric, bigint) to authenticated;


create or replace function public.portfolio_set_caption(p_id uuid, p_caption text)
returns json
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.portfolio_items
  set caption = nullif(left(trim(coalesce(p_caption, '')), 300), '')
  where id = p_id and user_id = auth.uid();
  return json_build_object('ok', found);
end;
$$;

revoke all on function public.portfolio_set_caption(uuid, text) from public;
grant execute on function public.portfolio_set_caption(uuid, text) to authenticated;


-- Подредба: подава се целият списък id-та в новия ред
create or replace function public.portfolio_reorder(p_ids uuid[])
returns json
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.portfolio_items i
  set sort_order = x.ord
  from unnest(p_ids) with ordinality as x(id, ord)
  where i.id = x.id and i.user_id = auth.uid();
  return json_build_object('ok', true);
end;
$$;

revoke all on function public.portfolio_reorder(uuid[]) from public;
grant execute on function public.portfolio_reorder(uuid[]) to authenticated;


-- Трие реда и връща пътищата на файловете — таблото ги маха от Storage
-- (директно триене в storage.objects не изтрива самите файлове).
create or replace function public.portfolio_delete_item(p_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.portfolio_items;
begin
  delete from public.portfolio_items
  where id = p_id and user_id = auth.uid()
  returning * into v_row;

  if v_row.id is null then
    return json_build_object('ok', false, 'message', 'Няма такъв елемент.');
  end if;

  return json_build_object('ok', true,
    'urls', json_build_array(v_row.url, v_row.thumb_url, v_row.poster_url));
end;
$$;

revoke all on function public.portfolio_delete_item(uuid) from public;
grant execute on function public.portfolio_delete_item(uuid) to authenticated;


-- ---------------------------------------------------------------------
-- 7. Публичният показ на визитката
-- ---------------------------------------------------------------------
-- Само при активен пакет и само до лимита му (ако е минал на по-малък
-- пакет, излишните остават скрити, но не се трият).
create or replace function public.get_portfolio(p_profile_id text)
returns json
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid  uuid;
  v_plan text;
  v_lim  record;
begin
  select p.user_id into v_uid from public.profiles p where p.id = p_profile_id limit 1;
  if v_uid is null then return '[]'::json; end if;

  v_plan := public.portfolio_plan_of(v_uid);
  if v_plan is null then return '[]'::json; end if;
  select * into v_lim from public.portfolio_limits(v_plan);

  return coalesce((
    select json_agg(json_build_object(
      'kind', x.kind, 'url', x.url, 'thumb_url', x.thumb_url,
      'poster_url', x.poster_url, 'caption', x.caption,
      'width', x.width, 'height', x.height, 'duration_sec', x.duration_sec
    ) order by x.sort_order, x.created_at)
    from (
      select i.*, row_number() over (partition by i.kind order by i.sort_order, i.created_at) as rn
      from public.portfolio_items i
      where i.user_id = v_uid
    ) x
    where (x.kind = 'image' and x.rn <= v_lim.photos)
       or (x.kind = 'video' and x.rn <= v_lim.videos)
  ), '[]'::json);
end;
$$;

revoke all on function public.get_portfolio(text) from public;
grant execute on function public.get_portfolio(text) to anon, authenticated;


-- ---------------------------------------------------------------------
-- 8. Админ: подаряване на пакет + справка
-- ---------------------------------------------------------------------
create or replace function public.admin_grant_portfolio(
  p_profile_id text,
  p_plan       text,
  p_months     int default 12
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid;
begin
  if not public.is_app_admin() then
    return json_build_object('ok', false, 'message', 'Нямате администраторски права.');
  end if;
  if p_plan not in ('foto', 'video', 'pro') then
    return json_build_object('ok', false, 'message', 'Непознат пакет.');
  end if;

  select p.user_id into v_uid from public.profiles p where p.id = p_profile_id;
  if v_uid is null then
    return json_build_object('ok', false, 'message', 'Няма такъв профил (или е без акаунт).');
  end if;

  insert into public.portfolio_subscriptions
    (user_id, profile_id, plan, interval, price_cents, status, current_period_end,
     stripe_subscription_id)
  values
    (v_uid, p_profile_id, p_plan, 'month', 0, 'active',
     now() + make_interval(months => greatest(coalesce(p_months, 12), 1)),
     'manual-' || v_uid::text)
  on conflict (stripe_subscription_id) do update set
    plan = excluded.plan,
    status = 'active',
    current_period_end = excluded.current_period_end,
    updated_at = now();

  return json_build_object('ok', true,
    'message', format('Портфолио „%s“ е включено на %s за %s мес.', p_plan, p_profile_id, p_months));
end;
$$;

revoke all on function public.admin_grant_portfolio(text, text, int) from public;
grant execute on function public.admin_grant_portfolio(text, text, int) to authenticated;


create or replace function public.admin_portfolio_overview()
returns json
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_app_admin() then
    return json_build_object('ok', false, 'message', 'Нямате администраторски права.');
  end if;

  return json_build_object(
    'ok', true,
    'subs', coalesce((
      select json_agg(x order by x.created_at desc) from (
        select s.created_at, s.plan, s.interval, s.price_cents, s.status,
               s.current_period_end, s.cancel_at_period_end,
               (s.stripe_subscription_id is null or s.stripe_subscription_id like 'manual-%') as manual,
               (public.portfolio_plan_of(s.user_id) = s.plan) as is_active,
               p.id as profile_id, p.name as profile_name, p.company,
               u.email::text as user_email,
               (select count(*) from public.portfolio_items i where i.user_id = s.user_id and i.kind = 'image') as photos,
               (select count(*) from public.portfolio_items i where i.user_id = s.user_id and i.kind = 'video') as videos,
               (select coalesce(sum(i.size_bytes), 0) from public.portfolio_items i where i.user_id = s.user_id) as bytes
        from public.portfolio_subscriptions s
        left join lateral (select * from public.profiles pp where pp.user_id = s.user_id limit 1) p on true
        left join auth.users u on u.id = s.user_id
        order by s.created_at desc
        limit 500
      ) x
    ), '[]'::json),
    'total_bytes', (select coalesce(sum(size_bytes), 0) from public.portfolio_items)
  );
end;
$$;

revoke all on function public.admin_portfolio_overview() from public;
grant execute on function public.admin_portfolio_overview() to authenticated;


-- ---------------------------------------------------------------------
-- 9. Плащанията за портфолио влизат в същия списък за фактуриране
-- ---------------------------------------------------------------------
-- Купувачът може да е без фирмена група — тогава фактурата е на името
-- от визитката.
alter table public.subscription_payments alter column company_id drop not null;
alter table public.subscription_payments add column if not exists profile_id text;

create or replace function public.admin_list_payments()
returns table (
  id            bigint,
  paid_at       timestamptz,
  company_id    uuid,
  company_label text,
  plan          text,
  plan_interval text,
  amount_cents  int,
  currency      text,
  period_start  timestamptz,
  period_end    timestamptz,
  receipt_url   text,
  invoiced      boolean,
  invoice_note  text,
  billing       json
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_app_admin() then
    raise exception 'Нямате администраторски права.';
  end if;

  return query
  select
    sp.id, sp.paid_at, sp.company_id,
    coalesce(cb.company_name,
             (select p.company from public.profiles p
               where p.company_id = sp.company_id and coalesce(p.company, '') <> ''
               limit 1),
             (select p.name || coalesce(' · ' || nullif(p.email, ''), '')
                from public.profiles p where p.id = sp.profile_id)) as company_label,
    sp.plan, sp.interval, sp.amount_cents, sp.currency,
    sp.period_start, sp.period_end, sp.receipt_url,
    sp.invoiced, sp.invoice_note,
    case when cb.company_id is null then null else json_build_object(
      'company_name', cb.company_name, 'eik', cb.eik, 'vat_number', cb.vat_number,
      'address', cb.address, 'city', cb.city, 'postal_code', cb.postal_code,
      'mol', cb.mol, 'email', cb.email) end as billing
  from public.subscription_payments sp
  left join public.company_billing cb on cb.company_id = sp.company_id
  order by sp.paid_at desc
  limit 500;
end;
$$;

revoke all on function public.admin_list_payments() from public;
grant execute on function public.admin_list_payments() to authenticated;


-- ---------------------------------------------------------------------
-- Проверка
-- ---------------------------------------------------------------------
-- select * from public.portfolio_limits('video');
-- select public.get_portfolio('DeividDimitrov');
-- select * from public.portfolio_subscriptions order by created_at desc;
-- select public.admin_grant_portfolio('DeividDimitrov', 'pro', 1);
