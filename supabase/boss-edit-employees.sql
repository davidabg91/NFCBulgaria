-- =====================================================================
-- Шефът редактира визитките на служителите си от своето табло
-- =====================================================================
-- Право има:
--   * фирмен админ (company_admins) — за всяка визитка със същия company_id;
--   * класически шеф — за визитките с parent_boss_id = него.
--
-- Нарочно е RPC, а не по-широка RLS политика: обновяват се САМО полетата
-- със съдържание на визитката. user_id, company_id, id, шефските флагове и
-- платените фонове (theme_id) не могат да се пипнат оттук — иначе шеф би
-- могъл да „прехвърли“ чужд профил на себе си.
--
-- Липсващ ключ в p_data = полето не се променя. Идемпотентно.
-- =====================================================================

create or replace function public.can_edit_profile(p_profile_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = p_profile_id
      and p.user_id is distinct from auth.uid()       -- своята си се пише нормално
      and (
        (p.company_id is not null and p.company_id = public.my_company_admin_id())
        or p.parent_boss_id = auth.uid()
      )
  );
$$;

revoke all on function public.can_edit_profile(text) from public;
grant execute on function public.can_edit_profile(text) to authenticated;


create or replace function public.boss_update_employee_profile(
  p_profile_id text,
  p_data       jsonb
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  d jsonb := coalesce(p_data, '{}'::jsonb);
begin
  if auth.uid() is null then
    return json_build_object('ok', false, 'message', 'Няма активна сесия.');
  end if;
  if not public.can_edit_profile(p_profile_id) then
    return json_build_object('ok', false, 'message', 'Нямате право да редактирате тази визитка.');
  end if;
  if d ? 'name' and nullif(trim(d->>'name'), '') is null then
    return json_build_object('ok', false, 'message', 'Името не може да е празно.');
  end if;

  update public.profiles p set
    name          = case when d ? 'name'          then trim(d->>'name')        else p.name end,
    title         = case when d ? 'title'         then d->>'title'             else p.title end,
    company       = case when d ? 'company'       then d->>'company'           else p.company end,
    phone         = case when d ? 'phone'         then d->>'phone'             else p.phone end,
    email         = case when d ? 'email'         then d->>'email'             else p.email end,
    viber         = case when d ? 'viber'         then d->>'viber'             else p.viber end,
    whatsapp      = case when d ? 'whatsapp'      then d->>'whatsapp'          else p.whatsapp end,
    linkedin      = case when d ? 'linkedin'      then d->>'linkedin'          else p.linkedin end,
    facebook      = case when d ? 'facebook'      then d->>'facebook'          else p.facebook end,
    instagram     = case when d ? 'instagram'     then d->>'instagram'         else p.instagram end,
    website       = case when d ? 'website'       then d->>'website'           else p.website end,
    google_maps   = case when d ? 'google_maps'   then d->>'google_maps'       else p.google_maps end,
    bio           = case when d ? 'bio'           then d->>'bio'               else p.bio end,
    company_logo  = case when d ? 'company_logo'  then d->>'company_logo'      else p.company_logo end,
    avatar_url    = case when d ? 'avatar_url'    then d->>'avatar_url'        else p.avatar_url end,
    share_enabled = case when d ? 'share_enabled' then (d->>'share_enabled')::boolean else p.share_enabled end,
    hours_enabled = case when d ? 'hours_enabled' then (d->>'hours_enabled')::boolean else p.hours_enabled end,
    working_hours = case when d ? 'working_hours' then d->>'working_hours'     else p.working_hours end,
    i18n          = case when d ? 'i18n'          then nullif(d->'i18n', 'null'::jsonb) else p.i18n end,
    updated_at    = now()
  where p.id = p_profile_id;

  return json_build_object('ok', true);
end;
$$;

revoke all on function public.boss_update_employee_profile(text, jsonb) from public;
grant execute on function public.boss_update_employee_profile(text, jsonb) to authenticated;
