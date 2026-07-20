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

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const { data: userData, error: userErr } = await supabase.auth.getUser(
      authHeader.replace('Bearer ', ''),
    );
    if (userErr || !userData.user) return json({ error: 'Невалидна сесия.' }, 401);

    const user = userData.user;

    // --- Кой пакет ---
    const { plan } = await req.json().catch(() => ({ plan: null }));
    const spec = PLANS[plan as string];
    if (!spec) return json({ error: 'Непознат пакет.' }, 400);

    // --- Фирмата трябва да е зададена, иначе абонаментът няма към какво да се върже ---
    const { data: profile } = await supabase
      .from('profiles')
      .select('company_id, company, name')
      .eq('user_id', user.id)
      .maybeSingle();

    if (!profile?.company_id) {
      return json({
        error:
          'Профилът ви още няма зададена фирма. Свържете се с нас, за да я активираме.',
      }, 409);
    }

    const session = await stripe.checkout.sessions.create({
      mode: 'subscription',
      customer_email: user.email ?? undefined,
      client_reference_id: user.id,
      line_items: [{
        quantity: 1,
        price_data: {
          currency: 'eur',
          unit_amount: spec.amount,
          recurring: { interval: 'month' },
          product_data: {
            name: spec.label,
            description: `${spec.seats} места за служители · достъп до Фирмения Портал`,
          },
        },
      }],
      // Тези метаданни webhook-ът чете, за да знае кого да отключи.
      metadata: { supabase_user_id: user.id, plan, company_id: profile.company_id },
      subscription_data: {
        metadata: { supabase_user_id: user.id, plan, company_id: profile.company_id },
      },
      success_url: `${SITE_URL}/dashboard.html?checkout=success`,
      cancel_url: `${SITE_URL}/dashboard.html?checkout=cancel`,
    });

    return json({ url: session.url });
  } catch (err) {
    console.error('checkout error', err);
    return json({ error: 'Възникна грешка при създаване на плащането.' }, 500);
  }
});
