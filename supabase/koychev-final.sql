-- =====================================================================
-- СГХГ — окончателни настройки по избора на клиента
-- =====================================================================
-- Пусни ВСИЧКО наведнъж в Supabase → SQL Editor.
--
-- След това адресите за таговете са:
--   скрит чип (със снимка, с AR):   .../pokana.html?id=koychev
--   видим чип (без снимка, без AR): .../pokana.html?id=koychev-vidim
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Нови колони
-- ---------------------------------------------------------------------
-- mode така и не беше добавяна: кино режимът се ползваше през адреса
-- (?kino=1), а не през базата. Тук влиза заедно с останалите.
alter table public.video_invites
  add column if not exists mode        text not null default 'page',
  add column if not exists layout      text not null default 'full',
  add column if not exists ar_crop_top numeric;

alter table public.invite_views
  add column if not exists source text;

-- ---------------------------------------------------------------------
-- 2. Отчитане с етикет на носителя (?s=bilbord, ?s=plakat…)
-- ---------------------------------------------------------------------
drop function if exists public.log_invite_view(text, text);
drop function if exists public.log_invite_view(text, text, text);

create or replace function public.log_invite_view(
  p_invite   text,
  p_event    text default 'open',
  p_platform text default null,
  p_source   text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_event not in ('open', 'play', 'sound', 'complete',
                     'calendar', 'map', 'site', 'share', 'skip',
                     'ar_open', 'ar_found', 'ar_play') then
    return;
  end if;

  if not exists (select 1 from public.video_invites v where v.id = p_invite and v.published) then
    return;
  end if;

  insert into public.invite_views (invite_id, event, platform, source)
  values (
    p_invite, p_event,
    case when p_platform in ('ios','android','desktop','other') then p_platform end,
    nullif(lower(left(regexp_replace(coalesce(p_source, ''), '[^a-zA-Z0-9_-]', '', 'g'), 24)), '')
  );

  if p_event = 'open' then
    update public.video_invites set views = views + 1 where id = p_invite;
  elsif p_event = 'play' then
    update public.video_invites set plays = plays + 1 where id = p_invite;
  end if;
end;
$$;

grant execute on function public.log_invite_view(text, text, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 3. Поканата със СКРИТИЯ чип: свит изглед, AR остава
--    ar_crop_top = 331/1656 — толкова е отрязано ОТГОРЕ в оформлението,
--    за да легне видеото точно върху отпечатания кадър.
-- ---------------------------------------------------------------------
update public.video_invites set
  layout      = 'compact',
  ar_crop_top = 0.1999,
  updated_at  = now()
where id = 'koychev';

-- ---------------------------------------------------------------------
-- 4. Поканата с ВИДИМИЯ чип: същото съдържание, но без AR
--    (лицето ѝ е празно — няма кадър, който камерата да разпознае)
-- ---------------------------------------------------------------------
insert into public.video_invites (
  id, title, subtitle, video_url, poster_url, autoplay, loop_video,
  event_text, event_start, event_end,
  venue, address, maps_url, website_url, website_label, logo_url,
  sponsors_note, sponsors_url,
  theme, accent, bg_color, bilingual, published, i18n,
  mode, layout, ar_enabled
)
select
  'koychev-vidim', title, subtitle, video_url, poster_url, autoplay, loop_video,
  event_text, event_start, event_end,
  venue, address, maps_url, website_url, website_label, logo_url,
  sponsors_note, sponsors_url,
  theme, accent, bg_color, bilingual, published, i18n,
  mode, 'compact', false
from public.video_invites
where id = 'koychev'
on conflict (id) do update set
  layout     = 'compact',
  ar_enabled = false,
  updated_at = now();

-- ---------------------------------------------------------------------
-- 5. Ключ за отчета и на втората покана
-- ---------------------------------------------------------------------
insert into public.invite_tokens (invite_id, token)
select v.id, encode(gen_random_bytes(12), 'hex')
from public.video_invites v
where not exists (select 1 from public.invite_tokens t where t.invite_id = v.id);

-- ---------------------------------------------------------------------
-- 6. Нулиране на пробите преди раздаването
-- ---------------------------------------------------------------------
update public.video_invites set views = 0, plays = 0 where id like 'koychev%';
delete from public.invite_views where invite_id like 'koychev%';

-- ---------------------------------------------------------------------
-- Проверка: адресите за таговете и линковете за отчет
-- ---------------------------------------------------------------------
select
  v.id,
  case when v.ar_enabled then 'скрит чип — със снимка, с AR'
       else 'видим чип — без снимка, без AR' end                     as покана,
  'https://nfcbulgaria.com/pokana.html?id=' || v.id                  as адрес_за_тага,
  'https://nfcbulgaria.com/pokana-otchet.html?t=' || t.token         as отчет
from public.video_invites v
join public.invite_tokens t on t.invite_id = v.id
where v.id like 'koychev%'
order by v.id;
