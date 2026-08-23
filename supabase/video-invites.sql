-- =====================================================================
-- Видео покани (NFC таг → видео на нашия сайт)
-- =====================================================================
-- Нов тип страница в платформата: pokana.html?id=<slug>. NFC тагът носи
-- само този кратък, ПОСТОЯНЕН адрес — видеото, текстовете и датите се
-- сменят по всяко време от базата, без да се пипат таговете. Точно това
-- иска клиент като СГХГ: таговете се заключват срещу презапис, а
-- съдържанието остава редактируемо.
--
-- Самото видео НЕ стои в базата — в video_url се записва публичният му
-- адрес (Supabase Storage bucket, Cloudflare R2, GitHub Pages…).
--
-- Изпълни веднъж в Supabase → SQL Editor. Безопасно за повторно пускане.
-- =====================================================================

create table if not exists public.video_invites (
  id             text primary key,          -- slug в адреса: pokana.html?id=koychev
  title          text not null,
  subtitle       text,

  -- Видео
  video_url      text not null,             -- MP4 (H.264/AAC) — чете се от iOS и Android
  video_url_webm text,                      -- по избор: втори, по-лек формат
  poster_url     text,                      -- кадър, който се вижда преди пускане
  autoplay       boolean not null default true,   -- старт без звук + „докоснете за звук"
  loop_video     boolean not null default false,

  -- Събитие
  description    text,
  event_text     text,                      -- свободен ред: „12 септември 2026, 18:00 ч."
  event_start    timestamptz,               -- за бутона „Добави в календара"
  event_end      timestamptz,
  venue          text,
  address        text,
  maps_url       text,
  website_url    text,
  website_label  text,
  logo_url       text,

  -- Вид
  theme          text not null default 'dark',      -- dark | light
  mode           text not null default 'page',      -- page | cinema (клипът пръв, цял екран)
  accent         text not null default '#c9a227',   -- акцентен цвят
  bg_color       text not null default '#0b0b0d',
  bilingual      boolean not null default false,    -- BG и EN един до друг (както в печата)
  sponsors_note  text,                              -- редът над логата на партньорите
  sponsors_url   text,                              -- лентата с логата (една картинка)

  -- Управление
  published      boolean not null default true,
  views          integer not null default 0,
  plays          integer not null default 0,
  i18n           jsonb,                     -- {"en":{"title":"...","description":"..."}}
  owner_id       uuid references auth.users(id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

comment on table  public.video_invites is 'Видео покани, отваряни през NFC таг: pokana.html?id=<slug>';
comment on column public.video_invites.video_url is 'Публичен адрес на MP4 файла (Storage/R2/CDN), а не самият файл';
comment on column public.video_invites.i18n is
  'Английски текстове: {"en":{"title","subtitle","description","event_text","venue","address","sponsors_note"}}';
comment on column public.video_invites.mode is
  'page = поканата с видеото в нея; cinema = клипът пръв на цял екран, поканата се показва след края му';
comment on column public.video_invites.bilingual is
  'true = двата езика се показват заедно (за покани, чийто печатен оригинал е двуезичен)';
comment on column public.video_invites.event_text is
  'Многоредово. Ред, ограден с ** **, излиза получер; празен ред прави отстъп.';

-- Ако таблицата вече съществува от по-ранно пускане
alter table public.video_invites
  add column if not exists theme         text not null default 'dark',
  add column if not exists mode          text not null default 'page',
  add column if not exists bilingual     boolean not null default false,
  add column if not exists sponsors_note text,
  add column if not exists sponsors_url  text;

-- ---------------------------------------------------------------------
-- Лог на отварянията — за отчет към клиента ("колко пъти е сканирана")
-- ---------------------------------------------------------------------
create table if not exists public.invite_views (
  id         bigserial primary key,
  invite_id  text not null references public.video_invites(id) on delete cascade,
  event      text not null default 'open',   -- виж списъка в log_invite_view
  platform   text,                           -- ios | android | desktop | other
  created_at timestamptz not null default now()
);

alter table public.invite_views add column if not exists platform text;

create index if not exists invite_views_invite_idx on public.invite_views (invite_id, created_at desc);

-- ---------------------------------------------------------------------
-- RLS: публично се чете само публикувана покана; пише се от service_role
-- ---------------------------------------------------------------------
alter table public.video_invites enable row level security;
alter table public.invite_views  enable row level security;

drop policy if exists "video_invites public read" on public.video_invites;
create policy "video_invites public read"
  on public.video_invites for select
  using (published = true);

drop policy if exists "video_invites owner write" on public.video_invites;
create policy "video_invites owner write"
  on public.video_invites for all
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

-- invite_views няма публични политики: пише се само през RPC-то отдолу
-- (security definer), за да не може някой да пълни таблицата на ръка.

-- Изрично право за четене. Политиката отгоре казва КОИ редове се виждат,
-- но без този grant PostgREST връща „няма такава таблица" и поканата
-- излиза като ненамерена, макар редът да си стои в базата.
grant select on public.video_invites to anon, authenticated;

-- ---------------------------------------------------------------------
-- Броене на отваряния/гледания
-- ---------------------------------------------------------------------
-- Видове събития:
--   open      отворена покана (сканиране)
--   play      видеото тръгна
--   sound     гостът докосна, за да чуе звука
--   complete  видеото изгледано докрай
--   calendar  „Добави в календара"
--   map       „Как да стигна"
--   site      сайтът на организатора
--   share     „Сподели"
--   skip      прескочи клипа (кино режим)
--
-- Старата версия с два параметъра отпада, за да няма две функции с
-- едно име — PostgREST се обърква коя да извика.
drop function if exists public.log_invite_view(text, text);

create or replace function public.log_invite_view(
  p_invite   text,
  p_event    text default 'open',
  p_platform text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_event not in ('open', 'play', 'sound', 'complete',
                     'calendar', 'map', 'site', 'share', 'skip') then
    return;
  end if;

  -- само за съществуваща и публикувана покана
  if not exists (select 1 from public.video_invites v where v.id = p_invite and v.published) then
    return;
  end if;

  insert into public.invite_views (invite_id, event, platform)
  values (
    p_invite,
    p_event,
    case when p_platform in ('ios', 'android', 'desktop', 'other') then p_platform end
  );

  if p_event = 'open' then
    update public.video_invites set views = views + 1 where id = p_invite;
  elsif p_event = 'play' then
    update public.video_invites set plays = plays + 1 where id = p_invite;
  end if;
end;
$$;

grant execute on function public.log_invite_view(text, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- Отчет по дни (за нас / за клиента)
-- ---------------------------------------------------------------------
create or replace view public.invite_stats as
select
  v.id,
  v.title,
  v.views,
  v.plays,
  (select count(*) from public.invite_views w where w.invite_id = v.id and w.event = 'complete') as completions,
  (select max(w.created_at) from public.invite_views w where w.invite_id = v.id)                 as last_view
from public.video_invites v;

-- Отчетът е за нас, не за посетителя
revoke all on public.invite_stats from anon, authenticated;

-- ---------------------------------------------------------------------
-- Storage: публичен bucket, ако решим да качваме видеата тук
-- ---------------------------------------------------------------------
-- НЕ Е ЗАДЪЛЖИТЕЛЕН. Поканата на Койчев се раздава от самия сайт
-- (assets/invites/koychev/), затова bucket-ът е само за бъдещи клиенти.
-- Ако проектът не дава права върху storage схемата, блокът се пропуска
-- тихо, вместо да събори целия скрипт.
--
-- Внимание: безплатният план вдига до 50 MB на файл. По-голям клип или
-- се компресира, или се качва другаде (GitHub Pages / R2) и в base се
-- слага само адресът му.
do $$
begin
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('invites', 'invites', true, 52428800,
          array['video/mp4', 'video/webm', 'image/jpeg', 'image/png', 'image/webp'])
  on conflict (id) do update set
    public             = true,
    file_size_limit    = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

  execute 'drop policy if exists "invites public read" on storage.objects';
  execute 'create policy "invites public read" on storage.objects for select using (bucket_id = ''invites'')';
exception when insufficient_privilege or undefined_table then
  raise notice 'Storage bucket-ът е пропуснат (няма права) — не е нужен за поканата на Койчев.';
end $$;

-- Проверка:
-- select id, title, views, plays from public.video_invites;
-- select * from public.invite_stats;
