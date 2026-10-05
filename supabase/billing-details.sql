-- =====================================================================
-- Данни за фактура на фирмата (получател във фактурите от Stripe)
-- =====================================================================
-- Попълват се веднъж от шефа преди първото плащане. create-checkout-session
-- ги чете сървърно и ги записва в Stripe клиента (име, адрес, ЕИК, МОЛ,
-- ДДС №), така че излизат на всяка фактура — първата и подновяванията.
--
-- Ключ е company_id: един запис на фирма, общ за всичките ѝ шефове.
-- Достъпът е само през RPC-тата долу (без директни client политики).
-- Идемпотентно.
-- =====================================================================

create table if not exists public.company_billing (
  company_id    uuid primary key,
  company_name  text not null,
  eik           text not null,
  vat_number    text,
  address       text not null,
  city          text not null,
  postal_code   text,
  mol           text not null,
  email         text,
  updated_by    uuid,
  updated_at    timestamptz not null default now()
);

alter table public.company_billing enable row level security;


-- Фирмата на текущия потребител (първият профил с company_id)
create or replace function public.my_company_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select p.company_id from public.profiles p
  where p.user_id = auth.uid() and p.company_id is not null
  limit 1;
$$;

revoke all on function public.my_company_id() from public;
grant execute on function public.my_company_id() to authenticated;


create or replace function public.get_my_billing_details()
returns setof public.company_billing
language sql
stable
security definer
set search_path = public
as $$
  select b.* from public.company_billing b
  where b.company_id = public.my_company_id();
$$;

revoke all on function public.get_my_billing_details() from public;
grant execute on function public.get_my_billing_details() to authenticated;


create or replace function public.save_my_billing_details(
  p_company_name text,
  p_eik          text,
  p_vat_number   text,
  p_address      text,
  p_city         text,
  p_postal_code  text,
  p_mol          text,
  p_email        text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company uuid := public.my_company_id();
  v_eik     text := regexp_replace(coalesce(p_eik, ''), '\s', '', 'g');
  v_vat     text := upper(regexp_replace(coalesce(p_vat_number, ''), '\s', '', 'g'));
begin
  if auth.uid() is null then
    return json_build_object('ok', false, 'message', 'Няма активна сесия.');
  end if;
  if v_company is null then
    return json_build_object('ok', false, 'message', 'Профилът ви не е свързан с фирма.');
  end if;
  if nullif(trim(p_company_name), '') is null or nullif(trim(p_address), '') is null
     or nullif(trim(p_city), '') is null or nullif(trim(p_mol), '') is null then
    return json_build_object('ok', false, 'message', 'Попълнете всички задължителни полета.');
  end if;
  if v_eik !~ '^[0-9]{9}([0-9]{4})?$' then
    return json_build_object('ok', false, 'message', 'ЕИК трябва да е 9 или 13 цифри.');
  end if;
  if v_vat <> '' and v_vat !~ '^BG[0-9]{9,10}$' then
    return json_build_object('ok', false, 'message', 'ДДС номерът е във вида BG123456789.');
  end if;

  insert into public.company_billing
    (company_id, company_name, eik, vat_number, address, city, postal_code, mol, email, updated_by, updated_at)
  values
    (v_company, trim(p_company_name), v_eik, nullif(v_vat, ''), trim(p_address), trim(p_city),
     nullif(trim(coalesce(p_postal_code, '')), ''), trim(p_mol), nullif(trim(coalesce(p_email, '')), ''),
     auth.uid(), now())
  on conflict (company_id) do update set
    company_name = excluded.company_name, eik = excluded.eik, vat_number = excluded.vat_number,
    address = excluded.address, city = excluded.city, postal_code = excluded.postal_code,
    mol = excluded.mol, email = excluded.email, updated_by = excluded.updated_by, updated_at = now();

  return json_build_object('ok', true);
end;
$$;

revoke all on function public.save_my_billing_details(text, text, text, text, text, text, text, text) from public;
grant execute on function public.save_my_billing_details(text, text, text, text, text, text, text, text) to authenticated;
