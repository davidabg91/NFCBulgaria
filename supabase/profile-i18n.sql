-- =====================================================================
-- Ръчни преводи на визитка (по избор) — колона profiles.i18n
-- =====================================================================
-- profile.html вече превежда автоматично:
--   1) името се транслитерира (Любомир Чернев Новаков → Lyubomir Chernev Novakov)
--   2) длъжността минава през вградения речник (Изпълнителен директор →
--      Executive Director / Geschäftsführer / Director executiv)
--   3) фирмата се транслитерира (Елкабел АД → Elkabel AD)
--
-- Тази колона е за случаите, когато искаш ТОЧЕН превод вместо
-- автоматичния — нестандартна длъжност, утвърдено име на латиница,
-- или превод на кратката биография (bio НЕ се превежда автоматично).
-- Каквото е записано тук, бие речника.
--
-- Изпълни в Supabase → SQL Editor. Безопасно е да се пусне повторно.
-- =====================================================================

alter table public.profiles add column if not exists i18n jsonb;

comment on column public.profiles.i18n is
  'Ръчни преводи по език: {"en":{"name":"...","title":"...","company":"...","bio":"..."},"de":{...},"ro":{...}}. Празните/липсващи полета падат към автоматичния превод.';

-- ---------------------------------------------------------------------
-- Пример (разкоментирай и промени по нужда):
-- ---------------------------------------------------------------------
-- update public.profiles
-- set i18n = jsonb_build_object(
--   'en', jsonb_build_object(
--     'title',   'Chief Executive Officer',
--     'company', 'Elkabel JSC',
--     'bio',     'Short bio in English.'
--   ),
--   'de', jsonb_build_object(
--     'title',   'Vorstandsvorsitzender',
--     'company', 'Elkabel AG'
--   ),
--   'ro', jsonb_build_object(
--     'title',   'Director general executiv'
--   )
-- )
-- where id = 'lyubomir-novakov';

-- Проверка:
-- select id, name, i18n from public.profiles where i18n is not null;
