/* =====================================================================
 * Фонове (теми) на дигиталната визитка
 * =====================================================================
 * Един каталог, ползван от три места:
 *   profile.html   — рисува избрания фон на посетителя
 *   dashboard.html — галерията, от която клиентът избира / купува
 *   theme-checkout — валидира, че купуваният id съществува
 *
 * Всяка тема задава CSS променливите на страницата. Затова нито
 * profile.html, нито dashboard.html имат нужда от свой CSS за темите —
 * сменя се само стойността на променливите.
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

  var THEMES = [
    {
      id: 'midnight',
      name: 'Полунощен неон',
      tagline: 'Класиката на NFC Bulgaria — студено синьо и мента.',
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
      // 1:1 повторение на досегашните два „блоба" от body::before/::after,
      // за да не се промени нито една вече издадена визитка.
      page:
        'radial-gradient(circle 150px at 100px 100px, rgba(0,242,255,0.4) 0%, transparent 70%),' +
        'radial-gradient(circle 150px at calc(100% - 100px) calc(100% - 100px), rgba(161,232,175,0.2) 0%, transparent 70%),' +
        'linear-gradient(160deg, #0b0f19 0%, #0b0f19 100%)',
      cardShadow: '0 20px 50px rgba(0, 0, 0, 0.5)'
    },

    {
      id: 'obsidian',
      name: 'Обсидиан и злато',
      tagline: 'Дълбоко черно с топло злато. За хора, които не се обясняват.',
      free: false,
      light: false,
      vars: {
        bg: '#07070a',
        cardBg: 'rgba(20, 19, 17, 0.78)',
        primary: '#e2c275',
        primaryGlow: 'rgba(226, 194, 117, 0.30)',
        secondary: '#f4e6c1',
        text: '#f6f2ea',
        textMuted: '#a49b8a',
        border: 'rgba(226, 194, 117, 0.14)',
        glassBorder: 'rgba(226, 194, 117, 0.28)',
        onPrimary: '#0a0908',
        surface: 'rgba(255, 248, 232, 0.035)',
        surfaceStrong: 'rgba(255, 248, 232, 0.08)',
        inputBg: 'rgba(0, 0, 0, 0.35)',
        primarySoft: 'rgba(226, 194, 117, 0.10)'
      },
      page:
        'radial-gradient(1000px 700px at 78% -12%, rgba(226,194,117,0.16), transparent 58%),' +
        'radial-gradient(700px 520px at 6% 104%, rgba(158,112,50,0.14), transparent 60%),' +
        'linear-gradient(165deg, #0a0908 0%, #07070a 55%, #100d09 100%)',
      cardShadow: '0 24px 60px rgba(0, 0, 0, 0.72)'
    },

    {
      id: 'platinum',
      name: 'Платина',
      tagline: 'Светла, тиха и много чиста. Идеална за печатни материали.',
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
        'radial-gradient(900px 620px at 10% -10%, rgba(61,90,128,0.16), transparent 60%),' +
        'radial-gradient(820px 560px at 96% 110%, rgba(123,143,168,0.20), transparent 62%),' +
        'linear-gradient(160deg, #f7f8fa 0%, #e9ecf1 100%)',
      cardShadow: '0 22px 48px rgba(22, 26, 33, 0.14)'
    },

    {
      id: 'aurora',
      name: 'Аврора',
      tagline: 'Виолетово и циан, преливащи като северно сияние.',
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
        'radial-gradient(880px 620px at 18% -6%, rgba(155,140,255,0.30), transparent 58%),' +
        'radial-gradient(820px 600px at 88% 20%, rgba(67,223,232,0.18), transparent 58%),' +
        'radial-gradient(760px 560px at 60% 112%, rgba(224,86,190,0.16), transparent 60%),' +
        'linear-gradient(170deg, #080a1c 0%, #0c0a22 100%)',
      cardShadow: '0 24px 58px rgba(6, 4, 24, 0.68)'
    },

    {
      id: 'emerald',
      name: 'Смарагд',
      tagline: 'Тъмнозелено с нефритов акцент. Спокойно и скъпо.',
      free: false,
      light: false,
      vars: {
        bg: '#05110d',
        cardBg: 'rgba(11, 30, 24, 0.74)',
        primary: '#35e0a1',
        primaryGlow: 'rgba(53, 224, 161, 0.32)',
        secondary: '#b9f2d8',
        text: '#eef7f2',
        textMuted: '#8aa79b',
        border: 'rgba(255, 255, 255, 0.08)',
        glassBorder: 'rgba(53, 224, 161, 0.22)',
        onPrimary: '#04100c',
        surface: 'rgba(255, 255, 255, 0.035)',
        surfaceStrong: 'rgba(255, 255, 255, 0.075)',
        inputBg: 'rgba(4, 20, 15, 0.6)',
        primarySoft: 'rgba(53, 224, 161, 0.10)'
      },
      page:
        'radial-gradient(900px 640px at 84% -10%, rgba(53,224,161,0.20), transparent 58%),' +
        'radial-gradient(760px 540px at 4% 106%, rgba(16,120,90,0.26), transparent 62%),' +
        'linear-gradient(165deg, #04100c 0%, #061912 100%)',
      cardShadow: '0 22px 54px rgba(0, 20, 14, 0.66)'
    },

    {
      id: 'sapphire',
      name: 'Сапфир',
      tagline: 'Корпоративно синьо без да е скучно. Работи навсякъде.',
      free: false,
      light: false,
      vars: {
        bg: '#040a19',
        cardBg: 'rgba(13, 25, 48, 0.74)',
        primary: '#5b9dff',
        primaryGlow: 'rgba(91, 157, 255, 0.34)',
        secondary: '#b9d4ff',
        text: '#eef3fb',
        textMuted: '#8fa2c2',
        border: 'rgba(255, 255, 255, 0.08)',
        glassBorder: 'rgba(91, 157, 255, 0.22)',
        onPrimary: '#03081a',
        surface: 'rgba(255, 255, 255, 0.04)',
        surfaceStrong: 'rgba(255, 255, 255, 0.08)',
        inputBg: 'rgba(4, 12, 32, 0.6)',
        primarySoft: 'rgba(91, 157, 255, 0.13)'
      },
      page:
        'radial-gradient(920px 640px at 14% -8%, rgba(91,157,255,0.26), transparent 58%),' +
        'radial-gradient(780px 560px at 92% 104%, rgba(28,64,138,0.34), transparent 62%),' +
        'linear-gradient(165deg, #030818 0%, #061334 100%)',
      cardShadow: '0 22px 54px rgba(2, 8, 26, 0.7)'
    },

    {
      id: 'copper',
      name: 'Мед и графит',
      tagline: 'Топъл метал върху студен графит. Занаятчийски, не крещящ.',
      free: false,
      light: false,
      vars: {
        bg: '#121110',
        cardBg: 'rgba(28, 25, 23, 0.76)',
        primary: '#e08a5b',
        primaryGlow: 'rgba(224, 138, 91, 0.30)',
        secondary: '#f2c3a3',
        text: '#f5efe9',
        textMuted: '#a4968b',
        border: 'rgba(255, 255, 255, 0.08)',
        glassBorder: 'rgba(224, 138, 91, 0.24)',
        onPrimary: '#0f0e0d',
        surface: 'rgba(255, 245, 235, 0.035)',
        surfaceStrong: 'rgba(255, 245, 235, 0.08)',
        inputBg: 'rgba(0, 0, 0, 0.32)',
        primarySoft: 'rgba(224, 138, 91, 0.12)'
      },
      page:
        'radial-gradient(880px 620px at 88% -8%, rgba(224,138,91,0.22), transparent 58%),' +
        'radial-gradient(720px 540px at 8% 108%, rgba(120,66,40,0.26), transparent 62%),' +
        'linear-gradient(165deg, #0f0e0d 0%, #191513 100%)',
      cardShadow: '0 22px 54px rgba(10, 8, 7, 0.7)'
    },

    {
      id: 'noir',
      name: 'Ноар',
      tagline: 'Само черно, бяло и сиво. Типографията говори.',
      free: false,
      light: false,
      vars: {
        bg: '#0c0c0d',
        cardBg: 'rgba(24, 24, 26, 0.78)',
        primary: '#ededed',
        primaryGlow: 'rgba(255, 255, 255, 0.20)',
        secondary: '#9d9d9f',
        text: '#f7f7f7',
        textMuted: '#8e8e90',
        border: 'rgba(255, 255, 255, 0.10)',
        glassBorder: 'rgba(255, 255, 255, 0.22)',
        onPrimary: '#0c0c0d',
        surface: 'rgba(255, 255, 255, 0.045)',
        surfaceStrong: 'rgba(255, 255, 255, 0.09)',
        inputBg: 'rgba(0, 0, 0, 0.35)',
        primarySoft: 'rgba(255, 255, 255, 0.08)'
      },
      page:
        'radial-gradient(900px 640px at 22% -10%, rgba(255,255,255,0.12), transparent 58%),' +
        'radial-gradient(760px 560px at 90% 110%, rgba(255,255,255,0.07), transparent 60%),' +
        'linear-gradient(165deg, #0a0a0b 0%, #111112 100%)',
      cardShadow: '0 22px 54px rgba(0, 0, 0, 0.75)'
    },

    {
      id: 'sandstone',
      name: 'Пясъчник',
      tagline: 'Топла светла тема с кафяв акцент. Мека за окото.',
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
        'radial-gradient(880px 620px at 14% -10%, rgba(195,154,118,0.32), transparent 60%),' +
        'radial-gradient(800px 560px at 94% 108%, rgba(156,102,68,0.20), transparent 62%),' +
        'linear-gradient(160deg, #faf5ed 0%, #efe5d6 100%)',
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
    '--avatar-glow'
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
    return t;
  }

  /* Малко квадратче за галерията — същите цветове, умалена визитка. */
  function previewHtml(id) {
    var t = getTheme(id);
    var v = t.vars;
    return '' +
      '<div style="position:absolute;inset:0;background:' + t.page + ';"></div>' +
      '<div style="position:absolute;inset:0;background:' + GRAIN + ';opacity:0.9;"></div>' +
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
