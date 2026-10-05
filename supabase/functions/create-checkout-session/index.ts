// =====================================================================
// Създава Stripe Checkout сесия за пакет от Фирмения Портал.
//
// Deploy:
//   supabase functions deploy create-checkout-session
//   supabase secrets set STRIPE_SECRET_KEY=sk_live_... SITE_URL=https://nfcbulgaria.com
//
// Извиква се от dashboard.html с Authorization: Bearer <access_token>.
// Цената НЕ идва от браузъра — взима се от таблицата тук, за да не може
// някой да си купи 20 места за 1 стотинка.
// =====================================================================

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

const PLANS: Record<string, { seats: number; amount: number; label: string }> = {
  team5:  { seats: 5,  amount: 600,  label: 'Фирмен Портал — 5 служителя' },
  team10: { seats: 10, amount: 1000, label: 'Фирмен Портал — 10 служителя' },
  team20: { seats: 20, amount: 1800, label: 'Фирмен Портал — 20 служителя' },
  team40: { seats: 40, amount: 3500, label: 'Фирмен Портал — 40 служителя' },
};

// Годишно = месечно × 11 (една такса безплатна).
const YEAR_MULTIPLIER = 11;

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
  apiVersion: '2024-06-20',
  httpClient: Stripe.createFetchHttpClient(),
});

const SITE_URL = Deno.env.get('SITE_URL') ?? 'https://nfcbulgaria.com';

const cors = {
  'Access-Control-Allow-Origin': SITE_URL,
  'Access-Control-Allow-Headers': 'authorization, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });

type Billing = {
  company_id: string;
  company_name: string;
  eik: string;
  vat_number: string | null;
  address: string;
  city: string;
  postal_code: string | null;
  mol: string;
  email: string | null;
};

// Един Stripe клиент на фирма (по metadata.company_id), само с име, имейл
// и адрес — за разписката. Истинската фактура (с ЕИК, МОЛ и основанието
// по ЗДДС) се издава ръчно от Revolut по данните в админ панела, затова
// документът от Stripe нарочно не прилича на българска фактура.
async function upsertBillingCustomer(b: Billing, fallbackEmail: string): Promise<string> {
  const data = {
    name: b.company_name,
    email: b.email || fallbackEmail || undefined,
    address: {
      line1: b.address,
      city: b.city,
      postal_code: b.postal_code ?? undefined,
      country: 'BG',
    },
    preferred_locales: ['bg'],
    // '' изчиства полета, ако клиентът е създаден с тях по-рано
    invoice_settings: { custom_fields: '' as const, footer: '' },
    metadata: { company_id: b.company_id },
  };

  const found = await stripe.customers.search({
    query: `metadata['company_id']:'${b.company_id}'`,
    limit: 1,
  });
  if (found.data[0]) {
    await stripe.customers.update(found.data[0].id, data);
    return found.data[0].id;
  }
  const created = await stripe.customers.create(data);
  return created.id;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  try {
    // --- Кой е потребителят ---
    const authHeader = req.headers.get('Authorization') ?? '';
    if (!authHeader.startsWith('Bearer ')) {
      return json({ error: 'Липсва сесия.' }, 401);
    }

    // Авто-вкараният SERVICE_ROLE_KEY е счупен (проектът е на новите ключове)
    // и няма права за таблиците. За четене ползваме публичния ANON ключ —
    // profiles така или иначе е публично четим (визитките се показват на всеки).
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
    );

    const { data: userData, error: userErr } = await supabase.auth.getUser(
      authHeader.replace('Bearer ', ''),
    );
    if (userErr || !userData.user) return json({ error: 'Невалидна сесия.' }, 401);

    const user = userData.user;

    // --- Кой пакет и на какъв период ---
    const body = await req.json().catch(() => ({} as Record<string, unknown>));
    const plan = body.plan as string | null;
    const interval = (body.interval === 'year' ? 'year' : 'month') as 'month' | 'year';

    const isBusiness = plan === 'business';
    const spec = plan ? PLANS[plan] : undefined;
    if (!isBusiness && !spec) return json({ error: 'Непознат пакет.' }, 400);

    // --- Фирмата трябва да е зададена, иначе абонаментът няма към какво да се върже ---
    // Търсим профила първо по user_id, после по имейл (той е потвърден в
    // токена). Fallback-ът по имейл спасява случаите, в които профилът е
    // закачен за друг вътрешен user_id заради разминаване при създаването.
    let { data: profiles } = await supabase
      .from('profiles')
      .select('company_id, company, name, id')
      .eq('user_id', user.id);

    if ((!profiles || profiles.length === 0) && user.email) {
      const byEmail = await supabase
        .from('profiles')
        .select('company_id, company, name, id')
        .ilike('email', user.email);
      profiles = byEmail.data ?? [];
    }

    if (!profiles || profiles.length === 0) {
      return json({
        code: 'no_profile',
        error:
          `Този акаунт (${user.email}) няма своя визитка, затова не може да купува пакети. ` +
          `Влезте с имейла, с който сте получили визитката си.`,
      }, 409);
    }

    const profile = profiles.find((p) => p.company_id) ?? profiles[0];

    // Тук НЕ става дума за името на фирмата, което клиентът си пише сам в
    // полето „Фирма" — а за фирмената група (company_id), която свързва
    // неговите карти в един екип. Тя се задава от нас. Затова
    // съобщението не бива да го праща в админ панел, до който няма достъп.
    if (!profile.company_id) {
      return json({
        code: 'no_company',
        error:
          'Профилът ви още не е свързан с фирмена група. Фирменият портал ' +
          'работи на групи: ние отбелязваме кой е управителят и закачаме ' +
          'картите на екипа към неговата фирма. Свържете се с нас и го ' +
          'настройваме — отнема минути.',
      }, 409);
    }

    // Клиент с токена на потребителя — за RPC-тата, които гледат auth.uid()
    const userClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } },
    );

    // --- Данни за фактура: без тях не тръгваме към Stripe ---
    // Таблото показва формата при този код и после пробва отново.
    const { data: billingRows } = await userClient.rpc('get_my_billing_details');
    const billing = Array.isArray(billingRows) ? billingRows[0] : billingRows;
    if (!billing) {
      return json({
        code: 'need_billing',
        error: 'Попълнете данните за фактура, за да продължите към плащането.',
      }, 409);
    }

    // --- Определяме места / месечна цена / етикет / триал ---
    let seats: number;
    let monthlyAmount: number;
    let label: string;
    let trial = false;

    if (isBusiness) {
      // Договорената оферта се чете СЪРВЪРНО (никога от браузъра), с токена
      // на потребителя — RPC-то връща офертата за неговата фирма.
      const { data: offers } = await userClient.rpc('get_my_business_offer');
      const offer = Array.isArray(offers) ? offers[0] : offers;
      if (!offer) {
        return json({
          code: 'no_offer',
          error:
            'За вашата фирма още няма изготвена оферта. Бизнес планът е с ' +
            'договорена цена според броя служители — свържете се с нас и ' +
            'ще ви я подготвим.',
        }, 409);
      }
      seats = offer.seats;
      monthlyAmount = offer.monthly_price_cents;
      label = offer.label ?? `Бизнес план — ${seats} служителя`;
      trial = !!offer.trial;
    } else {
      seats = spec!.seats;
      monthlyAmount = spec!.amount;
      label = spec!.label;
    }

    // Годишно = месечно × 11. Триалът (първи месец безплатно) важи само за
    // месечно плащане — при годишно отстъпката е самата безплатна такса.
    const unitAmount = interval === 'year' ? monthlyAmount * YEAR_MULTIPLIER : monthlyAmount;
    const trialDays = trial && interval === 'month' ? 30 : undefined;
    const periodLabel = interval === 'year' ? 'годишно' : 'месечно';

    // Тези метаданни verify-checkout/webhook четат, за да запишат правилно
    // местата, цената и периода (важно за бизнес и годишно).
    const meta = {
      supabase_user_id: user.id,
      plan: plan!,
      company_id: profile.company_id,
      seats: String(seats),
      price_cents: String(unitAmount),
      interval,
    };

    const customerId = await upsertBillingCustomer(billing, user.email ?? '');

    const session = await stripe.checkout.sessions.create({
      mode: 'subscription',
      customer: customerId,
      client_reference_id: user.id,
      line_items: [{
        quantity: 1,
        price_data: {
          currency: 'eur',
          unit_amount: unitAmount,
          recurring: { interval },
          product_data: {
            name: label,
            description: `${seats} места за служители · ${periodLabel} · достъп до Фирмения Портал`,
          },
        },
      }],
      metadata: meta,
      subscription_data: {
        metadata: meta,
        ...(trialDays ? { trial_period_days: trialDays } : {}),
      },
      success_url: `${SITE_URL}/dashboard.html?checkout=success&session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${SITE_URL}/dashboard.html?checkout=cancel`,
    });

    return json({ url: session.url });
  } catch (err) {
    console.error('checkout error', err);
    return json({ error: 'Възникна грешка при създаване на плащането.' }, 500);
  }
});
