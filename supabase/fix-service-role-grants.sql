-- =====================================================================
-- Възстановява правата на service_role върху public схемата
-- =====================================================================
-- На този проект service_role беше без GRANT-ове върху таблиците, затова
-- edge функциите получаваха „permission denied for table profiles" и
-- отключването след плащане не можеше да запише нищо.
--
-- Изпълни веднъж в Supabase → SQL Editor. Безопасно за повторно пускане.
-- =====================================================================

grant usage on schema public to service_role;

grant all privileges on all tables    in schema public to service_role;
grant all privileges on all sequences in schema public to service_role;
grant all privileges on all functions in schema public to service_role;

-- Бъдещи таблици/секвенции също да са достъпни за service_role.
alter default privileges in schema public grant all on tables    to service_role;
alter default privileges in schema public grant all on sequences to service_role;
alter default privileges in schema public grant all on functions to service_role;
