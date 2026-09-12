// =====================================================================
// Покупка на премиум фон за визитката — 9,99 € еднократно.
//
// Нарочно е ОТДЕЛНА функция от create-checkout-session / verify-checkout.
// Абонаментите за Фирмения Портал не се пипат — ако тук нещо гръмне,
// плащанията на пакетите продължават да работят.
//
// Deploy:
//   supabase functions deploy theme-checkout
//
// Ползва вече зададените STRIPE_SECRET_KEY, SITE_URL и SERVICE_KEY.
// По избор:
//   supabase secrets set STRIPE_THEME_PRICE_ID=price_...
// (ако не е зададен, се ползва цената, създадена в Stripe за този продукт)
// =====================================================================

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

// Каталогът е дублиран тук нарочно: браузърът НЕ може да реши кой фон е
// платен. Сървърът е авторитетът. Ако добавиш фон в card-themes.js,
// добави id-то и тук.
const PAID_THEMES: Record<string, string> = {
  obsidian:  'Обсидиан и злато',
  platinum:  'Платина',
  aurora:    'Аврора',
  emerald:   'Смарагд',
  sapphire:  'Сапфир',
  copper:    'Мед и графит',
  noir:      'Ноар',
  sandstone: 'Пясъчник',
};

const THEME_PRICE_ID = Deno.env.get('STRIPE_THEME_PRICE_ID')
  ?? 'price_1UEvtaBSCTEyBv79AlhnTEWy';

const THEME_PRICE_CENTS = 999;

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
    const authHeader = req.headers.get('Authorization') ?? '';
    if (!authHeader.startsWith('Bearer ')) return json({ error: 'Липсва сесия.' }, 401);

    const url = Deno.env.get('SUPABASE_URL')!;
    // Четене/валидация — публичният ключ. Писане — SERVICE_KEY (авто-
    // вкараният service-role на този проект е без права, виж README).
    const anon = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!);
    const writeKey = Deno.env.get('SERVICE_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(url, writeKey);

    const { data: userData, error: userErr } = await anon.auth.getUser(
      authHeader.replace('Bearer ', ''),
    );
    if (userErr || !userData.user) return json({ error: 'Невалидна сесия.' }, 401);
    const user = userData.user;

    const body = await req.json().catch(() => ({} as Record<string, unknown>));
    const action = body.action === 'verify' ? 'verify' : 'create';

    // -----------------------------------------------------------------
    // СЪЗДАВАНЕ на checkout сесия
    // -----------------------------------------------------------------
    if (action === 'create') {
      const themeId = String(body.theme_id ?? '');
      const themeName = PAID_THEMES[themeId];

      if (!themeName) {
        return json({ error: 'Непознат фон.' }, 400);
      }

      // Профилът трябва да съществува — фонът се лепи на визитка.
      const { data: profiles } = await supabase
        .from('profiles')
        .select('id, name')
        .eq('user_id', user.id)
        .limit(1);

      if (!profiles || profiles.length === 0) {
        return json({
          error: `Този акаунт (${user.email}) няма профил-визитка, на която да се сложи фон.`,
        }, 409);
      }

      // Вече купен? Не го таксуваме втори път.
      const { data: owned } = await supabase
        .from('theme_purchases')
        .select('theme_id')
        .eq('user_id', user.id)
        .eq('theme_id', themeId)
        .limit(1);

      if (owned && owned.length > 0) {
        return json({ already_owned: true, theme_id: themeId });
      }

      const session = await stripe.checkout.sessions.create({
        mode: 'payment',
        customer_email: user.email ?? undefined,
        client_reference_id: user.id,
        line_items: [{ price: THEME_PRICE_ID, quantity: 1 }],
        metadata: {
          kind: 'card_theme',
          supabase_user_id: user.id,
          theme_id: themeId,
          theme_name: themeName,
          profile_id: profiles[0].id,
        },
        payment_intent_data: {
          description: `Премиум фон „${themeName}" — ${profiles[0].id}`,
          metadata: { kind: 'card_theme', theme_id: themeId, supabase_user_id: user.id },
        },
        success_url: `${SITE_URL}/dashboard.html?theme_checkout=success&session_id={CHECKOUT_SESSION_ID}`,
        cancel_url: `${SITE_URL}/dashboard.html?theme_checkout=cancel`,
      });

      return json({ url: session.url });
    }

    // -----------------------------------------------------------------
    // ПОТВЪРЖДАВАНЕ при връщане от Stripe
    // -----------------------------------------------------------------
    const sessionId = String(body.session_id ?? '');
    if (!sessionId) return json({ error: 'Липсва session_id.' }, 400);

    const session = await stripe.checkout.sessions.retrieve(sessionId);

    // Сесията трябва да е на ТОЗИ потребител — иначе някой може да
    // отключи фон с подставен session_id.
    if (session.client_reference_id !== user.id) {
      return json({ ok: false, error: 'Тази сесия не принадлежи на профила ви.' }, 403);
    }

    if (session.metadata?.kind !== 'card_theme') {
      return json({ ok: false, error: 'Тази сесия не е за фон.' }, 400);
    }

    const themeId = session.metadata?.theme_id ?? '';
    if (!PAID_THEMES[themeId]) {
      return json({ ok: false, error: 'Непознат фон в сесията.' }, 400);
    }

    if (session.payment_status !== 'paid') {
      // Още не е минало — UI-ът ще опита пак след малко.
      return json({ ok: false, pending: true, message: 'Плащането още не е потвърдено.' });
    }

    const { error: insErr } = await supabase
      .from('theme_purchases')
      .upsert({
        user_id: user.id,
        theme_id: themeId,
        amount_cents: session.amount_total ?? THEME_PRICE_CENTS,
        currency: session.currency ?? 'eur',
        stripe_session_id: session.id,
      }, { onConflict: 'user_id,theme_id' });

    if (insErr) {
      console.error('theme purchase insert error', insErr.message);
      return json({ ok: false, error: 'Плащането мина, но записът не стана. Свържете се с нас.' }, 500);
    }

    // Веднага го правим активен — това е очакването след покупка.
    await supabase.from('profiles').update({ theme_id: themeId }).eq('user_id', user.id);

    return json({ ok: true, theme_id: themeId, theme_name: PAID_THEMES[themeId] });
  } catch (err) {
    console.error('theme-checkout error', err);
    return json({ error: 'Възникна грешка при плащането за фон.' }, 500);
  }
});
