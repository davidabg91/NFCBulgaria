-- =====================================================================
-- Липсващи колони в profiles
-- =====================================================================
-- Формата за редакция на профил (dashboard.html) записва тези три полета,
-- а публичната визитка (profile.html) ги чете — но колоните ги нямаше,
-- затова запазването гърмеше с „Could not find the 'bio' column".
--
-- Изпълни веднъж в Supabase → SQL Editor. Безопасно за повторно пускане.
-- =====================================================================

alter table public.profiles
  add column if not exists bio          text,
  add column if not exists google_maps  text,
  add column if not exists company_logo text;
