-- =====================================================================
-- Един отчет за цяла кампания, вместо по един на всяка покана
-- =====================================================================
-- Досега всяка покана имаше свой ключ и свой линк. При две (или повече)
-- вида покани за едно и също събитие това значи два линка към клиента —
-- излишно и неудобно.
--
-- Сега един ключ може да покрива цяла кампания: отчетът показва общото
-- и разбивка по отделните покани.
--
-- Старите ключове за единична покана продължават да работят.
-- Изпълни в Supabase → SQL Editor. Безопасно за повторно пускане.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Кампания и човешко име на всяка покана
-- ---------------------------------------------------------------------
alter table public.video_invites
  add column if not exists campaign     text,
  add column if not exists report_label text;

comment on column public.video_invites.campaign is
  'Общо име за поканите на едно събитие. Един ключ за отчет покрива цялата кампания.';
comment on column public.video_invites.report_label is
  'Как се казва тази покана в отчета, напр. „Покана със скрит чип".';

-- ---------------------------------------------------------------------
-- 2. Ключовете вече могат да сочат към кампания, не само към покана
-- ---------------------------------------------------------------------
alter table public.invite_tokens
  add column if not exists campaign text;

-- invite_id спира да е задължителен: ключ за кампания няма една покана
do $$
begin
  if exists (
    select 1 from information_schema.table_constraints
    where table_schema = 'public' and table_name = 'invite_tokens'
      and constraint_type = 'PRIMARY KEY'
  ) then
    alter table public.invite_tokens drop constraint invite_tokens_pkey;
  end if;
exception when others then null;
end $$;

alter table public.invite_tokens alter column invite_id drop not null;

create unique index if not exists invite_tokens_token_key   on public.invite_tokens (token);
create unique index if not exists invite_tokens_invite_uniq on public.invite_tokens (invite_id) where invite_id is not null;
create unique index if not exists invite_tokens_camp_uniq   on public.invite_tokens (campaign)  where campaign  is not null;

-- ---------------------------------------------------------------------
-- 3. Отчетът: общо за кампанията + разбивка по покана
-- ---------------------------------------------------------------------
create or replace function public.invite_report(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ids     text[];
  v_first   public.video_invites%rowtype;
  v_camp    text;
  v_days    jsonb;
  v_events  jsonb;
  v_hours   jsonb;
  v_plats   jsonb;
  v_sources jsonb;
  v_list    jsonb;
begin
  if p_token is null or length(p_token) < 16 then
    return null;
  end if;

  -- ключ за кампания или за единична покана
  select t.campaign into v_camp from public.invite_tokens t where t.token = p_token;

  if v_camp is not null then
    select array_agg(v.id order by v.id) into v_ids
    from public.video_invites v where v.campaign = v_camp;
  else
    select array_agg(t.invite_id) into v_ids
    from public.invite_tokens t where t.token = p_token and t.invite_id is not null;
  end if;

  if v_ids is null or array_length(v_ids, 1) is null then
    return null;
  end if;

  select * into v_first from public.video_invites where id = v_ids[1];

  select coalesce(jsonb_agg(x order by x.day), '[]'::jsonb) into v_days
  from (
    select (w.created_at at time zone 'Europe/Sofia')::date as day,
           count(*) filter (where w.event = 'open')     as opens,
           count(*) filter (where w.event = 'play')     as plays,
           count(*) filter (where w.event = 'complete') as completions
    from public.invite_views w where w.invite_id = any(v_ids) group by 1
  ) x;

  select coalesce(jsonb_object_agg(e.event, e.n), '{}'::jsonb) into v_events
  from (select w.event, count(*) as n from public.invite_views w
        where w.invite_id = any(v_ids) group by w.event) e;

  select coalesce(jsonb_object_agg(h.hh::text, h.n), '{}'::jsonb) into v_hours
  from (select extract(hour from (w.created_at at time zone 'Europe/Sofia'))::int as hh,
               count(*) as n
        from public.invite_views w
        where w.invite_id = any(v_ids) and w.event = 'open' group by 1) h;

  select coalesce(jsonb_object_agg(p.plat, p.n), '{}'::jsonb) into v_plats
  from (select coalesce(w.platform, 'other') as plat, count(*) as n
        from public.invite_views w
        where w.invite_id = any(v_ids) and w.event = 'open' group by 1) p;

  select coalesce(jsonb_object_agg(s.src, s.n), '{}'::jsonb) into v_sources
  from (select coalesce(w.source, 'pokana') as src, count(*) as n
        from public.invite_views w
        where w.invite_id = any(v_ids) and w.event = 'open' group by 1) s;

  -- разбивка по отделните покани (само ако са повече от една)
  select coalesce(jsonb_agg(jsonb_build_object(
           'id',          v.id,
           'label',       coalesce(v.report_label, v.id),
           'views',       v.views,
           'plays',       v.plays,
           'completions', (select count(*) from public.invite_views w
                           where w.invite_id = v.id and w.event = 'complete')
         ) order by v.id), '[]'::jsonb)
  into v_list
  from public.video_invites v where v.id = any(v_ids);

  return jsonb_build_object(
    'title',       v_first.title,
    'subtitle',    v_first.subtitle,
    'venue',       v_first.venue,
    'logo_url',    v_first.logo_url,
    'accent',      v_first.accent,
    'views',       (select coalesce(sum(views), 0) from public.video_invites where id = any(v_ids)),
    'plays',       (select coalesce(sum(plays), 0) from public.video_invites where id = any(v_ids)),
    'completions', (select count(*) from public.invite_views w
                    where w.invite_id = any(v_ids) and w.event = 'complete'),
    'first_view',  (select min(created_at) from public.invite_views w where w.invite_id = any(v_ids)),
    'last_view',   (select max(created_at) from public.invite_views w where w.invite_id = any(v_ids)),
    'daily',       v_days,
    'events',      v_events,
    'hours',       v_hours,
    'platforms',   v_plats,
    'sources',     v_sources,
    'invites',     case when array_length(v_ids, 1) > 1 then v_list else '[]'::jsonb end
  );
end;
$$;

grant execute on function public.invite_report(text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 4. Двете покани на Койчев стават една кампания с ЕДИН отчет
-- ---------------------------------------------------------------------
update public.video_invites set campaign = 'koychev', report_label = 'Покана със скрит чип'
where id = 'koychev';

update public.video_invites set campaign = 'koychev', report_label = 'Покана с видим чип'
where id = 'koychev-vidim';

-- старите ключове за единична покана отпадат
delete from public.invite_tokens where invite_id like 'koychev%';

insert into public.invite_tokens (invite_id, campaign, token)
values (null, 'koychev', encode(gen_random_bytes(12), 'hex'))
on conflict do nothing;

-- нулиране на пробите преди раздаването
update public.video_invites set views = 0, plays = 0 where campaign = 'koychev';
delete from public.invite_views where invite_id like 'koychev%';

-- ---------------------------------------------------------------------
-- Единственият линк, който отива при клиента
-- ---------------------------------------------------------------------
select 'https://nfcbulgaria.com/pokana-otchet.html?t=' || token as отчет_за_кампанията
from public.invite_tokens where campaign = 'koychev';
