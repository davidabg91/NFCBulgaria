-- =====================================================================
-- Пакет team40 (40 места, 35 €/мес.) + поправка на проверката за пакет
-- =====================================================================
-- team_subscriptions.plan допускаше само team5/team10/team20 — така
-- платен бизнес план ('business') гърмеше при записа и порталът оставаше
-- заключен, въпреки че Stripe е взел парите. Сега са разрешени и двата.
-- Идемпотентно.
-- =====================================================================

alter table public.team_subscriptions
  drop constraint if exists team_subscriptions_plan_check;
alter table public.team_subscriptions
  add constraint team_subscriptions_plan_check
  check (plan in ('team5', 'team10', 'team20', 'team40', 'business'));

create or replace function public.team_plan_specs()
returns table (plan text, seats int, price_cents int)
language sql
immutable
as $$
  select * from (values
    ('team5',   5, 600),   -- 6 €
    ('team10', 10, 1000),  -- 10 €
    ('team20', 20, 1800),  -- 18 €
    ('team40', 40, 3500)   -- 35 €
  ) as t(plan, seats, price_cents);
$$;
