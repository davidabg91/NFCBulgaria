-- =====================================================================
-- ЕЛКАБЕЛ — бизнес оферта (20€/мес, 25 места, първи месец безплатно)
-- =====================================================================
-- ПУСНИ СЛЕД billing-plans-upgrade.sql.
-- Задава офертата директно (SQL Editor = service role, заобикаля
-- admin проверката). След това шефът (Васил) вижда бутон „Активирай“
-- в портала и плаща с карта — първият месец е 0 € (триал).
-- =====================================================================

insert into public.business_offers (company_id, seats, monthly_price_cents, trial, label)
values ('e1cab511-0000-4000-8000-000000000001', 25, 2000, true, 'Бизнес план — ЕЛКАБЕЛ АД')
on conflict (company_id) do update set
  seats               = excluded.seats,
  monthly_price_cents = excluded.monthly_price_cents,
  trial               = excluded.trial,
  label               = excluded.label,
  updated_at          = now();
