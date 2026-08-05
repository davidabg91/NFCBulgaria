-- =====================================================================
-- ЕЛКАБЕЛ — ЕДИНЕН SETUP: login акаунти + визитки (24 души)
-- =====================================================================
-- Заменя import-elkabel-profiles.sql + elkabel-accounts.sql.
-- profiles.user_id е NOT NULL → първо създаваме auth акаунта, после
-- вкарваме профила с неговия user_id. Изпълни в Supabase → SQL Editor.
-- Идемпотентно: пропуска съществуващ имейл; профилите са upsert по id.
-- Един транзакционен DO блок → при грешка се връща назад чисто.
--
-- СЛЕД него пусни company-admin-portal.sql (двата шефа).
-- =====================================================================

create extension if not exists pgcrypto;

-- WhatsApp колона (ако още я няма)
alter table public.profiles add column if not exists whatsapp text;

do $$
declare
  v_company uuid := 'e1cab511-0000-4000-8000-000000000001';
  r record;
  v_uid uuid;
begin
  for r in
    select * from (values
      ('vitaliy-kara', 'Виталий Василиевич Кара', 'Мениджър "Развойна дейност, иновации и внедряване"', '0888107616', 'v.kara@elkabel.bg', '0888107616', '0888107616', 'https://bg.linkedin.com/company/elkabel-official', 'v.kara@elkabel.bg', 'BgnGEj7nJd'),
      ('georgi-dimitrov', 'Георги Василев Димитров', 'Началник на отдел КК', '0887767502', 'otk@elkabel.bg', '0887767502', '', 'https://bg.linkedin.com/company/elkabel-official', 'otk@elkabel.bg', 'cH3wnfkhTh'),
      ('iliya-andonov', 'Илия Любчев Андонов', 'Директор дирекция "Развойна дейност и иновации"; Длъжностно лице по защита на данните', '0888120465', 'i.andonov@elkabel.bg', '', '', 'https://www.linkedin.com/in/iliya-andonov-61054957', 'i.andonov@elkabel.bg', 'TmFPXMPXLt'),
      ('kalinka-payova', 'Калинка Енчева Пайова', 'Н-к отдел Процес контрол', '0887502071', 'k.payova@elkabel.bg', '0887502071', '', 'https://bg.linkedin.com/company/elkabel-official', 'k.payova@elkabel.bg', 'SkwzQkKk72'),
      ('kaloyan-samokovliev', 'Калоян Ташков Самоковлиев', 'Главен инженер, предприятие', '0885538362', 'k.samokovliev@elkabel.bg', '0885538362', '0885538362', 'https://www.linkedin.com/in/kaloyan-samokovliev-02b440188', 'k.samokovliev@elkabel.bg', 'kUzfu5bdhq'),
      ('mariana-dobreva', 'Мариана Йонкова Добрева', 'Мениджър ЧР', '0887603311', 'm.dobreva@elkabel.bg', '0887603311', '0887603311', 'https://www.linkedin.com/in/mariana-dobreva-9b728b44', 'm.dobreva@elkabel.bg', 'RJaEWjsf2P'),
      ('petko-kurtev', 'Петко Радостинов Куртев', 'Началник отдел Доставки', '0883705560', 'p.kurtev@elkabel.bg', '', '0883705560', 'https://bg.linkedin.com/company/elkabel-official', 'p.kurtev@elkabel.bg', 'RzzuvEC6bv'),
      ('petya-todorova', 'Петя Иванова Тодорова', 'Началник отдел Проектиране и лимитиране', '0884232844', 'p.todorova@elkabel.bg', '', '', 'https://www.linkedin.com/in/petya-todorova-2a9b7834b', 'p.todorova@elkabel.bg', '3vuKHNQchE'),
      ('petya-nikolova', 'Петя Костадинова Николова', 'Търговски директор', '0888310155', 'p.nikolova@elkabel.bg', '', '', 'https://bg.linkedin.com/company/elkabel-official', 'p.nikolova@elkabel.bg', 'z5BkcjJTBR'),
      ('radoslav-slavov', 'Радослав Манолов Славов', 'Производствен директор и планиране', '0885838173', 'r.slavov@elkabel.bg', '', '', 'https://bg.linkedin.com/company/elkabel-official', 'r.slavov@elkabel.bg', 'vhU3EENxVT'),
      ('stanimir-shterionov', 'Станимир Георгиев Щерионов', 'Ръководител Изпитвателна лаборатория', '+35956800811', 'shterionov@elkabel.bg', '', '', 'https://bg.linkedin.com/company/elkabel-official', 'shterionov@elkabel.bg', 'k5xzFZ2XrQ'),
      ('stefan-velikov', 'Стефан Атанасов Великов', 'Търговски д/р местен пазар', '0888706947', 'svelikov@elkabel.bg', '0888706947', '', 'https://bg.linkedin.com/company/elkabel-official', 'svelikov@elkabel.bg', 'iGZ9DqD95e'),
      ('stoil-chilikov', 'Стоил Георгиев Чиликов', 'Мениджър отдел "Износ"', '0886701021', 'stoil.chilikov@elkabel.bg', '0886701021', '', 'https://bg.linkedin.com/company/elkabel-official', 'stoil.chilikov@elkabel.bg', 'wEYZugMQwB'),
      ('toni-shurelova', 'Тони Георгиева Шурелова', 'Главен счетоводител', '0887773279', 'toni@elkabel.bg', '0887773279', '', 'https://bg.linkedin.com/company/elkabel-official', 'toni@elkabel.bg', 'yCv6c3gAmZ'),
      ('tihomir-senkov', 'Тихомир Веселинов Сенков', 'Мениджър продажби и маркетинг', '0888951499', 't.senkov@elkabel.bg', '0888951499', '', 'https://bg.linkedin.com/company/elkabel-official', 't.senkov@elkabel.bg', 'GqsGXC9Yyi'),
      ('valentin-kostov', 'Валентин Петев Костов', 'Управител търговска база', '0887767190', 'v.kostov@elkabel.bg', '0887767190', '', 'https://bg.linkedin.com/company/elkabel-official', 'v.kostov@elkabel.bg', 'FRQeRZ9ESM'),
      ('dimitar-shopov', 'Димитър Георгиев Шопов', 'Управител търговска база', '0887787343', 'd.shopov@elkabel.bg', '', '', 'https://bg.linkedin.com/company/elkabel-official', 'd.shopov@elkabel.bg', 'AyDVBGxBAR'),
      ('aldin-kafedzhiev', 'Алдин Жеков Кафеджиев', 'Управител търговска база', '0889041716', 'a.jekov@elkabel.bg', '0889041716', '', 'https://bg.linkedin.com/company/elkabel-official', 'a.jekov@elkabel.bg', 'TDfdzCmZMA'),
      ('daniel-georgiev', 'Даниел Георгиев Георгиев', 'Управител търговска база', '0886220221', 'd.georgiev@elkabel.bg', '', '0886220221', 'https://www.linkedin.com/in/daniel-georgiev-933932197/', 'd.georgiev@elkabel.bg', 'PvwFucvYKg'),
      ('vasil-bozhinov', 'Васил Богомилов Божинов', 'Изпълнителен директор', '+35956800811', 'office@elkabel.bg', '', '', 'https://bg.linkedin.com/company/elkabel-official', 'v.bozhinov@elkabel.bg', 'Z7hxHdqcA7'),
      ('lyubomir-novakov', 'Любомир Чернев Новаков', 'Изпълнителен директор', '+35956800811', 'office@elkabel.bg', '', '', 'https://bg.linkedin.com/company/elkabel-official', 'l.novakov@elkabel.bg', 'zbvFYCxxsU'),
      ('tundzher-koch', 'Тунджер Коч', 'Главен Изпълнителен директор', '+35956800811', 'office@elkabel.bg', '', '', 'https://bg.linkedin.com/company/elkabel-official', 't.koch@elkabel.bg', 'P4WKd9S2hH'),
      ('albena-ignatova', 'Албена Иванова Игнатова', 'Асистент', '0885709490', 'a.ignatova@elkabel.bg', '0885709490', '0885709490', 'https://bg.linkedin.com/company/elkabel-official', 'a.ignatova@elkabel.bg', '3VrHXrxtAZ'),
      ('semnas-hasan', 'Семнас Назиф Хасан', 'Асистент', '0882801081', 'office@elkabel.bg', '0882801081', '0882801081', 'https://bg.linkedin.com/company/elkabel-official', 's.hasan@elkabel.bg', 'aYVveQug9s')
    ) as t(slug, name, title, phone, email, viber, whatsapp, linkedin, login_email, pw)
  loop
    -- 1) auth акаунт (ако липсва)
    select id into v_uid from auth.users where email = r.login_email;
    if v_uid is null then
      v_uid := gen_random_uuid();
      insert into auth.users
        (instance_id, id, aud, role, email, encrypted_password,
         email_confirmed_at, created_at, updated_at,
         raw_app_meta_data, raw_user_meta_data,
         confirmation_token, recovery_token, email_change_token_new, email_change)
      values
        ('00000000-0000-0000-0000-000000000000', v_uid, 'authenticated', 'authenticated',
         r.login_email, crypt(r.pw, gen_salt('bf')),
         now(), now(), now(),
         '{"provider":"email","providers":["email"]}', '{}',
         '', '', '', '');
      insert into auth.identities
        (id, user_id, provider_id, identity_data, provider,
         created_at, updated_at, last_sign_in_at)
      values
        (gen_random_uuid(), v_uid, v_uid::text,
         json_build_object('sub', v_uid::text, 'email', r.login_email)::jsonb, 'email',
         now(), now(), now());
    else
      -- акаунтът вече съществува → синхронизираме паролата с тази от CSV
      update auth.users
      set encrypted_password = crypt(r.pw, gen_salt('bf')),
          email_confirmed_at = coalesce(email_confirmed_at, now()),
          updated_at = now()
      where id = v_uid;
    end if;

    -- 2) визитката с неговия user_id
    insert into public.profiles
      (id, user_id, name, title, company, phone, email, viber, whatsapp,
       linkedin, facebook, website, google_maps, company_id)
    values
      (r.slug, v_uid, r.name, r.title, 'Елкабел АД', r.phone, r.email, r.viber, r.whatsapp,
       r.linkedin, 'https://www.facebook.com/elkabel.bg', 'www.elkabel.bg', 'https://www.google.com/maps/search/?api=1&query=%D0%95%D0%BB%D0%BA%D0%B0%D0%B1%D0%B5%D0%BB+%D0%91%D1%83%D1%80%D0%B3%D0%B0%D1%81+%D1%83%D0%BB.+%D0%9E%D0%B4%D1%80%D0%B8%D0%BD+15', v_company)
    on conflict (id) do update set
      user_id     = excluded.user_id,
      name        = excluded.name,
      title       = excluded.title,
      company     = excluded.company,
      phone       = excluded.phone,
      email       = excluded.email,
      viber       = excluded.viber,
      whatsapp    = excluded.whatsapp,
      linkedin    = excluded.linkedin,
      facebook    = excluded.facebook,
      website     = excluded.website,
      google_maps = excluded.google_maps,
      company_id  = excluded.company_id;
  end loop;
end $$;

-- Проверка: 24 реда, всички с user_id
-- select id, name, user_id from public.profiles
--   where company_id = 'e1cab511-0000-4000-8000-000000000001' order by name;
