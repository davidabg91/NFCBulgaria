// =====================================================================
// Портфолио във визитката — абонамент (снимки / видеа).
//
// Отделна функция като theme-checkout: ако тук нещо гръмне, пакетите на
// Фирмения Портал и фоновете продължават да работят.
//
// Действия (POST, Authorization: Bearer <access_token>):
//   create  {plan, interval}  → Stripe Checkout (ново портфолио)
//   verify  {session_id}      → отключва при връщане от Stripe
//   change  {plan, interval}  → смяна на пакет (доплаща се разликата)
//   cancel / resume           → спиране в края на периода / отмяна на спирането
//
// Deploy:
//   npx supabase functions deploy portfolio-checkout --project-ref upjwsqfrblxzhyuxeumj
//
// Цените са в Stripe с lookup_key portfolio_<plan>_<month|year>. Тук стои
// само каталогът за проверка — браузърът не решава колко струва пакетът.
// =====================================================================

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

const PORTFOLIO_PLANS: Record<string, { label: string; rank: number }> = {
  foto:  { label: 'Портфолио — Фото', rank: 1 },
  video: { label: 'Портфолио — Фото + Видео', rank: 2 },
  pro:   { label: 'Портфолио — Про', rank: 3 },
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

async function priceFor(plan: string, interval: 'month' | 'year'): Promise<Stripe.Price> {
  const key = `portfolio_${plan}_${interval}`;
  const { data } = await stripe.prices.list({ lookup_keys: [key], active: true, limit: 1 });
  if (!data[0]) throw new Error(`Липсва цена в Stripe с lookup_key ${key}`);
  return data[0];
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  try {
    const authHeader = req.headers.get('Authorization') ?? '';
    if (!authHeader.startsWith('Bearer ')) return json({ error: 'Липсва сесия.' }, 401);

    const url = Deno.env.get('SUPABASE_URL')!;
    // Четене/валидация — публичният ключ. Писане — SERVICE_KEY (виж README).
    const anon = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!);
    const writeKey = Deno.env.get('SERVICE_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(url, writeKey);

    const { data: userData, error: userErr } = await anon.auth.getUser(
      authHeader.replace('Bearer ', ''),
    );
    if (userErr || !userData.user) return json({ error: 'Невалидна сесия.' }, 401);
    const user = userData.user;

    const body = await req.json().catch(() => ({} as Record<string, unknown>));
    const action = String(body.action ?? 'create');
    const interval = (body.interval === 'year' ? 'year' : 'month') as 'month' | 'year';

    // Записва/обновява абонамента в базата по данните от Stripe.
    async function saveSub(sub: Stripe.Subscription, profileId?: string | null, sessionId?: string | null) {
      const plan = sub.metadata?.plan ?? '';
      if (!PORTFOLIO_PLANS[plan]) throw new Error('Непознат пакет в абонамента.');
      const item = sub.items.data[0];
      const { error } = await supabase.from('portfolio_subscriptions').upsert({
        user_id: user.id,
        profile_id: profileId ?? sub.metadata?.profile_id ?? null,
        plan,
        interval: item?.price?.recurring?.interval === 'year' ? 'year' : 'month',
        price_cents: item?.price?.unit_amount ?? 0,
        status: sub.status,
        cancel_at_period_end: !!sub.cancel_at_period_end,
        current_period_end: new Date(sub.current_period_end * 1000).toISOString(),
        stripe_customer_id: typeof sub.customer === 'string' ? sub.customer : null,
        stripe_subscription_id: sub.id,
        ...(sessionId ? { stripe_session_id: sessionId } : {}),
        updated_at: new Date().toISOString(),
      }, { onConflict: 'stripe_subscription_id' });
      if (error) throw error;
    }

    // Текущият Stripe абонамент за портфолио (ако има)
    async function currentSub(): Promise<Stripe.Subscription | null> {
      const { data: rows } = await supabase
        .from('portfolio_subscriptions')
        .select('stripe_subscription_id')
        .eq('user_id', user.id)
        .in('status', ['active', 'trialing', 'past_due'])
        .not('stripe_subscription_id', 'like', 'manual-%')
        .not('stripe_subscription_id', 'is', null)
        .order('current_period_end', { ascending: false })
        .limit(1);
      const id = rows?.[0]?.stripe_subscription_id;
      if (!id) return null;
      const sub = await stripe.subscriptions.retrieve(id);
      return ['active', 'trialing', 'past_due'].includes(sub.status) ? sub : null;
    }

    // -----------------------------------------------------------------
    // СЪЗДАВАНЕ
    // -----------------------------------------------------------------
    if (action === 'create') {
      const plan = String(body.plan ?? '');
      if (!PORTFOLIO_PLANS[plan]) return json({ error: 'Непознат пакет.' }, 400);

      const { data: profiles } = await supabase
        .from('profiles')
        .select('id, name, company_id')
        .eq('user_id', user.id)
        .limit(1);
      const profile = profiles?.[0];
      if (!profile) {
        return json({
          error: `Този акаунт (${user.email}) няма визитка, към която да се закачи портфолио.`,
        }, 409);
      }

      if (await currentSub()) {
        return json({ code: 'has_sub', error: 'Вече имате портфолио — сменете пакета от таблото.' }, 409);
      }

      // Клиент в Stripe: фирменият (ако фирмата има данни за фактура),
      // иначе личен по user_id.
      let customerId: string | null = null;
      if (profile.company_id) {
        const found = await stripe.customers.search({
          query: `metadata['company_id']:'${profile.company_id}'`, limit: 1,
        });
        customerId = found.data[0]?.id ?? null;
      }
      if (!customerId) {
        const found = await stripe.customers.search({
          query: `metadata['supabase_user_id']:'${user.id}'`, limit: 1,
        });
        customerId = found.data[0]?.id ?? (await stripe.customers.create({
          email: user.email ?? undefined,
          name: profile.name ?? undefined,
          preferred_locales: ['bg'],
          metadata: { supabase_user_id: user.id, profile_id: profile.id },
        })).id;
      }

      const price = await priceFor(plan, interval);
      const meta = {
        kind: 'portfolio',
        plan,
        interval,
        supabase_user_id: user.id,
        profile_id: profile.id,
        company_id: profile.company_id ?? '',
      };

      const session = await stripe.checkout.sessions.create({
        mode: 'subscription',
        customer: customerId,
        client_reference_id: user.id,
        line_items: [{ price: price.id, quantity: 1 }],
        metadata: meta,
        subscription_data: { metadata: meta },
        success_url: `${SITE_URL}/dashboard.html?portfolio_checkout=success&session_id={CHECKOUT_SESSION_ID}`,
        cancel_url: `${SITE_URL}/dashboard.html?portfolio_checkout=cancel#portfolioSection`,
      });

      return json({ url: session.url });
    }

    // -----------------------------------------------------------------
    // ПОТВЪРЖДАВАНЕ при връщане от Stripe
    // -----------------------------------------------------------------
    if (action === 'verify') {
      const sessionId = String(body.session_id ?? '');
      if (!sessionId) return json({ error: 'Липсва session_id.' }, 400);

      const session = await stripe.checkout.sessions.retrieve(sessionId);
      if (session.client_reference_id !== user.id) {
        return json({ ok: false, error: 'Тази сесия не принадлежи на профила ви.' }, 403);
      }
      if (session.metadata?.kind !== 'portfolio') {
        return json({ ok: false, error: 'Тази сесия не е за портфолио.' }, 400);
      }
      if (session.status !== 'complete' || typeof session.subscription !== 'string') {
        return json({ ok: false, pending: true, message: 'Плащането още не е потвърдено.' });
      }

      const sub = await stripe.subscriptions.retrieve(session.subscription);
      await saveSub(sub, session.metadata?.profile_id, session.id);
      return json({ ok: true, plan: sub.metadata?.plan, label: PORTFOLIO_PLANS[sub.metadata?.plan ?? '']?.label });
    }

    // -----------------------------------------------------------------
    // СМЯНА НА ПАКЕТ / СПИРАНЕ
    // -----------------------------------------------------------------
    const sub = await currentSub();
    if (!sub) return json({ code: 'no_sub', error: 'Нямате платен абонамент за портфолио.' }, 404);

    if (action === 'change') {
      const plan = String(body.plan ?? '');
      if (!PORTFOLIO_PLANS[plan]) return json({ error: 'Непознат пакет.' }, 400);
      const price = await priceFor(plan, interval);
      const item = sub.items.data[0];
      if (item.price.id === price.id) return json({ ok: true, unchanged: true });

      // По-голям пакет — доплаща се веднага пропорционално. По-малък — разликата
      // остава като кредит за следващата такса.
      const upgrade = PORTFOLIO_PLANS[plan].rank > PORTFOLIO_PLANS[sub.metadata?.plan ?? '']?.rank
        || (interval === 'year' && item.price.recurring?.interval === 'month');

      const updated = await stripe.subscriptions.update(sub.id, {
        items: [{ id: item.id, price: price.id }],
        proration_behavior: upgrade ? 'always_invoice' : 'create_prorations',
        payment_behavior: 'error_if_incomplete',
        cancel_at_period_end: false,
        metadata: { ...sub.metadata, plan, interval },
      });
      await saveSub(updated);
      return json({ ok: true, plan, label: PORTFOLIO_PLANS[plan].label });
    }

    if (action === 'cancel' || action === 'resume') {
      const updated = await stripe.subscriptions.update(sub.id, {
        cancel_at_period_end: action === 'cancel',
      });
      await saveSub(updated);
      return json({ ok: true, cancel_at_period_end: updated.cancel_at_period_end });
    }

    return json({ error: 'Непознато действие.' }, 400);
  } catch (err) {
    console.error('portfolio-checkout error', err);
    const msg = (err as { raw?: { message?: string } })?.raw?.message;
    return json({ error: msg ? `Stripe: ${msg}` : 'Възникна грешка при плащането за портфолио.' }, 500);
  }
});
