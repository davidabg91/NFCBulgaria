-- =====================================================================
-- Отчет за клиента — линк за четене, без акаунт
-- =====================================================================
-- ПУСНИ СЛЕД video-invites.sql.
--
-- Дава на организатора адрес от вида
--     https://nfcbulgaria.com/pokana-otchet.html?t=<таен ключ>
-- на който вижда колко пъти е сканирана поканата, колко души са пуснали
-- видеото и колко са го изгледали докрай — на живо, по дни.
--
-- Достъпът е само с ключа: без него не се вижда нищо, а с него не се
-- стига до друга покана, до базата или до останалите клиенти. Ключът се
-- сменя по всяко време (виж най-долу), ако линкът изтече някъде.
--
-- Безопасно за повторно пускане.
-- =====================================================================

create extension if not exists pgcrypto;

alter table public.video_invites
  add column if not exists stats_token text unique;

comment on column public.video_invites.stats_token is
  'Таен ключ за отчета на клиента: pokana-otchet.html?t=<ключ>. Само за четене.';

-- Всяка покана без ключ получава такъв
update public.video_invites
set stats_token = encode(gen_random_bytes(12), 'hex')
where stats_token is null;

-- ---------------------------------------------------------------------
-- Функцията, която отчетът чете. Пуска се с правата на собственика,
-- затова таблиците остават затворени за външния свят — навън излиза
-- само това, което е изброено тук, и то срещу верен ключ.
-- ---------------------------------------------------------------------
create or replace function public.invite_report(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v      public.video_invites%rowtype;
  v_days jsonb;
begin
  if p_token is null or length(p_token) < 16 then
    return null;
  end if;

  select * into v from public.video_invites where stats_token = p_token;
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

  return jsonb_build_object(
    'title',       v.title,
    'subtitle',    v.subtitle,
    'event_text',  v.event_text,
    'venue',       v.venue,
    'logo_url',    v.logo_url,
    'accent',      v.accent,
    'views',       v.views,
    'plays',       v.plays,
    'completions', (select count(*) from public.invite_views w
                    where w.invite_id = v.id and w.event = 'complete'),
    'first_view',  (select min(created_at) from public.invite_views w where w.invite_id = v.id),
    'last_view',   (select max(created_at) from public.invite_views w where w.invite_id = v.id),
    'daily',       v_days
  );
end;
$$;

grant execute on function public.invite_report(text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- Линкът, който пращаш на клиента
-- ---------------------------------------------------------------------
select
  id,
  title,
  'https://nfcbulgaria.com/pokana-otchet.html?t=' || stats_token as отчет
from public.video_invites
order by created_at;

-- Смяна на ключа (старият линк спира да работи веднага):
-- update public.video_invites
-- set stats_token = encode(gen_random_bytes(12), 'hex')
-- where id = 'koychev';
