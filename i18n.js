/* =====================================================================
 * NFC Bulgaria — превод на сайта (BG / EN / RO)
 * =====================================================================
 * Речникът се вдига по САМИЯ български текст, а не по ключове. Затова
 * страниците не се пипат: слага се само
 *     <script src="i18n-data.js"></script>
 *     <script src="i18n.js"></script>
 * преди </body>, и по желание <div id="langSwitch"></div> там, където
 * искаме бутоните (иначе се появяват горе вдясно).
 *
 * Български = оригиналът в HTML-а. При превключване към BG се връща
 * запазеният оригинал, така че българската версия е винаги точна.
 *
 * Динамично появил се текст (таблици в панела, toast-ове) се превежда
 * автоматично през MutationObserver.
 *
 * За текст, който се сглобява в JS с променливи, има шаблони в
 * i18n-data.js (I18N_PATTERNS) — виж примерите там.
 * ===================================================================== */
(function () {
  'use strict';

  var LANGS   = ['bg', 'en', 'ro'];
  var NAMES   = { bg: 'BG', en: 'EN', ro: 'RO' };
  var STORAGE = 'nfcLang';
  var FALLBACK = 'en';          // непознат език на браузъра → английски

  var DATA     = window.I18N_DATA || {};
  var PATTERNS = window.I18N_PATTERNS || {};

  // Съдържанието на textarea е стойност на поле — не се пипа. Но placeholder-ът
  // му трябва да се превежда, затова е изключен само от текстовите възли.
  var SKIP_TAGS      = { SCRIPT: 1, STYLE: 1, CODE: 1, PRE: 1, TEXTAREA: 1, NOSCRIPT: 1 };
  var SKIP_TAGS_ATTR = { SCRIPT: 1, STYLE: 1, CODE: 1, PRE: 1, NOSCRIPT: 1 };
  var ATTRS = ['placeholder', 'alt', 'title', 'aria-label'];

  var lang = 'bg';
  var applying = false;
  var observer = null;

  // --- помощни -------------------------------------------------------
  function norm(s) { return String(s).replace(/\s+/g, ' ').trim(); }

  function lookup(src, target) {
    if (target === 'bg') return null;
    var dict = DATA[target];
    if (dict) {
      var hit = dict[src];
      if (hit) return hit;
    }
    var pats = PATTERNS[target] || [];
    for (var i = 0; i < pats.length; i++) {
      var m = src.match(pats[i][0]);
      if (m) {
        return pats[i][1].replace(/\$(\d)/g, function (_, d) { return m[+d] || ''; });
      }
    }
    return null;
  }

  // Публично: превод на низ от JS код
  function t(src) {
    var key = norm(src);
    return lookup(key, lang) || src;
  }

  function skipIn(el, tags) {
    for (var n = el; n; n = n.parentElement) {
      if (tags[n.nodeName]) return true;
      if (n.hasAttribute && n.hasAttribute('data-i18n-skip')) return true;
    }
    return false;
  }

  function skip(el)     { return skipIn(el, SKIP_TAGS); }
  function skipAttr(el) { return skipIn(el, SKIP_TAGS_ATTR); }

  // --- текстови възли ------------------------------------------------
  function translateText(node) {
    var raw = node.nodeValue;
    if (!raw || !raw.trim()) return;
    if (!node.parentElement || skip(node.parentElement)) return;

    // Оригиналът се пази при първото докосване, за да може връщане към BG.
    if (node.__i18nBG === undefined) {
      if (!/[Ѐ-ӿ]/.test(raw)) return;   // няма кирилица → не ни интересува
      node.__i18nBG = raw;
    }

    var original = node.__i18nBG;
    if (lang === 'bg') {
      if (node.nodeValue !== original) node.nodeValue = original;
      return;
    }

    var hit = lookup(norm(original), lang);
    if (hit === null) return;                      // няма превод → оставяме както си е

    // Пазим водещото/крайното празно място, за да не се слепят думи.
    var lead  = (original.match(/^\s*/) || [''])[0];
    var trail = (original.match(/\s*$/) || [''])[0];
    var next = lead + hit + trail;
    if (node.nodeValue !== next) node.nodeValue = next;
  }

  // --- атрибути ------------------------------------------------------
  function translateAttrs(el) {
    if (skipAttr(el)) return;
    for (var i = 0; i < ATTRS.length; i++) {
      var a = ATTRS[i];
      if (!el.hasAttribute(a)) continue;
      var store = '__i18nBG_' + a;
      var cur = el.getAttribute(a);
      if (el[store] === undefined) {
        if (!/[Ѐ-ӿ]/.test(cur)) continue;
        el[store] = cur;
      }
      var original = el[store];
      if (lang === 'bg') { el.setAttribute(a, original); continue; }
      var hit = lookup(norm(original), lang);
      if (hit !== null) el.setAttribute(a, hit);
    }
  }

  function walk(root) {
    if (root.nodeType === 3) { translateText(root); return; }
    if (root.nodeType !== 1 && root.nodeType !== 9 && root.nodeType !== 11) return;
    if (root.nodeType === 1 && skip(root)) return;

    var it = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
    var n;
    while ((n = it.nextNode())) translateText(n);

    if (root.nodeType === 1) translateAttrs(root);
    var els = root.querySelectorAll ? root.querySelectorAll('*') : [];
    for (var i = 0; i < els.length; i++) translateAttrs(els[i]);
  }

  function applyAll() {
    applying = true;
    try {
      walk(document.body);
      // <title> и meta описанието
      var ttl = document.querySelector('title');
      if (ttl) translateText(ttl.firstChild || ttl.appendChild(document.createTextNode('')));
      var md = document.querySelector('meta[name="description"]');
      if (md) {
        if (md.__i18nBG === undefined) md.__i18nBG = md.getAttribute('content') || '';
        var hit = lang === 'bg' ? md.__i18nBG : lookup(norm(md.__i18nBG), lang);
        if (hit) md.setAttribute('content', hit);
      }
      document.documentElement.lang = lang;
    } finally {
      applying = false;
    }
  }

  // --- следене на новопоявил се текст --------------------------------
  function startObserver() {
    if (observer || !window.MutationObserver) return;
    observer = new MutationObserver(function (muts) {
      if (applying || lang === 'bg') {
        // и на BG следим, за да запазим оригиналите на новите възли
        if (applying) return;
      }
      applying = true;
      try {
        for (var i = 0; i < muts.length; i++) {
          var m = muts[i];
          if (m.type === 'characterData') { translateText(m.target); continue; }
          for (var j = 0; j < m.addedNodes.length; j++) walk(m.addedNodes[j]);
        }
      } finally {
        applying = false;
      }
    });
    observer.observe(document.body, {
      childList: true, subtree: true, characterData: true
    });
  }

  // --- превключвател -------------------------------------------------
  function injectStyles() {
    if (document.getElementById('i18n-style')) return;
    var css = document.createElement('style');
    css.id = 'i18n-style';
    css.textContent =
      '.i18n-switch{display:inline-flex;gap:.25rem;background:rgba(17,24,39,.72);' +
      'border:1px solid rgba(255,255,255,.12);border-radius:20px;padding:.22rem;' +
      'box-shadow:inset 0 2px 4px rgba(0,0,0,.3);backdrop-filter:blur(8px);' +
      '-webkit-backdrop-filter:blur(8px);vertical-align:middle;z-index:1000}' +
      '.i18n-switch.i18n-float{position:fixed;top:14px;right:14px;z-index:9999}' +
      '.i18n-switch button{background:transparent;border:none;color:#94a3b8;' +
      'padding:.26rem .58rem;font-size:.74rem;font-weight:800;border-radius:12px;' +
      'cursor:pointer;line-height:1.1;font-family:inherit;transition:all .2s ease}' +
      '.i18n-switch button:hover:not(.active){color:#fff;background:rgba(255,255,255,.08)}' +
      '.i18n-switch button.active{background:#00f2ff;color:#0b0f19;' +
      'box-shadow:0 0 10px rgba(0,242,255,.35)}' +
      '@media print{.i18n-switch{display:none}}' +
      // Английските и румънските думи са по-дълги от българските и една
      // дума в заглавие (напр. "Funcționalități" = 462px при екран 375px)
      // изкарваше страницата извън екрана. Пречупването се задейства САМО
      // когато думата иначе не се събира, така че българският не се променя.
      // hyphens:auto ползва <html lang>, който сменяме при всеки превод.
      'h1,h2,h3,h4,h5,h6,.gradient-text{overflow-wrap:break-word;hyphens:auto}' +
      // Мобилното меню е position:fixed и стои извън екрана (right:-100%).
      // Такива елементи НЕ се клипват от body{overflow-x:hidden} — избягват го
      // и разширяват документа. При по-дългите EN/RO етикети това изкарваше
      // страницата настрани. Клипваме на ниво <html>.
      // "clip" не създава скролиращ контейнер и затова НЕ чупи position:sticky
      // (има такъв в dashboard.html и demo-dashboard.html); "hidden" е само
      // резерва за браузъри без поддръжка на clip.
      'html{overflow-x:hidden}' +
      '@supports (overflow-x:clip){html{overflow-x:clip}}';
    document.head.appendChild(css);
  }

  function buildSwitch() {
    injectStyles();
    var host = document.getElementById('langSwitch');
    var floating = false;
    if (!host) {
      host = document.createElement('div');
      document.body.appendChild(host);
      floating = true;
    }
    host.innerHTML = '';
    var box = document.createElement('div');
    box.className = 'i18n-switch' + (floating ? ' i18n-float' : '');
    box.setAttribute('role', 'group');
    box.setAttribute('aria-label', 'Език / Language');
    box.setAttribute('data-i18n-skip', '');

    LANGS.forEach(function (code) {
      var b = document.createElement('button');
      b.type = 'button';
      b.textContent = NAMES[code];
      b.setAttribute('lang', code);
      b.title = { bg: 'Български', en: 'English', ro: 'Română' }[code];
      if (code === lang) b.classList.add('active');
      b.addEventListener('click', function () { setLang(code); });
      box.appendChild(b);
    });
    host.appendChild(box);
  }

  function markActive() {
    var btns = document.querySelectorAll('.i18n-switch button');
    for (var i = 0; i < btns.length; i++) {
      btns[i].classList.toggle('active', btns[i].getAttribute('lang') === lang);
    }
  }

  // --- избор на език -------------------------------------------------
  function detect() {
    var saved;
    try { saved = localStorage.getItem(STORAGE); } catch (e) { saved = null; }
    if (saved && LANGS.indexOf(saved) !== -1) return saved;

    var nav = (navigator.language || navigator.userLanguage || '').toLowerCase();
    for (var i = 0; i < LANGS.length; i++) {
      if (nav.indexOf(LANGS[i]) === 0) return LANGS[i];
    }
    // Езикът на браузъра не е сред поддържаните → английски
    return FALLBACK;
  }

  function setLang(code) {
    if (LANGS.indexOf(code) === -1) return;
    lang = code;
    try { localStorage.setItem(STORAGE, code); } catch (e) {}
    applyAll();
    markActive();
    document.dispatchEvent(new CustomEvent('i18n:change', { detail: { lang: code } }));
  }

  window.I18N = { t: t, set: setLang, get lang() { return lang; }, langs: LANGS };

  function init() {
    lang = detect();
    buildSwitch();
    applyAll();
    startObserver();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
