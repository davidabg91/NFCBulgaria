-- =====================================================================
-- Плащания по абонаменти + данните за фактура — за админ панела
-- =====================================================================
-- Stripe таксува картата и праща само разписка. Фактурата я издаваме
-- ръчно от Revolut, затова админът трябва да вижда на едно място:
-- кой е платил, колко и кога, данните на фирмата за фактурата и дали
-- фактурата вече е издадена.
--
-- Редовете се пишат от stripe-webhook (invoice.paid) със SERVICE_KEY.
-- Четене/отбелязване — само през админ RPC-тата долу. Идемпотентно.
-- =====================================================================

create table if not exists public.subscription_payments (
  id                 bigserial primary key,
  stripe_invoice_id  text not null unique,
  company_id         uuid not null,
  plan               text,
  interval           text,
  amount_cents       int  not null,
  currency           text not null default 'eur',
  paid_at            timestamptz not null default now(),
  period_start       timestamptz,
  period_end         timestamptz,
  receipt_url        text,
  invoiced           boolean not null default false,  -- издадена фактура в Revolut
  invoice_note       text,                            -- напр. номерът на фактурата
  created_at         timestamptz not null default now()
);

create index if not exists subscription_payments_company_idx
  on public.subscription_payments (company_id, paid_at desc);

alter table public.subscription_payments enable row level security;
grant select, insert, update on public.subscription_payments to service_role;
grant usage, select on sequence public.subscription_payments_id_seq to service_role;


-- Всички плащания с данните за фактура на фирмата (най-новите първо)
create or replace function public.admin_list_payments()
returns table (
  id            bigint,
  paid_at       timestamptz,
  company_id    uuid,
  company_label text,
  plan          text,
  plan_interval text,
  amount_cents  int,
  currency      text,
  period_start  timestamptz,
  period_end    timestamptz,
  receipt_url   text,
  invoiced      boolean,
  invoice_note  text,
  billing       json
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_app_admin() then
    raise exception 'Нямате администраторски права.';
  end if;

  return query
  select
    sp.id, sp.paid_at, sp.company_id,
    coalesce(cb.company_name,
             (select p.company from public.profiles p
               where p.company_id = sp.company_id and coalesce(p.company, '') <> ''
               limit 1)) as company_label,
    sp.plan, sp.interval, sp.amount_cents, sp.currency,
    sp.period_start, sp.period_end, sp.receipt_url,
    sp.invoiced, sp.invoice_note,
    case when cb.company_id is null then null else json_build_object(
      'company_name', cb.company_name, 'eik', cb.eik, 'vat_number', cb.vat_number,
      'address', cb.address, 'city', cb.city, 'postal_code', cb.postal_code,
      'mol', cb.mol, 'email', cb.email) end as billing
  from public.subscription_payments sp
  left join public.company_billing cb on cb.company_id = sp.company_id
  order by sp.paid_at desc
  limit 500;
end;
$$;

revoke all on function public.admin_list_payments() from public;
grant execute on function public.admin_list_payments() to authenticated;


-- Отбелязва, че за плащането е издадена фактура (и по желание номера ѝ)
create or replace function public.admin_mark_payment_invoiced(
  p_id       bigint,
  p_invoiced boolean,
  p_note     text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_app_admin() then
    return json_build_object('ok', false, 'message', 'Нямате администраторски права.');
  end if;

  update public.subscription_payments
  set invoiced = coalesce(p_invoiced, false),
      invoice_note = nullif(trim(coalesce(p_note, '')), '')
  where id = p_id;

  return json_build_object('ok', found);
end;
$$;

revoke all on function public.admin_mark_payment_invoiced(bigint, boolean, text) from public;
grant execute on function public.admin_mark_payment_invoiced(bigint, boolean, text) to authenticated;
