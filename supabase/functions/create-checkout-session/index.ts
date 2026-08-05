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
        error:
          `Този акаунт (${user.email}) няма профил-визитка и не може да купува пакети. ` +
          `Влезте с акаунта на визитката, на която е зададена фирма.`,
      }, 409);
    }

    const profile = profiles.find((p) => p.company_id) ?? profiles[0];

    if (!profile.company_id) {
      return json({
        error:
          `Профилът „${profile.id}" още няма зададена фирма. ` +
          `Задайте я от админ панела (Фирма на профила).`,
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
      const userClient = createClient(
        Deno.env.get('SUPABASE_URL')!,
        Deno.env.get('SUPABASE_ANON_KEY')!,
        { global: { headers: { Authorization: authHeader } } },
      );
      const { data: offers } = await userClient.rpc('get_my_business_offer');
      const offer = Array.isArray(offers) ? offers[0] : offers;
      if (!offer) {
        return json({
          error: 'Няма изготвена бизнес оферта за вашата фирма. Свържете се с нас.',
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

    const session = await stripe.checkout.sessions.create({
      mode: 'subscription',
      customer_email: user.email ?? undefined,
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
