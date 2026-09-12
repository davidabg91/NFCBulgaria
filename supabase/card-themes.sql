-- =====================================================================
-- Фонове на визитката — избор и покупка (9,99 € еднократно за фон)
-- =====================================================================
-- Изпълни в Supabase → SQL Editor. Идемпотентно.
--
-- Модел:
--   * profiles.theme_id            — кой фон е активен на визитката
--   * theme_purchases              — кои платени фона е купил потребителят
--   * Безплатният фон ('midnight') е винаги разрешен, без покупка.
--   * Записът в theme_purchases се прави САМО от edge функцията
--     theme-checkout със service ключ, след потвърдено плащане в Stripe.
--     Клиентският ключ няма право да пише в таблицата.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Активният фон върху профила
-- ---------------------------------------------------------------------
alter table public.profiles
  add column if not exists theme_id text not null default 'midnight';

create index if not exists profiles_theme_idx on public.profiles (theme_id);


-- ---------------------------------------------------------------------
-- 2. Купените фонове
-- ---------------------------------------------------------------------
create table if not exists public.theme_purchases (
  user_id           uuid not null references auth.users (id) on delete cascade,
  theme_id          text not null,
  amount_cents      int  not null default 999,
  currency          text not null default 'eur',
  stripe_session_id text unique,
  created_at        timestamptz not null default now(),
  primary key (user_id, theme_id)
);

create index if not exists theme_purchases_created_idx
  on public.theme_purchases (created_at desc);

alter table public.theme_purchases enable row level security;

-- Потребителят вижда САМО своите покупки. Няма INSERT/UPDATE/DELETE
-- policy → никой клиентски ключ не може да си „подари" фон.
drop policy if exists "read own theme purchases" on public.theme_purchases;
create policy "read own theme purchases"
  on public.theme_purchases
  for select
  using (user_id = auth.uid());


-- ---------------------------------------------------------------------
-- 3. Кои фонове притежавам + кой ми е активен
-- ---------------------------------------------------------------------
-- Връща един ред дори без покупки, за да знае UI-ът какво да покаже.
create or replace function public.get_my_themes()
returns table (
  active_theme text,
  owned        text[]
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_active text;
begin
  if auth.uid() is null then
    raise exception 'Няма активна сесия.';
  end if;

  select coalesce(p.theme_id, 'midnight') into v_active
  from public.profiles p
  where p.user_id = auth.uid()
  limit 1;

  return query
  select
    coalesce(v_active, 'midnight'),
    coalesce(
      (select array_agg(tp.theme_id order by tp.theme_id)
         from public.theme_purchases tp
        where tp.user_id = auth.uid()),
      '{}'::text[]
    );
end;
$$;

revoke all on function public.get_my_themes() from public;
grant execute on function public.get_my_themes() to authenticated;


-- ---------------------------------------------------------------------
-- 4. Смяна на активния фон
-- ---------------------------------------------------------------------
-- Разрешава само безплатния фон или такъв, който потребителят е купил.
-- Проверката е тук, а не в браузъра — иначе всеки може да си сложи
-- платен фон през конзолата.
create or replace function public.set_my_theme(p_theme_id text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_theme text := nullif(trim(p_theme_id), '');
  v_owned boolean;
  v_rows  int;
begin
  if auth.uid() is null then
    return json_build_object('ok', false, 'message', 'Няма активна сесия.');
  end if;

  if v_theme is null then
    return json_build_object('ok', false, 'message', 'Не е избран фон.');
  end if;

  if v_theme <> 'midnight' then
    select exists (
      select 1 from public.theme_purchases tp
      where tp.user_id = auth.uid() and tp.theme_id = v_theme
    ) into v_owned;

    if not v_owned then
      return json_build_object('ok', false, 'code', 'not_owned',
        'message', 'Този фон още не е купен.');
    end if;
  end if;

  update public.profiles
  set theme_id = v_theme
  where user_id = auth.uid();

  get diagnostics v_rows = row_count;

  if v_rows = 0 then
    return json_build_object('ok', false,
      'message', 'Този акаунт няма визитка, на която да се сложи фон.');
  end if;

  return json_build_object('ok', true, 'theme_id', v_theme,
    'message', 'Фонът е сменен.');
end;
$$;

revoke all on function public.set_my_theme(text) from public;
grant execute on function public.set_my_theme(text) to authenticated;


-- ---------------------------------------------------------------------
-- 5. Ръчно подаряване на фон (поддръжка / банков превод)
-- ---------------------------------------------------------------------
-- Само за админ. Полезно, когато някой плати по друг начин.
create or replace function public.admin_grant_theme(
  p_profile_id text,
  p_theme_id   text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid;
begin
  if not public.is_app_admin() then
    return json_build_object('ok', false, 'message', 'Нямате администраторски права.');
  end if;

  select p.user_id into v_uid from public.profiles p where p.id = p_profile_id;
  if v_uid is null then
    return json_build_object('ok', false, 'message', 'Няма такъв профил (или е без акаунт).');
  end if;

  insert into public.theme_purchases (user_id, theme_id, amount_cents, stripe_session_id)
  values (v_uid, p_theme_id, 0, null)
  on conflict (user_id, theme_id) do nothing;

  return json_build_object('ok', true,
    'message', format('Фонът %s е добавен на %s.', p_theme_id, p_profile_id));
end;
$$;

revoke all on function public.admin_grant_theme(text, text) from public;
grant execute on function public.admin_grant_theme(text, text) to authenticated;


-- ---------------------------------------------------------------------
-- 6. Проверка
-- ---------------------------------------------------------------------
-- select * from public.get_my_themes();
-- select theme_id, count(*) from public.profiles group by theme_id;
-- select * from public.theme_purchases order by created_at desc;


-- ---------------------------------------------------------------------
-- 7. Справка за админ панела — кой какви фонове е купил
-- ---------------------------------------------------------------------
-- Нарочно живее тук, а не в admin-insights.sql, за да не се налага
-- да пускаш пак другия файл.
create or replace function public.admin_theme_sales()
returns json
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_sales json;
  v_usage json;
begin
  if not public.is_app_admin() then
    return json_build_object('ok', false, 'message', 'Нямате администраторски права.');
  end if;

  select coalesce(json_agg(x order by x.created_at desc), '[]'::json) into v_sales
  from (
    select tp.created_at, tp.theme_id, tp.amount_cents, tp.currency,
           p.id as profile_id, p.name as profile_name, p.company,
           u.email::text as user_email,
           (p.theme_id = tp.theme_id) as is_active,
           (tp.stripe_session_id is null) as granted_manually
    from public.theme_purchases tp
    left join public.profiles p on p.user_id = tp.user_id
    left join auth.users    u on u.id = tp.user_id
    order by tp.created_at desc
    limit 500
  ) x;

  select coalesce(json_agg(y order by y.cnt desc), '[]'::json) into v_usage
  from (
    select p.theme_id, count(*) as cnt
    from public.profiles p
    where p.theme_id is not null
    group by p.theme_id
  ) y;

  return json_build_object(
    'ok', true,
    'sales', v_sales,
    'usage', v_usage,
    'revenue_cents', (select coalesce(sum(amount_cents), 0) from public.theme_purchases),
    'sold_count',    (select count(*) from public.theme_purchases where stripe_session_id is not null)
  );
end;
$$;

revoke all on function public.admin_theme_sales() from public;
grant execute on function public.admin_theme_sales() to authenticated;
