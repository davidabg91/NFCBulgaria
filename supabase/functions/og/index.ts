// =====================================================================
// Динамичен OG preview за визитните профили.
//
// Защо съществува: profile.html е статична страница на GitHub Pages, а
// crawler-ите на Facebook/LinkedIn/Viber НЕ изпълняват JavaScript, затова
// винаги виждат едни и същи (общи) og: тагове. Тази функция връща лека
// HTML страница с ПЕРСОНАЛИЗИРАНИ og: тагове за конкретния профил и веднага
// пренасочва истинския посетител към profile.html?id=<id>.
//
// Резултат: при споделяне на линк към визитка изскача името, длъжността,
// фирмата и снимката на човека — вместо обща картинка.
//
// Употреба:
//   Сподели/OG линк:  https://<project>.functions.supabase.co/og?id=gikov
//   (човекът бива пренасочен към https://nfcbulgaria.com/profile.html?id=gikov)
//
// Deploy:
//   supabase functions deploy og --no-verify-jwt
// Ползва вече наличните SUPABASE_URL и SUPABASE_ANON_KEY (инжектират се
// автоматично от платформата).
// =====================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

const SITE_URL = Deno.env.get('SITE_URL') ?? 'https://nfcbulgaria.com';
const DEFAULT_IMAGE = `${SITE_URL}/assets/share-preview.png`;

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_ANON_KEY')!,
);

function esc(s: unknown): string {
  return String(s ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function page(opts: {
  title: string;
  description: string;
  image: string;
  redirect: string;
}): string {
  const { title, description, image, redirect } = opts;
  return `<!DOCTYPE html>
<html lang="bg">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${esc(title)}</title>
  <meta name="description" content="${esc(description)}">

  <meta property="og:type" content="profile">
  <meta property="og:title" content="${esc(title)}">
  <meta property="og:description" content="${esc(description)}">
  <meta property="og:image" content="${esc(image)}">
  <meta property="og:url" content="${esc(redirect)}">

  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${esc(title)}">
  <meta name="twitter:description" content="${esc(description)}">
  <meta name="twitter:image" content="${esc(image)}">

  <link rel="canonical" href="${esc(redirect)}">
  <meta http-equiv="refresh" content="0; url=${esc(redirect)}">
  <script>window.location.replace(${JSON.stringify(redirect)});</script>
</head>
<body>
  <p>Пренасочване към визитката… <a href="${esc(redirect)}">Натиснете тук</a>, ако не се зареди автоматично.</p>
</body>
</html>`;
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const id = url.searchParams.get('id');

  // Без id — прати към сайта
  if (!id) {
    return Response.redirect(SITE_URL, 302);
  }

  const redirect = `${SITE_URL}/profile.html?id=${encodeURIComponent(id)}`;

  let title = 'Дигитална Визитка | NFC Bulgaria';
  let description = 'Сканирайте за бърз преглед на контакти, социални профили и запазване на контакт.';
  let image = DEFAULT_IMAGE;

  try {
    const { data } = await supabase
      .from('profiles')
      .select('name, title, company, avatar_url')
      .eq('id', id)
      .single();

    if (data) {
      title = [data.name, 'NFC Bulgaria'].filter(Boolean).join(' — ');
      description = [data.title, data.company].filter(Boolean).join(' · ')
        || description;
      if (data.avatar_url) image = data.avatar_url;
    }
  } catch (_e) {
    // При грешка връщаме общите тагове
  }

  return new Response(page({ title, description, image, redirect }), {
    status: 200,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      // Кеш за crawler-ите, но кратък за да се обновява при промяна на профила
      'Cache-Control': 'public, max-age=300',
    },
  });
});
