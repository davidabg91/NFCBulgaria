/* =====================================================================
 * Фонове (теми) на дигиталната визитка
 * =====================================================================
 * Един каталог, ползван от три места:
 *   profile.html   — рисува избрания фон на посетителя
 *   dashboard.html — галерията, от която клиентът избира / купува
 *   theme-checkout — валидира, че купуваният id съществува
 *
 * Всяка платена тема се състои от четири слоя:
 *   page     — преливащите се градиенти (основата)
 *   pattern  — рисунъкът отгоре: мрежа, платки, контури, щрихи…
 *   accent   — едно голямо светещо петно
 *   grain    — фината зърнистост, обща за всички
 * Плюс CSS променливите, по които се боядисват самата визитка и
 * панелите ѝ, за да е всичко от един тон.
 *
 * ВАЖНО: `id`-тата се пазят в базата (profiles.theme_id) и в Stripe
 * metadata. Не ги преименувай — добавяй нови.
 * ===================================================================== */

(function (global) {
  'use strict';

  // Фина зърнистост отгоре — това прави градиентите да изглеждат
  // „скъпи", а не като плосък CSS преливник.
  var GRAIN =
    // stitchTiles + baseFrequency, кратна на размера на плочката (0.8*120=96),
    // иначе шумът се вижда като квадратна мрежа върху светлите фонове.
    "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='120' height='120'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.8' numOctaves='3' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='120' height='120' filter='url(%23n)' opacity='0.03'/%3E%3C/svg%3E\")";

  // svg() спестява ръчното кодиране на # и кавичките в data URI-тата.
  function svg(w, h, body) {
    return "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' " +
      "width='" + w + "' height='" + h + "' viewBox='0 0 " + w + " " + h + "'%3E" +
      body + "%3C/svg%3E\")";
  }

  // ------------------------------------------------------------------
  // Рисунъците
  // ------------------------------------------------------------------

  // Точкова решетка със светещ възел — „данни в пространството"
  var P_QUANTUM = svg(48, 48,
    "%3Ccircle cx='1.5' cy='1.5' r='1' fill='%23ffffff' opacity='0.22'/%3E" +
    "%3Cpath d='M25 25h23M25 25v23' stroke='%237df9ff' stroke-width='0.4' opacity='0.16'/%3E" +
    "%3Ccircle cx='25' cy='25' r='1.7' fill='%237df9ff' opacity='0.34'/%3E");

  // Печатна платка — пътечки и запоени пъпки
  var P_CIRCUIT = svg(90, 90,
    "%3Cg fill='none' stroke='%2345f0a6' stroke-width='1' opacity='0.26'%3E" +
    "%3Cpath d='M0 18h26v26h28M54 44V18h36M18 90V62h36v28M62 0v26M0 70h18'/%3E" +
    "%3C/g%3E%3Cg fill='%2345f0a6' opacity='0.34'%3E" +
    "%3Ccircle cx='26' cy='18' r='2.4'/%3E%3Ccircle cx='54' cy='44' r='2.4'/%3E" +
    "%3Ccircle cx='54' cy='62' r='2.4'/%3E%3Ccircle cx='62' cy='26' r='2.4'/%3E" +
    "%3Ccircle cx='18' cy='70' r='2.4'/%3E%3C/g%3E");

  // Технически чертеж — фина мрежа с по-плътни главни линии
  var P_BLUEPRINT = svg(100, 100,
    "%3Cg stroke='%23bcd7ff' fill='none'%3E" +
    "%3Cpath d='M20 0V100M40 0V100M60 0V100M80 0V100M0 20H100M0 40H100M0 60H100M0 80H100' stroke-width='0.6' opacity='0.30'/%3E" +
    "%3Cpath d='M0 0V100M0 0H100' stroke-width='1.4' opacity='0.45'/%3E" +
    "%3C/g%3E");

  // Изохипси — плавни контури като на топографска карта
  var P_TOPO = svg(140, 70,
    "%3Cg fill='none' stroke='%232f7d5b' stroke-width='1.1' opacity='0.20'%3E" +
    "%3Cpath d='M0 14q35-20 70 0t70 0'/%3E" +
    "%3Cpath d='M0 34q35-20 70 0t70 0'/%3E" +
    "%3Cpath d='M0 54q35-20 70 0t70 0'/%3E" +
    "%3C/g%3E");

  // Архитектурна мрежа — едра, светла, за печатните материали
  var P_GRID_LIGHT = svg(120, 120,
    "%3Cg stroke='%23161a21' fill='none' stroke-width='0.7' opacity='0.10'%3E" +
    "%3Cpath d='M0 0H120M0 60H120M0 0V120M60 0V120'/%3E%3C/g%3E" +
    "%3Ccircle cx='60' cy='60' r='1.3' fill='%23161a21' opacity='0.14'/%3E");

  // Звезден прах за Аврора
  var P_STARS = svg(160, 160,
    "%3Cg fill='%23ffffff'%3E" +
    "%3Ccircle cx='18' cy='26' r='1.1' opacity='0.45'/%3E%3Ccircle cx='96' cy='14' r='0.9' opacity='0.32'/%3E" +
    "%3Ccircle cx='134' cy='58' r='1.2' opacity='0.40'/%3E%3Ccircle cx='52' cy='84' r='0.9' opacity='0.30'/%3E" +
    "%3Ccircle cx='118' cy='118' r='1.1' opacity='0.38'/%3E%3Ccircle cx='28' cy='140' r='0.9' opacity='0.28'/%3E" +
    "%3Ccircle cx='76' cy='48' r='0.7' opacity='0.24'/%3E%3Ccircle cx='150' cy='96' r='0.7' opacity='0.24'/%3E" +
    "%3C/g%3E");

  // Меки дюни за Пясъчник
  var P_DUNES = svg(180, 90,
    "%3Cg fill='none' stroke='%239c6644' stroke-width='1.2' opacity='0.16'%3E" +
    "%3Cpath d='M0 22q45-24 90 0t90 0'/%3E" +
    "%3Cpath d='M0 48q45-24 90 0t90 0'/%3E" +
    "%3Cpath d='M0 74q45-24 90 0t90 0'/%3E" +
    "%3C/g%3E");

  // Диагонални щрихи — четкана стомана
  var P_STEEL =
    'repeating-linear-gradient(115deg, rgba(255,255,255,0) 0 7px, rgba(255,255,255,0.035) 7px 8px)';

  // Тънки вертикални райета — костюмен плат
  var P_PINSTRIPE =
    'repeating-linear-gradient(90deg, rgba(216,184,119,0) 0 15px, rgba(216,184,119,0.09) 15px 16px)';

  var THEMES = [
    {
      id: 'midnight',
      name: 'Полунощен неон',
      tagline: 'Класиката на NFC Bulgaria — студено синьо и мента.',
      industry: 'Универсален',
      free: true,
      light: false,
      vars: {
        bg: '#0b0f19',
        cardBg: 'rgba(17, 24, 39, 0.7)',
        primary: '#00f2ff',
        primaryGlow: 'rgba(0, 242, 255, 0.4)',
        secondary: '#a1e8af',
        text: '#f3f4f6',
        textMuted: '#9ca3af',
        border: 'rgba(255, 255, 255, 0.08)',
        glassBorder: 'rgba(0, 242, 255, 0.15)',
        onPrimary: '#0b0f19',
        surface: 'rgba(255, 255, 255, 0.03)',
        surfaceStrong: 'rgba(255, 255, 255, 0.07)',
        inputBg: 'rgba(15, 23, 42, 0.6)',
        primarySoft: 'rgba(0, 242, 255, 0.10)'
      },
      // Ползва се САМО от прегледите — живата визитка си рисува блобовете
      // от body::before/::after в profile.html и не пипа тази стойност.
      // Затова е в проценти: така умаленото квадратче в галерията показва
      // същото, което човекът ще види на телефона си.
      page:
        'radial-gradient(30% 34% at 9% 12%, rgba(0,242,255,0.40) 0%, transparent 70%),' +
        'radial-gradient(30% 34% at 91% 88%, rgba(161,232,175,0.20) 0%, transparent 70%),' +
        'linear-gradient(160deg, #0b0f19 0%, #0b0f19 100%)',
      cardShadow: '0 20px 50px rgba(0, 0, 0, 0.5)'
    },

    {
      id: 'quantum',
      name: 'Квантум',
      tagline: 'Мрежа от светещи възли в дълбок космос. За хора, които продават бъдеще.',
      industry: 'Технологии · Стартъпи · Иновации',
      free: false,
      light: false,
      vars: {
        bg: '#05060f',
        cardBg: 'rgba(14, 17, 38, 0.72)',
        primary: '#7df9ff',
        primaryGlow: 'rgba(125, 249, 255, 0.35)',
        secondary: '#b98cff',
        text: '#eef2ff',
        textMuted: '#8f97c4',
        border: 'rgba(255, 255, 255, 0.09)',
        glassBorder: 'rgba(125, 249, 255, 0.26)',
        onPrimary: '#04050d',
        surface: 'rgba(255, 255, 255, 0.04)',
        surfaceStrong: 'rgba(255, 255, 255, 0.08)',
        inputBg: 'rgba(6, 8, 24, 0.65)',
        primarySoft: 'rgba(125, 249, 255, 0.12)'
      },
      page:
        'radial-gradient(70% 72% at 16% -6%, rgba(185,140,255,0.26), transparent 60%),' +
        'radial-gradient(75% 80% at 90% 106%, rgba(125,249,255,0.20), transparent 62%),' +
        'linear-gradient(168deg, #05060f 0%, #080a20 60%, #05060f 100%)',
      pattern: P_QUANTUM,
      patternSize: '48px 48px',
      drift: '48px 48px',
      accent: 'radial-gradient(closest-side, rgba(125,249,255,0.16), transparent 70%)',
      accentPos: '78% 18%',
      accentSize: '48% 62%',
      cardShadow: '0 24px 58px rgba(2, 3, 16, 0.72)'
    },

    {
      id: 'circuit',
      name: 'Платка',
      tagline: 'Пътечки и запоени възли по тъмна плоскост. Направена за софтуерни хора.',
      industry: 'ИТ · Софтуер · Електроника',
      free: false,
      light: false,
      vars: {
        bg: '#060b09',
        cardBg: 'rgba(10, 21, 18, 0.76)',
        primary: '#45f0a6',
        primaryGlow: 'rgba(69, 240, 166, 0.32)',
        secondary: '#7fe9ff',
        text: '#e9fff6',
        textMuted: '#7e9c90',
        border: 'rgba(255, 255, 255, 0.08)',
        glassBorder: 'rgba(69, 240, 166, 0.24)',
        onPrimary: '#04100b',
        surface: 'rgba(255, 255, 255, 0.035)',
        surfaceStrong: 'rgba(255, 255, 255, 0.075)',
        inputBg: 'rgba(4, 16, 12, 0.62)',
        primarySoft: 'rgba(69, 240, 166, 0.11)'
      },
      page:
        'radial-gradient(78% 80% at 86% -10%, rgba(69,240,166,0.16), transparent 58%),' +
        'radial-gradient(66% 70% at 4% 104%, rgba(20,110,90,0.26), transparent 62%),' +
        'linear-gradient(168deg, #040907 0%, #07120f 100%)',
      pattern: P_CIRCUIT,
      patternSize: '90px 90px',
      drift: '90px 0px',
      accent: 'radial-gradient(closest-side, rgba(69,240,166,0.14), transparent 72%)',
      accentPos: '20% 82%',
      accentSize: '44% 58%',
      cardShadow: '0 22px 54px rgba(0, 14, 10, 0.7)'
    },

    {
      id: 'blueprint',
      name: 'Чертеж',
      tagline: 'Милиметрова мрежа и жълт молив — езикът на проекта.',
      industry: 'Строители · Архитекти · Проектанти',
      free: false,
      light: false,
      vars: {
        bg: '#062348',
        cardBg: 'rgba(9, 42, 82, 0.74)',
        primary: '#ffcc66',
        primaryGlow: 'rgba(255, 204, 102, 0.30)',
        secondary: '#ffe6b0',
        text: '#eaf2ff',
        textMuted: '#9fb6d4',
        border: 'rgba(188, 215, 255, 0.16)',
        glassBorder: 'rgba(255, 204, 102, 0.28)',
        onPrimary: '#062348',
        surface: 'rgba(188, 215, 255, 0.06)',
        surfaceStrong: 'rgba(188, 215, 255, 0.12)',
        inputBg: 'rgba(4, 26, 54, 0.6)',
        primarySoft: 'rgba(255, 204, 102, 0.12)'
      },
      page:
        'radial-gradient(82% 82% at 12% -8%, rgba(120,170,240,0.20), transparent 60%),' +
        'radial-gradient(70% 72% at 94% 108%, rgba(255,204,102,0.12), transparent 62%),' +
        'linear-gradient(168deg, #05203f 0%, #072a54 55%, #041b38 100%)',
      pattern: P_BLUEPRINT,
      patternSize: '100px 100px',
      drift: '0px 100px',
      accent: 'radial-gradient(closest-side, rgba(255,204,102,0.12), transparent 72%)',
      accentPos: '86% 12%',
      accentSize: '42% 55%',
      cardShadow: '0 22px 54px rgba(2, 14, 30, 0.66)'
    },

    {
      id: 'forge',
      name: 'Ковачница',
      tagline: 'Четкана стомана и жар от пещта. За хора, които произвеждат неща.',
      industry: 'Производство · Индустрия · Енергетика',
      free: false,
      light: false,
      vars: {
        bg: '#100f0e',
        cardBg: 'rgba(27, 24, 22, 0.78)',
        primary: '#ff8a3d',
        primaryGlow: 'rgba(255, 138, 61, 0.30)',
        secondary: '#ffc189',
        text: '#f7f1ea',
        textMuted: '#a3968a',
        border: 'rgba(255, 255, 255, 0.08)',
        glassBorder: 'rgba(255, 138, 61, 0.26)',
        onPrimary: '#0e0c0a',
        surface: 'rgba(255, 245, 235, 0.04)',
        surfaceStrong: 'rgba(255, 245, 235, 0.085)',
        inputBg: 'rgba(0, 0, 0, 0.34)',
        primarySoft: 'rgba(255, 138, 61, 0.12)'
      },
      page:
        'radial-gradient(82% 80% at 50% 116%, rgba(255,110,40,0.26), transparent 62%),' +
        'radial-gradient(64% 67% at 8% -8%, rgba(255,255,255,0.06), transparent 58%),' +
        'linear-gradient(168deg, #14120f 0%, #0d0c0b 100%)',
      pattern: P_STEEL,
      patternSize: 'auto',
      drift: '60px 0px',
      accent: 'radial-gradient(closest-side, rgba(255,138,61,0.18), transparent 70%)',
      accentPos: '50% 104%',
      accentSize: '66% 50%',
      cardShadow: '0 22px 54px rgba(8, 6, 5, 0.72)'
    },

    {
      id: 'meridian',
      name: 'Меридиан',
      tagline: 'Костюмено райе и премерено злато. Сдържано, не крещящо.',
      industry: 'Финанси · Право · Консултанти',
      free: false,
      light: false,
      vars: {
        bg: '#0a0f1c',
        cardBg: 'rgba(16, 23, 41, 0.78)',
        primary: '#d8b877',
        primaryGlow: 'rgba(216, 184, 119, 0.28)',
        secondary: '#e8d8ae',
        text: '#f2f4f9',
        textMuted: '#94a0b8',
        border: 'rgba(216, 184, 119, 0.14)',
        glassBorder: 'rgba(216, 184, 119, 0.26)',
        onPrimary: '#0a0f1c',
        surface: 'rgba(255, 255, 255, 0.035)',
        surfaceStrong: 'rgba(255, 255, 255, 0.075)',
        inputBg: 'rgba(6, 10, 20, 0.6)',
        primarySoft: 'rgba(216, 184, 119, 0.11)'
      },
      page:
        'radial-gradient(82% 82% at 82% -10%, rgba(216,184,119,0.16), transparent 58%),' +
        'radial-gradient(70% 72% at 6% 106%, rgba(30,52,96,0.40), transparent 62%),' +
        'linear-gradient(168deg, #080d19 0%, #0c1426 100%)',
      pattern: P_PINSTRIPE,
      patternSize: 'auto',
      drift: '32px 0px',
      accent: 'radial-gradient(closest-side, rgba(216,184,119,0.12), transparent 72%)',
      accentPos: '84% 16%',
      accentSize: '46% 60%',
      cardShadow: '0 22px 54px rgba(2, 6, 16, 0.7)'
    },

    {
      id: 'verdant',
      name: 'Върдант',
      tagline: 'Светла, с меки контури като на карта. Спокойна и чиста.',
      industry: 'Здраве · Екология · Земеделие',
      free: false,
      light: true,
      vars: {
        bg: '#edf4ef',
        cardBg: 'rgba(255, 255, 255, 0.88)',
        primary: '#2f7d5b',
        primaryGlow: 'rgba(47, 125, 91, 0.22)',
        secondary: '#6cbb95',
        text: '#14251d',
        textMuted: '#55695f',
        border: 'rgba(20, 37, 29, 0.10)',
        glassBorder: 'rgba(47, 125, 91, 0.24)',
        onPrimary: '#ffffff',
        surface: 'rgba(20, 37, 29, 0.045)',
        surfaceStrong: 'rgba(20, 37, 29, 0.09)',
        inputBg: 'rgba(255, 255, 255, 0.92)',
        primarySoft: 'rgba(47, 125, 91, 0.10)'
      },
      page:
        'radial-gradient(82% 80% at 10% -10%, rgba(108,187,149,0.34), transparent 60%),' +
        'radial-gradient(75% 72% at 96% 110%, rgba(47,125,91,0.20), transparent 62%),' +
        'linear-gradient(160deg, #f5faf6 0%, #e6efe8 100%)',
      pattern: P_TOPO,
      patternSize: '140px 70px',
      drift: '140px 0px',
      accent: 'radial-gradient(closest-side, rgba(47,125,91,0.10), transparent 72%)',
      accentPos: '18% 84%',
      accentSize: '48% 62%',
      cardShadow: '0 22px 48px rgba(20, 50, 36, 0.14)'
    },

    {
      id: 'aurora',
      name: 'Аврора',
      tagline: 'Виолетово и циан, преливащи като северно сияние, със звезден прах.',
      industry: 'Творчески · Маркетинг · Медии',
      free: false,
      light: false,
      vars: {
        bg: '#080a1c',
        cardBg: 'rgba(20, 22, 46, 0.72)',
        primary: '#9b8cff',
        primaryGlow: 'rgba(155, 140, 255, 0.38)',
        secondary: '#43dfe8',
        text: '#f2f1fb',
        textMuted: '#9e9bc4',
        border: 'rgba(255, 255, 255, 0.09)',
        glassBorder: 'rgba(155, 140, 255, 0.24)',
        onPrimary: '#0a0820',
        surface: 'rgba(255, 255, 255, 0.04)',
        surfaceStrong: 'rgba(255, 255, 255, 0.08)',
        inputBg: 'rgba(10, 10, 30, 0.6)',
        primarySoft: 'rgba(155, 140, 255, 0.13)'
      },
      page:
        'radial-gradient(80% 80% at 18% -6%, rgba(155,140,255,0.30), transparent 58%),' +
        'radial-gradient(75% 77% at 88% 20%, rgba(67,223,232,0.18), transparent 58%),' +
        'radial-gradient(70% 72% at 60% 112%, rgba(224,86,190,0.16), transparent 60%),' +
        'linear-gradient(170deg, #080a1c 0%, #0c0a22 100%)',
      pattern: P_STARS,
      patternSize: '160px 160px',
      drift: '160px 160px',
      accent: 'radial-gradient(closest-side, rgba(67,223,232,0.12), transparent 72%)',
      accentPos: '88% 22%',
      accentSize: '48% 62%',
      cardShadow: '0 24px 58px rgba(6, 4, 24, 0.68)'
    },

    {
      id: 'platinum',
      name: 'Платина',
      tagline: 'Светла, тиха и много чиста, с едва доловима архитектурна мрежа.',
      industry: 'Корпоративен · Печатни материали',
      free: false,
      light: true,
      vars: {
        bg: '#eef0f4',
        cardBg: 'rgba(255, 255, 255, 0.86)',
        primary: '#3d5a80',
        primaryGlow: 'rgba(61, 90, 128, 0.22)',
        secondary: '#7b8fa8',
        text: '#161a21',
        textMuted: '#5d6675',
        border: 'rgba(22, 26, 33, 0.10)',
        glassBorder: 'rgba(61, 90, 128, 0.22)',
        onPrimary: '#ffffff',
        surface: 'rgba(22, 26, 33, 0.045)',
        surfaceStrong: 'rgba(22, 26, 33, 0.09)',
        inputBg: 'rgba(255, 255, 255, 0.92)',
        primarySoft: 'rgba(61, 90, 128, 0.10)'
      },
      page:
        'radial-gradient(82% 80% at 10% -10%, rgba(61,90,128,0.16), transparent 60%),' +
        'radial-gradient(75% 72% at 96% 110%, rgba(123,143,168,0.20), transparent 62%),' +
        'linear-gradient(160deg, #f7f8fa 0%, #e9ecf1 100%)',
      pattern: P_GRID_LIGHT,
      patternSize: '120px 120px',
      drift: '120px 0px',
      accent: 'radial-gradient(closest-side, rgba(61,90,128,0.09), transparent 72%)',
      accentPos: '14% 86%',
      accentSize: '48% 62%',
      cardShadow: '0 22px 48px rgba(22, 26, 33, 0.14)'
    },

    {
      id: 'sandstone',
      name: 'Пясъчник',
      tagline: 'Топла светла тема с кафяв акцент и меки дюни. Мека за окото.',
      industry: 'Занаяти · Хотелиерство · Ресторанти',
      free: false,
      light: true,
      vars: {
        bg: '#f3ece1',
        cardBg: 'rgba(255, 252, 247, 0.88)',
        primary: '#9c6644',
        primaryGlow: 'rgba(156, 102, 68, 0.22)',
        secondary: '#c39a76',
        text: '#241e18',
        textMuted: '#6b5f53',
        border: 'rgba(36, 30, 24, 0.10)',
        glassBorder: 'rgba(156, 102, 68, 0.24)',
        onPrimary: '#ffffff',
        surface: 'rgba(36, 30, 24, 0.05)',
        surfaceStrong: 'rgba(36, 30, 24, 0.10)',
        inputBg: 'rgba(255, 255, 255, 0.92)',
        primarySoft: 'rgba(156, 102, 68, 0.10)'
      },
      page:
        'radial-gradient(80% 80% at 14% -10%, rgba(195,154,118,0.32), transparent 60%),' +
        'radial-gradient(73% 72% at 94% 108%, rgba(156,102,68,0.20), transparent 62%),' +
        'linear-gradient(160deg, #faf5ed 0%, #efe5d6 100%)',
      pattern: P_DUNES,
      patternSize: '180px 90px',
      drift: '180px 0px',
      accent: 'radial-gradient(closest-side, rgba(156,102,68,0.10), transparent 72%)',
      accentPos: '86% 84%',
      accentSize: '50% 64%',
      cardShadow: '0 22px 48px rgba(60, 45, 32, 0.16)'
    }
  ];

  var BY_ID = {};
  THEMES.forEach(function (t) { BY_ID[t.id] = t; });

  var DEFAULT_ID = 'midnight';

  function getTheme(id) {
    return BY_ID[id] || BY_ID[DEFAULT_ID];
  }

  function isFree(id) {
    var t = BY_ID[id];
    return !!(t && t.free);
  }

  var PROPS = [
    '--bg', '--card-bg', '--primary', '--primary-glow', '--secondary',
    '--text', '--text-muted', '--border', '--glass-border',
    '--on-primary', '--surface', '--surface-strong', '--input-bg',
    '--primary-soft', '--theme-page', '--theme-card-shadow', '--theme-grain',
    '--btn-save-glow', '--lang-bg', '--lang-active-glow', '--hover-text',
    '--avatar-glow',
    '--theme-pattern', '--theme-pattern-size', '--theme-drift',
    '--theme-accent', '--theme-accent-pos', '--theme-accent-size'
  ];

  /* Задава CSS променливите на дадения елемент (обикновено
   * document.documentElement). Връща темата, за да може извикващият
   * да реши още нещо по нея (напр. светла ли е).
   *
   * ВАЖНО: темата по подразбиране НЕ задава нищо — маха всичко и оставя
   * страницата на нейния собствен CSS. Така визитката без купен фон
   * изглежда точно както преди да съществуват темите. `force` е за
   * прегледа в панела, където и подразбиращата се тема трябва да се
   * нарисува върху отделен елемент.
   */
  function applyThemeVars(el, id, force) {
    var t = getTheme(id);
    var v = t.vars;
    var s = el.style;

    if (t.id === DEFAULT_ID && !force) {
      PROPS.forEach(function (p) { s.removeProperty(p); });
      return t;
    }

    s.setProperty('--bg', v.bg);
    s.setProperty('--card-bg', v.cardBg);
    s.setProperty('--primary', v.primary);
    s.setProperty('--primary-glow', v.primaryGlow);
    s.setProperty('--secondary', v.secondary);
    s.setProperty('--text', v.text);
    s.setProperty('--text-muted', v.textMuted);
    s.setProperty('--border', v.border);
    s.setProperty('--glass-border', v.glassBorder);
    s.setProperty('--on-primary', v.onPrimary);
    s.setProperty('--surface', v.surface);
    s.setProperty('--surface-strong', v.surfaceStrong);
    s.setProperty('--input-bg', v.inputBg);
    s.setProperty('--primary-soft', v.primarySoft);
    s.setProperty('--btn-save-glow', v.primaryGlow);
    s.setProperty('--avatar-glow', v.primaryGlow);
    s.setProperty('--lang-bg', v.cardBg);
    s.setProperty('--lang-active-glow', v.primaryGlow);
    s.setProperty('--hover-text', v.text);
    s.setProperty('--theme-page', t.page);
    s.setProperty('--theme-card-shadow', t.cardShadow);
    s.setProperty('--theme-grain', GRAIN);
    s.setProperty('--theme-pattern', t.pattern || 'none');
    s.setProperty('--theme-pattern-size', t.patternSize || 'auto');
    s.setProperty('--theme-drift', t.drift || '0 0');
    s.setProperty('--theme-accent', t.accent || 'none');
    s.setProperty('--theme-accent-pos', t.accentPos || '50% 50%');
    s.setProperty('--theme-accent-size', t.accentSize || '46% 60%');
    return t;
  }

  /* Малко квадратче за галерията — същите слоеве, умалена визитка. */
  function previewHtml(id) {
    var t = getTheme(id);
    var v = t.vars;
    var layers = '<div style="position:absolute;inset:0;background:' + t.page + ';"></div>';

    if (t.pattern) {
      layers += '<div style="position:absolute;inset:0;background-image:' + t.pattern +
        ';background-size:' + (t.patternSize || 'auto') + ';"></div>';
    }
    if (t.accent) {
      layers += '<div style="position:absolute;inset:0;background-image:' + t.accent +
        ';background-position:' + (t.accentPos || '50% 50%') +
        ';background-size:' + (t.accentSize || '46% 60%') +
        ';background-repeat:no-repeat;"></div>';
    }
    layers += '<div style="position:absolute;inset:0;background:' + GRAIN + ';opacity:0.9;"></div>';

    return layers +
      '<div style="position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);' +
      'width:62%;height:72%;border-radius:14px;background:' + v.cardBg + ';' +
      'border:1px solid ' + v.border + ';box-shadow:' + t.cardShadow + ';' +
      'backdrop-filter:blur(8px);-webkit-backdrop-filter:blur(8px);' +
      'display:flex;flex-direction:column;align-items:center;justify-content:center;gap:5px;">' +
      '<div style="width:26px;height:26px;border-radius:50%;background:linear-gradient(135deg,' +
      v.primary + ',' + v.secondary + ');"></div>' +
      '<div style="width:52%;height:5px;border-radius:3px;background:' + v.text + ';opacity:0.85"></div>' +
      '<div style="width:36%;height:4px;border-radius:3px;background:' + v.textMuted + ';opacity:0.8"></div>' +
      '<div style="width:44%;height:7px;border-radius:4px;margin-top:3px;background:' + v.primary + ';opacity:0.9"></div>' +
      '</div>';
  }

  global.CardThemes = {
    list: THEMES,
    byId: BY_ID,
    DEFAULT_ID: DEFAULT_ID,
    GRAIN: GRAIN,
    get: getTheme,
    isFree: isFree,
    apply: applyThemeVars,
    previewHtml: previewHtml,
    PRICE_CENTS: 999,
    PRICE_LABEL: '9,99 €'
  };
})(typeof window !== 'undefined' ? window : globalThis);
