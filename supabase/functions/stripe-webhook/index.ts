// =====================================================================
// Stripe webhook — ЕДИНСТВЕНОТО място, което отключва пакет.
//
// Deploy:
//   supabase functions deploy stripe-webhook --no-verify-jwt
//   supabase secrets set STRIPE_SECRET_KEY=sk_live_... STRIPE_WEBHOOK_SECRET=whsec_...
//
// В Stripe Dashboard → Developers → Webhooks добави endpoint:
//   https://<project-ref>.supabase.co/functions/v1/stripe-webhook
// Събития:
//   checkout.session.completed
//   invoice.paid                      ← месечното подновяване
//   customer.subscription.deleted     ← отказ
//
// `--no-verify-jwt` е нужен, защото Stripe не носи Supabase токен.
// Автентичността се доказва с подписа на Stripe по-долу.
// =====================================================================

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
  apiVersion: '2024-06-20',
  httpClient: Stripe.createFetchHttpClient(),
});

const WEBHOOK_SECRET = Deno.env.get('STRIPE_WEBHOOK_SECRET')!;

// Писане в базата — SERVICE_KEY (авто-вкараният service-role на този
// проект е без права заради миграцията към новите API ключове).
const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SERVICE_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

const PLAN_SEATS: Record<string, { seats: number; amount: number }> = {
  team5:  { seats: 5,  amount: 600 },
  team10: { seats: 10, amount: 1000 },
  team20: { seats: 20, amount: 1800 },
};

/** Край на периода: това, което Stripe казва, иначе +1 месец. */
function periodEnd(unixSeconds?: number | null): string {
  if (unixSeconds) return new Date(unixSeconds * 1000).toISOString();
  const d = new Date();
  d.setMonth(d.getMonth() + 1);
  return d.toISOString();
}

async function activate(opts: {
  userId: string;
  companyId: string;
  plan: string;
  periodEndIso: string;
  customerId?: string | null;
  subscriptionId?: string | null;
  sessionId?: string | null;
}) {
  const spec = PLAN_SEATS[opts.plan];
  if (!spec) {
    console.error('Непознат пакет в metadata:', opts.plan);
    return;
  }

  // onConflict по stripe_subscription_id — подновяванията обновяват
  // същия ред вместо да трупат нови.
  const { error } = await supabase
    .from('team_subscriptions')
    .upsert({
      company_id: opts.companyId,
      boss_user_id: opts.userId,
      plan: opts.plan,
      seats: spec.seats,
      price_cents: spec.amount,
      status: 'active',
      current_period_end: opts.periodEndIso,
      stripe_customer_id: opts.customerId ?? null,
      stripe_subscription_id: opts.subscriptionId ?? null,
      stripe_session_id: opts.sessionId ?? null,
      updated_at: new Date().toISOString(),
    }, { onConflict: 'stripe_subscription_id' });

  if (error) {
    console.error('Неуспешен запис на абонамент:', error.message);
    throw error;
  }

  // Отключва портала в dashboard.html
  await supabase.from('profiles').update({ is_boss: true }).eq('user_id', opts.userId);
}

Deno.serve(async (req) => {
  const signature = req.headers.get('stripe-signature');
  if (!signature) return new Response('Липсва подпис.', { status: 400 });

  const payload = await req.text();

  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(payload, signature, WEBHOOK_SECRET);
  } catch (err) {
    console.error('Невалиден подпис:', err);
    return new Response('Невалиден подпис.', { status: 400 });
  }

  try {
    switch (event.type) {
      // Първо плащане
      case 'checkout.session.completed': {
        const s = event.data.object as Stripe.Checkout.Session;
        const userId = s.metadata?.supabase_user_id ?? s.client_reference_id;
        const companyId = s.metadata?.company_id;
        const plan = s.metadata?.plan;

        if (!userId || !companyId || !plan) {
          console.error('Непълни metadata в checkout сесия', s.id);
          break;
        }

        let end: number | null = null;
        if (typeof s.subscription === 'string') {
          const sub = await stripe.subscriptions.retrieve(s.subscription);
          end = sub.current_period_end;
        }

        await activate({
          userId,
          companyId,
          plan,
          periodEndIso: periodEnd(end),
          customerId: typeof s.customer === 'string' ? s.customer : null,
          subscriptionId: typeof s.subscription === 'string' ? s.subscription : null,
          sessionId: s.id,
        });
        break;
      }

      // Месечно подновяване — удължава с още един период
      case 'invoice.paid': {
        const inv = event.data.object as Stripe.Invoice;
        if (typeof inv.subscription !== 'string') break;

        const sub = await stripe.subscriptions.retrieve(inv.subscription);
        const userId = sub.metadata?.supabase_user_id;
        const companyId = sub.metadata?.company_id;
        const plan = sub.metadata?.plan;
        if (!userId || !companyId || !plan) break;

        await activate({
          userId,
          companyId,
          plan,
          periodEndIso: periodEnd(sub.current_period_end),
          customerId: typeof sub.customer === 'string' ? sub.customer : null,
          subscriptionId: sub.id,
        });
        break;
      }

      // Отказан абонамент — порталът се заключва
      case 'customer.subscription.deleted': {
        const sub = event.data.object as Stripe.Subscription;

        await supabase
          .from('team_subscriptions')
          .update({ status: 'canceled', updated_at: new Date().toISOString() })
          .eq('stripe_subscription_id', sub.id);

        const userId = sub.metadata?.supabase_user_id;
        if (userId) {
          await supabase.from('profiles').update({ is_boss: false }).eq('user_id', userId);
        }
        break;
      }
    }

    return new Response(JSON.stringify({ received: true }), {
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (err) {
    // 500 → Stripe ще пробва пак. Важно е при временен проблем с базата.
    console.error('Грешка при обработка на', event.type, err);
    return new Response('Грешка при обработка.', { status: 500 });
  }
});
