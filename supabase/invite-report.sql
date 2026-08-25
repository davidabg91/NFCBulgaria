-- =====================================================================
-- Отчет за клиента — линк за четене, без акаунт
-- =====================================================================
-- ПУСНИ СЛЕД video-invites.sql. Безопасно за повторно пускане.
--
-- Дава на организатора адрес от вида
--     https://nfcbulgaria.com/pokana-otchet.html?t=<таен ключ>
-- на който вижда колко пъти е сканирана поканата, колко души са пуснали
-- видеото и колко са го изгледали докрай — на живо, по дни.
--
-- ВАЖНО ЗА УСТРОЙСТВОТО: ключовете стоят в ОТДЕЛНА таблица, а не като
-- колона във video_invites. Причината е, че video_invites е публично
-- четима (иначе поканата няма как да се покаже), тоест всяка нейна
-- колона излиза навън през публичния ключ на сайта — включително и
-- „тайният" ключ. invite_tokens е с включен RLS без нито една политика и
-- без права за anon: отвън е невидима, а функцията отдолу я чете, защото
-- се изпълнява с правата на собственика.
--
-- Ако по-ранна версия е добавила колоната video_invites.stats_token, тя
-- се маха тук и се издават нови ключове — старите се смятат за изтекли.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Таблицата с ключовете — затворена за външния свят
-- ---------------------------------------------------------------------
create table if not exists public.invite_tokens (
  invite_id  text primary key references public.video_invites(id) on delete cascade,
  token      text not null unique,
  created_at timestamptz not null default now()
);

comment on table public.invite_tokens is
  'Тайни ключове за отчетите на клиентите. НЕ се чете отвън — само през invite_report().';

alter table public.invite_tokens enable row level security;
revoke all on public.invite_tokens from anon, authenticated;

-- Старият, изтекъл ключ отпада заедно с колоната
alter table public.video_invites drop column if exists stats_token;

-- Всяка покана без ключ получава нов
insert into public.invite_tokens (invite_id, token)
select v.id, encode(gen_random_bytes(12), 'hex')
from public.video_invites v
where not exists (
  select 1 from public.invite_tokens t where t.invite_id = v.id
);

-- ---------------------------------------------------------------------
-- Функцията, която отчетът чете. Приема само верен ключ и връща само
-- изброеното тук — таблиците остават затворени.
-- ---------------------------------------------------------------------
create or replace function public.invite_report(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v          public.video_invites%rowtype;
  v_days     jsonb;
  v_events   jsonb;
  v_hours    jsonb;
  v_plats    jsonb;
  v_sources  jsonb;
begin
  if p_token is null or length(p_token) < 16 then
    return null;
  end if;

  select vi.* into v
  from public.video_invites vi
  join public.invite_tokens t on t.invite_id = vi.id
  where t.token = p_token;

  if not found then
    return null;
  end if;

  select coalesce(jsonb_agg(x order by x.day), '[]'::jsonb)
  into v_days
  from (
    select (w.created_at at time zone 'Europe/Sofia')::date   as day,
           count(*) filter (where w.event = 'open')           as opens,
           count(*) filter (where w.event = 'play')           as plays,
           count(*) filter (where w.event = 'complete')       as completions
    from public.invite_views w
    where w.invite_id = v.id
    group by 1
  ) x;

  -- брой по вид събитие: {"open":137,"play":118,"calendar":9,...}
  select coalesce(jsonb_object_agg(e.event, e.n), '{}'::jsonb)
  into v_events
  from (
    select w.event, count(*) as n
    from public.invite_views w
    where w.invite_id = v.id
    group by w.event
  ) e;

  -- сканирания по час на деня (българско време)
  select coalesce(jsonb_object_agg(h.hh::text, h.n), '{}'::jsonb)
  into v_hours
  from (
    select extract(hour from (w.created_at at time zone 'Europe/Sofia'))::int as hh,
           count(*) as n
    from public.invite_views w
    where w.invite_id = v.id and w.event = 'open'
    group by 1
  ) h;

  -- с какво устройство отварят
  select coalesce(jsonb_object_agg(p.plat, p.n), '{}'::jsonb)
  into v_plats
  from (
    select coalesce(w.platform, 'other') as plat, count(*) as n
    from public.invite_views w
    where w.invite_id = v.id and w.event = 'open'
    group by 1
  ) p;

  -- откъде идват: самата покана, билборд, плакат, винил…
  select coalesce(jsonb_object_agg(x.src, x.n), '{}'::jsonb)
  into v_sources
  from (
    select coalesce(w.source, 'pokana') as src, count(*) as n
    from public.invite_views w
    where w.invite_id = v.id and w.event = 'open'
    group by 1
  ) x;

  return jsonb_build_object(
    'title',       v.title,
    'subtitle',    v.subtitle,
    'venue',       v.venue,
    'logo_url',    v.logo_url,
    'accent',      v.accent,
    'views',       v.views,
    'plays',       v.plays,
    'completions', (select count(*) from public.invite_views w
                    where w.invite_id = v.id and w.event = 'complete'),
    'first_view',  (select min(created_at) from public.invite_views w where w.invite_id = v.id),
    'last_view',   (select max(created_at) from public.invite_views w where w.invite_id = v.id),
    'daily',       v_days,
    'events',      v_events,
    'hours',       v_hours,
    'platforms',   v_plats,
    'sources',     v_sources
  );
end;
$$;

grant execute on function public.invite_report(text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- Линкът, който пращаш на клиента
-- ---------------------------------------------------------------------
select
  v.id,
  v.title,
  'https://nfcbulgaria.com/pokana-otchet.html?t=' || t.token as отчет
from public.invite_tokens t
join public.video_invites v on v.id = t.invite_id
order by v.created_at;

-- Смяна на ключа (старият линк спира да работи веднага):
-- update public.invite_tokens
-- set token = encode(gen_random_bytes(12), 'hex')
-- where invite_id = 'koychev';
