-- Поръчки на NFC табели/поставки от страницата modeli-razmeri.html
-- Посетителят не чете и не пише директно в таблицата — само през
-- submit_sign_order(), която проверява полетата и сама смята цената.
-- Логата се качват в bucket „sign-logos“ (публичен, само качване за anon).

create table if not exists public.sign_orders (
  id              bigint generated always as identity primary key,
  created_at      timestamptz not null default now(),
  status          text not null default 'new'
                  check (status in ('new', 'in_progress', 'done', 'cancelled')),
  model           text not null,
  size            text not null,
  quantity        int  not null check (quantity between 1 and 1000),
  unit_price      numeric(10,2) not null,
  total_price     numeric(10,2) not null,
  customer_name   text not null,
  customer_phone  text not null,
  customer_email  text not null,
  delivery_city   text,
  delivery_address text,
  target_link     text,
  design_notes    text,
  logo_paths      text[] not null default '{}',
  wants_invoice   boolean not null default false,
  invoice_company text,
  invoice_eik     text,
  invoice_vat     text,
  invoice_mol     text,
  invoice_address text,
  admin_note      text
);

alter table public.sign_orders enable row level security;
-- Без политики: anon/authenticated нямат директен достъп, всичко минава през функциите.
grant all on public.sign_orders to service_role;

-- Цени за единичен брой (същите като в modeli-razmeri.html)
create or replace function public.sign_unit_price(p_model text, p_size text)
returns numeric
language sql
immutable
as $$
  select case
    when p_model in ('stela-pro', 'panorama-pro') then
      case p_size when 'A4' then 25 when 'A5' then 23 when 'A6' then 20 end
    when p_model in ('stela', 'panorama') then
      case p_size when 'A4' then 30 when 'A5' then 28 when 'A6' then 25 end
    when p_model = 'kompakt-t' then
      case p_size when 'A5' then 20 when 'A6' then 17 end
  end::numeric;
$$;

create or replace function public.submit_sign_order(p jsonb)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_model text := trim(p->>'model');
  v_size  text := upper(trim(p->>'size'));
  v_qty   int  := coalesce((p->>'quantity')::int, 1);
  v_price numeric;
  v_invoice boolean := coalesce((p->>'wants_invoice')::boolean, false);
  v_logos text[];
  v_id bigint;
begin
  v_price := public.sign_unit_price(v_model, v_size);
  if v_price is null then
    raise exception 'Невалиден модел или размер';
  end if;
  if v_qty < 1 or v_qty > 1000 then
    raise exception 'Невалидно количество';
  end if;
  if coalesce(trim(p->>'customer_name'), '') = ''
     or coalesce(trim(p->>'customer_phone'), '') = ''
     or coalesce(trim(p->>'customer_email'), '') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Липсват име, телефон или валиден имейл';
  end if;
  if v_invoice and (coalesce(trim(p->>'invoice_company'), '') = ''
                    or coalesce(trim(p->>'invoice_eik'), '') = '') then
    raise exception 'За фактура са нужни име на фирма и ЕИК';
  end if;

  select coalesce(array_agg(x), '{}') into v_logos
  from (
    select left(value, 300) as x
    from jsonb_array_elements_text(coalesce(p->'logo_paths', '[]'::jsonb))
    limit 5
  ) s;

  insert into public.sign_orders (
    model, size, quantity, unit_price, total_price,
    customer_name, customer_phone, customer_email,
    delivery_city, delivery_address, target_link, design_notes, logo_paths,
    wants_invoice, invoice_company, invoice_eik, invoice_vat, invoice_mol, invoice_address
  ) values (
    v_model, v_size, v_qty, v_price, v_price * v_qty,
    left(trim(p->>'customer_name'), 200), left(trim(p->>'customer_phone'), 50),
    left(trim(p->>'customer_email'), 200),
    left(p->>'delivery_city', 200), left(p->>'delivery_address', 500),
    left(p->>'target_link', 1000), left(p->>'design_notes', 4000), v_logos,
    v_invoice,
    case when v_invoice then left(p->>'invoice_company', 300) end,
    case when v_invoice then left(p->>'invoice_eik', 30) end,
    case when v_invoice then left(p->>'invoice_vat', 30) end,
    case when v_invoice then left(p->>'invoice_mol', 200) end,
    case when v_invoice then left(p->>'invoice_address', 500) end
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.submit_sign_order(jsonb) from public;
grant execute on function public.submit_sign_order(jsonb) to anon, authenticated;

-- Админ: списък и смяна на статус
create or replace function public.admin_list_sign_orders(p_limit int default 300)
returns setof public.sign_orders
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_app_admin() then
    return;
  end if;
  return query
  select * from public.sign_orders
  order by created_at desc
  limit greatest(1, least(coalesce(p_limit, 300), 2000));
end;
$$;

revoke all on function public.admin_list_sign_orders(int) from public;
grant execute on function public.admin_list_sign_orders(int) to authenticated;

create or replace function public.admin_update_sign_order(p_id bigint, p_status text, p_note text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_app_admin() then
    raise exception 'Нямате достъп';
  end if;
  update public.sign_orders
     set status = coalesce(p_status, status),
         admin_note = coalesce(p_note, admin_note)
   where id = p_id;
end;
$$;

revoke all on function public.admin_update_sign_order(bigint, text, text) from public;
grant execute on function public.admin_update_sign_order(bigint, text, text) to authenticated;

-- Хранилище за логата: публично четене по точен адрес, качване от всеки,
-- без листване и без триене/презаписване.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('sign-logos', 'sign-logos', true, 10485760,
        array['image/png', 'image/jpeg', 'image/webp', 'image/svg+xml', 'application/pdf'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "sign_logos_upload" on storage.objects;
create policy "sign_logos_upload" on storage.objects
  for insert to anon, authenticated
  with check (bucket_id = 'sign-logos');
