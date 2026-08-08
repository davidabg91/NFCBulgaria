-- =====================================================================
-- Нови функции по визитните профили
-- =====================================================================
-- 1) Работно време (по избор на клиента) + статус "на работа"
-- 2) Бутон "Сподели профила" (по избор на клиента)
-- 3) Форма "Оставете запитване" — съобщение + имейл към лийда
--
-- Изпълни веднъж в Supabase → SQL Editor. Безопасно за повторно пускане.
-- =====================================================================

-- profiles: настройки за работно време и споделяне
alter table public.profiles
  add column if not exists working_hours text,                     -- JSON: {"days":[1,2,3,4,5],"from":"09:00","to":"18:00"}
  add column if not exists hours_enabled boolean not null default false,
  add column if not exists share_enabled boolean not null default false;

-- leads: разширяваме с имейл и съобщение (за формата "Оставете запитване")
alter table public.leads
  add column if not exists client_email   text,
  add column if not exists client_message text;
