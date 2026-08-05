-- =====================================================================
-- ЕЛКАБЕЛ — login акаунти за 24-те визитки
-- =====================================================================
-- ПУСНИ СЛЕД import-elkabel-profiles.sql (профилите трябва вече да ги има).
-- Изпълни в Supabase → SQL Editor. Идемпотентно (пропуска съществуващ имейл).
--
-- !!! СМOKE ТЕСТ ПРЕДИ МАСОВО: пусни целия блок, после влез в login.html с
--     един акаунт от списъка, за да потвърдиш, че auth схемата пасва. !!!
-- =====================================================================

create extension if not exists pgcrypto;

do $$
declare
  r record;
  v_uid uuid;
begin
  for r in
    select * from (values
      ('v.kara@elkabel.bg', 'HahWP8ypGu', 'vitaliy-kara'),
      ('otk@elkabel.bg', 'HJ8sJ4BCan', 'georgi-dimitrov'),
      ('i.andonov@elkabel.bg', 'P4uiY3fQEE', 'iliya-andonov'),
      ('k.payova@elkabel.bg', 'XdnBnsQdKU', 'kalinka-payova'),
      ('k.samokovliev@elkabel.bg', '324nSy8fYh', 'kaloyan-samokovliev'),
      ('m.dobreva@elkabel.bg', 'UfQXaf55uW', 'mariana-dobreva'),
      ('p.kurtev@elkabel.bg', 'qCJwdBEGNz', 'petko-kurtev'),
      ('p.todorova@elkabel.bg', 'TMZFRyz3BX', 'petya-todorova'),
      ('p.nikolova@elkabel.bg', '5nADsu9xBt', 'petya-nikolova'),
      ('r.slavov@elkabel.bg', '3TWQYhBYNM', 'radoslav-slavov'),
      ('shterionov@elkabel.bg', 'y9GY5bgnkU', 'stanimir-shterionov'),
      ('svelikov@elkabel.bg', 'FE9BdgQuaS', 'stefan-velikov'),
      ('stoil.chilikov@elkabel.bg', 'UMtccmvCDn', 'stoil-chilikov'),
      ('toni@elkabel.bg', 'pykMYChtee', 'toni-shurelova'),
      ('t.senkov@elkabel.bg', 'HrwpAk8pNk', 'tihomir-senkov'),
      ('v.kostov@elkabel.bg', 'MDUrGu23NS', 'valentin-kostov'),
      ('d.shopov@elkabel.bg', 'cP9AbhAH9E', 'dimitar-shopov'),
      ('a.jekov@elkabel.bg', 'C89kSTEufT', 'aldin-kafedzhiev'),
      ('d.georgiev@elkabel.bg', 'Td7dJgbwjU', 'daniel-georgiev'),
      ('v.bozhinov@elkabel.bg', 'MnxMynqZ6g', 'vasil-bozhinov'),
      ('l.novakov@elkabel.bg', 'ZsQEjpgaeH', 'lyubomir-novakov'),
      ('t.koch@elkabel.bg', 'EBJtGBTJLS', 'tundzher-koch'),
      ('a.ignatova@elkabel.bg', 'BShmPp9Q3Z', 'albena-ignatova'),
      ('s.hasan@elkabel.bg', 'yD9Ehdv2dX', 'semnas-hasan')
    ) as t(email, pw, slug)
  loop
    select id into v_uid from auth.users where email = r.email;
    if v_uid is null then
      v_uid := gen_random_uuid();
      insert into auth.users
        (instance_id, id, aud, role, email, encrypted_password,
         email_confirmed_at, created_at, updated_at,
         raw_app_meta_data, raw_user_meta_data,
         confirmation_token, recovery_token, email_change_token_new, email_change)
      values
        ('00000000-0000-0000-0000-000000000000', v_uid, 'authenticated', 'authenticated',
         r.email, crypt(r.pw, gen_salt('bf')),
         now(), now(), now(),
         '{"provider":"email","providers":["email"]}', '{}',
         '', '', '', '');
      insert into auth.identities
        (id, user_id, provider_id, identity_data, provider,
         created_at, updated_at, last_sign_in_at)
      values
        (gen_random_uuid(), v_uid, v_uid::text,
         json_build_object('sub', v_uid::text, 'email', r.email)::jsonb, 'email',
         now(), now(), now());
    end if;
    -- връзваме визитката за този login
    update public.profiles set user_id = v_uid where id = r.slug;
  end loop;
end $$;

-- Проверка: всички 24 трябва да имат user_id
-- select id, name, user_id from public.profiles
-- where company_id = 'e1cab511-0000-4000-8000-000000000001' order by name;
