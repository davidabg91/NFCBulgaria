# Фирмен Портал — стъпки за пускане

Кодът във фронтенда е готов, но порталът **няма да работи**, докато не минеш
тези стъпки. Всичко тук се прави веднъж.

## 1. База данни

Supabase → SQL Editor → изпълни `team-portal.sql`.

После се добави като администратор (за картата „Фирма на профила“ в admin.html):

```sql
insert into public.app_admins (user_id)
select id from auth.users where email = 'davida1991@gmail.com';
```

## 2. Задай фирми на съществуващите профили

В `admin.html` → карта **🏭 Фирма на профила**:

1. Избери профила на шефа → „Създай НОВА фирма“ → Запази.
2. За всеки негов служител → същия профил → избери вече създадената фирма.

Без това шефът не може да добави никого — правилото е „само карти от
същата фирма“.

## 3. Stripe

1. В Stripe вземи `sk_live_...` (или `sk_test_...` за проби).
2. Deploy на функциите:

```bash
supabase functions deploy create-checkout-session
supabase functions deploy verify-checkout
supabase functions deploy stripe-webhook --no-verify-jwt   # по избор, виж по-долу

supabase secrets set \
  STRIPE_SECRET_KEY=sk_live_... \
  SITE_URL=https://nfcbulgaria.com
```

Това е достатъчно порталът да работи. `verify-checkout` потвърждава
плащането директно при връщане от Stripe и отключва пакета — не е нужен
webhook за първоначалното активиране.

### Webhook (по избор — за подновявания и откази)

Нужен е само ако искаш месечните подновявания и отказите да се отразяват
автоматично. Ако го пропуснеш, пакетът пак се отключва след плащане,
но изтича след 1 месец без авто-подновяване.

1. Stripe → Developers → Webhooks → Add endpoint:
   `https://upjwsqfrblxzhyuxeumj.supabase.co/functions/v1/stripe-webhook`

   Събития: `checkout.session.completed`, `invoice.paid`,
   `customer.subscription.deleted`

2. Копирай `whsec_...` от Stripe и го добави:

```bash
supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_...
```

`--no-verify-jwt` при webhook-а е задължителен — Stripe не носи Supabase
токен. Автентичността се проверява с подписа.

## 4. Изтичане (по избор)

Supabase → Database → Cron, дневно:

```sql
select public.expire_team_subscriptions();
```

Не е критично — порталът проверява `current_period_end` при всяко зареждане.
Cron-ът само поддържа `status` колоната чиста.

---

## Пакети

| Пакет    | Места | Цена/мес. | На място |
|----------|-------|-----------|----------|
| `team5`  | 5     | 6 €       | 1.20 €   |
| `team10` | 10    | 10 €      | 1.00 €   |
| `team20` | 20    | 18 €      | 0.90 €   |

Цените стоят на **три места** и трябва да се сменят и на трите заедно:
`team-portal.sql` (`team_plan_specs`), двете Edge Functions, и картите в
`dashboard.html`. Сървърът е авторитетът — цената никога не идва от браузъра.

## Ръчно активиране (банков превод)

Само със service_role ключ, от SQL Editor:

```sql
select public.admin_activate_subscription(
  '<user_id на шефа>'::uuid, 'team10', 1
);
```
