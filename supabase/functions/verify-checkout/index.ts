// =====================================================================
// Проверява Checkout сесия при връщане от Stripe и отключва пакета.
//
// Защо съществува: създаването на webhook endpoint изисква ръчна
// настройка в Stripe Dashboard. Тази функция маха тази зависимост за
// ПЪРВОНАЧАЛНОТО отключване — извиква се от dashboard.html със session_id
// от success_url, пита Stripe дали е платено и записва абонамента.
//
// (stripe-webhook остава за подновявания/откази, но не е задължителен,
//  за да заработи порталът.)
//
// Deploy:
//   supabase functions deploy verify-checkout
// Ползва вече зададените STRIPE_SECRET_KEY и SITE_URL.
// =====================================================================

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

const PLAN_SEATS: Record<string, { seats: number; amount: number }> = {
  team5:  { seats: 5,  amount: 600 },
  team10: { seats: 10, amount: 1000 },
  team20: { seats: 20, amount: 1800 },
};

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

function periodEnd(unixSeconds?: number | null): string {
  if (unixSeconds) return new Date(unixSeconds * 1000).toISOString();
  const d = new Date();
  d.setMonth(d.getMonth() + 1);
  return d.toISOString();
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  try {
    const authHeader = req.headers.get('Authorization') ?? '';
    if (!authHeader.startsWith('Bearer ')) return json({ error: 'Липсва сесия.' }, 401);

    const url = Deno.env.get('SUPABASE_URL')!;
    // Четене/валидация — публичен ключ (работи). Писане — SERVICE_KEY
    // (авто-вкараният service-role на този проект е без права).
    const anon = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!);
    const writeKey = Deno.env.get('SERVICE_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(url, writeKey);

    const { data: userData, error: userErr } = await anon.auth.getUser(
      authHeader.replace('Bearer ', ''),
    );
    if (userErr || !userData.user) return json({ error: 'Невалидна сесия.' }, 401);
    const user = userData.user;

    const { session_id } = await req.json().catch(() => ({ session_id: null }));
    if (!session_id) return json({ error: 'Липсва session_id.' }, 400);

    const session = await stripe.checkout.sessions.retrieve(session_id);

    // Сесията трябва да е на ТОЗИ потребител — иначе някой може да
    // отключи чужд/подставен session_id.
    if (session.client_reference_id !== user.id) {
      return json({ ok: false, error: 'Тази сесия не принадлежи на профила ви.' }, 403);
    }

    // 'paid' = нормално плащане; 'no_payment_required' = триал (първи месец
    // безплатно — Stripe не таксува сега, но абонаментът е валиден).
    const okPaid = session.payment_status === 'paid'
      || session.payment_status === 'no_payment_required'
      || session.status === 'complete';
    if (!okPaid) {
      // Още не е платено — казваме на UI-а да изчака/опита пак.
      return json({ ok: false, pending: true, message: 'Плащането още не е потвърдено.' });
    }

    const plan = session.metadata?.plan;
    const companyId = session.metadata?.company_id;
    if (!plan || !companyId) {
      return json({ ok: false, error: 'Липсват данни за пакета в сесията.' }, 400);
    }

    // Места/цена/период идват от metadata (важно за бизнес и годишно);
    // fallback към фиксираните пакети за стари сесии.
    const fallback = PLAN_SEATS[plan];
    const seats = session.metadata?.seats ? parseInt(session.metadata.seats, 10) : fallback?.seats;
    const priceCents = session.metadata?.price_cents
      ? parseInt(session.metadata.price_cents, 10) : fallback?.amount;
    const interval = session.metadata?.interval === 'year' ? 'year' : 'month';
    if (!seats || priceCents == null) {
      return json({ ok: false, error: 'Липсват данни за пакета в сесията.' }, 400);
    }

    let end: number | null = null;
    let trialEnd: number | null = null;
    let subscriptionId: string | null = null;
    if (typeof session.subscription === 'string') {
      const sub = await stripe.subscriptions.retrieve(session.subscription);
      end = sub.current_period_end;
      trialEnd = sub.trial_end ?? null;
      subscriptionId = sub.id;
    }

    const { error: upErr } = await supabase
      .from('team_subscriptions')
      .upsert({
        company_id: companyId,
        boss_user_id: user.id,
        plan,
        seats,
        price_cents: priceCents,
        interval,
        trial_end: trialEnd ? new Date(trialEnd * 1000).toISOString() : null,
        status: 'active',
        current_period_end: periodEnd(end),
        stripe_customer_id: typeof session.customer === 'string' ? session.customer : null,
        stripe_subscription_id: subscriptionId,
        stripe_session_id: session.id,
        updated_at: new Date().toISOString(),
      }, { onConflict: 'stripe_subscription_id' });

    if (upErr) {
      console.error('upsert error', upErr.message);
      return json({ ok: false, error: 'Грешка при активиране.' }, 500);
    }

    // Match и по имейл — профилът може да е закачен за друг вътрешен user_id.
    await supabase.from('profiles').update({ is_boss: true }).eq('user_id', user.id);
    if (user.email) {
      await supabase.from('profiles').update({ is_boss: true }).ilike('email', user.email);
    }

    return json({ ok: true, plan, seats });
  } catch (err) {
    console.error('verify error', err);
    return json({ ok: false, error: 'Грешка при проверка на плащането.' }, 500);
  }
});
