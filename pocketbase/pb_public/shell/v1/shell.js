/* ══════════════════════════════════════════════════════════════════
   Оболочка Togetherly: одна шапка и один подвал на все сайты.

     <script src="https://togetherly.day/shell/v1/shell.js" data-site="games"></script>

   Скрипт сам вставляет шапку первым элементом <body> и подвал последним,
   подсвечивает текущий сайт и рисует состояние аккаунта.

   Аккаунт общий, и держится это на ОДНОЙ вещи: токен сессии живёт в cookie
   с Domain=.togetherly.day, а не в localStorage. Хранилище привязано к
   origin, поэтому вход на профиле для игр был бы невидим. Читает и пишет
   cookie только этот файл — сайты зовут TG.token() и TG.setToken().
   ══════════════════════════════════════════════════════════════════ */
(function () {
  'use strict';

  var API   = 'https://togetherly.day';
  var COOK  = 'tg_session';
  var self  = document.currentScript;
  var SITE  = (self && self.dataset.site) || '';
  var NOHEAD = self && self.dataset.head === 'off';
  /* Язык у игр — это РАЗНЫЕ адреса (/en/...), а не переключатель в скрипте:
     иначе поисковик видит одну страницу и весь нерусский трафик теряется.
     Поэтому сайт сам передаёт, куда ведёт вторая версия этой же страницы. */
  var LANG    = (self && self.dataset.lang) || '';
  var LANGALT = (self && self.dataset.langAlt) || '';
  var NOFOOT = self && self.dataset.foot === 'off';

  var SITES = [
    { id: 'app',     name: 'Приложение', icon: 'smartphone', href: 'https://togetherly.day/' },
    { id: 'games',   name: 'Игры',       icon: 'joystick',   href: 'https://games.togetherly.day/' },
    { id: 'profile', name: 'Профиль',    icon: 'mail',       href: 'https://profile.togetherly.day/' },
    { id: 'watch',   name: 'Смотреть',   icon: 'movie',      href: 'https://togetherly.day/watch/room/' },
  ];
  var TITLES = { app: '', games: 'игры', profile: 'профиль', watch: 'просмотр' };

  /* ── cookie на общий домен ─────────────────────────────────────
     Срок — год: PocketBase сам решает, жив ли токен, а короткая кука
     выкидывала бы человека раньше времени. */
  function readCookie(name) {
    var m = document.cookie.match(new RegExp('(?:^|; )' + name + '=([^;]*)'));
    return m ? decodeURIComponent(m[1]) : '';
  }
  function writeCookie(name, value, days) {
    var host = location.hostname;
    var base = /(^|\.)togetherly\.day$/.test(host) ? '; Domain=.togetherly.day' : '';
    var exp = days > 0
      ? '; Max-Age=' + (days * 86400)
      : '; Expires=Thu, 01 Jan 1970 00:00:00 GMT';
    document.cookie = name + '=' + encodeURIComponent(value) + '; Path=/' + base + exp +
      '; SameSite=Lax' + (location.protocol === 'https:' ? '; Secure' : '');
  }

  /* Тема тоже общая: выбрал тёмную на играх — она тёмная и в профиле.
     Поэтому cookie, а не localStorage. Сайт может не поддерживать тему вовсе
     (лендинг) — тогда атрибут просто никем не читается и ничего не портит. */
  var THEME = 'tg_theme';
  function applyTheme(mode) {
    document.documentElement.setAttribute('data-theme', mode);
    writeCookie(THEME, mode, 365);
    var b = document.querySelector('.tg-theme');
    if (b) {
      b.querySelector('.tg-ms').textContent = mode === 'dark' ? 'light_mode' : 'dark_mode';
      b.title = mode === 'dark' ? 'Светлая тема' : 'Тёмная тема';
    }
  }

  var TG = window.TG = {
    api: API,
    theme: function () { return document.documentElement.getAttribute('data-theme') || 'light'; },
    setTheme: applyTheme,
    token: function () { return readCookie(COOK); },
    setToken: function (t) { writeCookie(COOK, t || '', t ? 365 : 0); },
    signOut: function () { TG.setToken(''); location.reload(); },
    /* Перерисовать шапку после входа или выхода: она строится один раз при
       загрузке, и без этого остаётся гостевой на том самом сайте, где человек
       только что вошёл. */
    refresh: function () {
      TG._me = null;
      var old = document.querySelector('.tg-shell-head');
      if (old) old.replaceWith(buildHead());
    },
    /* Профиль спрашиваем один раз на страницу: имя и аватар нужны только шапке. */
    me: function () {
      if (TG._me) return TG._me;
      var t = TG.token();
      if (!t) return (TG._me = Promise.resolve(null));
      TG._me = fetch(API + '/api/profile/web', { headers: { Authorization: t } })
        .then(function (r) { return r.ok ? r.json() : null; })
        .catch(function () { return null; });
      return TG._me;
    },
  };

  function el(tag, cls, html) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (html != null) n.innerHTML = html;
    return n;
  }
  function esc(s) {
    return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;')
      .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  /* ── шрифты ──────────────────────────────────────────────────
     Сайт мог не подключить Material Symbols — тогда вместо значков
     вылезли бы их имена словами. Добавляем, если тега ещё нет. */
  function ensureFonts() {
    var need = [
      'https://fonts.googleapis.com/css2?family=Unbounded:wght@400;600;700;800&family=Onest:wght@400;500;600;700&display=swap',
      'https://fonts.googleapis.com/css2?family=Material+Symbols+Rounded:opsz,wght,FILL,GRAD@24,400,1,0&display=block',
    ];
    need.forEach(function (href) {
      var key = href.split('family=')[1].split(':')[0];
      if (document.querySelector('link[href*="family=' + key + '"]')) return;
      var l = document.createElement('link');
      l.rel = 'stylesheet'; l.href = href;
      document.head.appendChild(l);
    });
  }

  /* ── шапка ── */
  function buildHead() {
    var head = el('header', 'tg-shell-head');
    var tail = TITLES[SITE] ? '&nbsp;<span class="tg-site">· ' + esc(TITLES[SITE]) + '</span>' : '';
    head.innerHTML =
      '<a class="tg-brand" href="' + (SITE === 'app' ? '/' : API + '/') + '">' +
        '<img src="' + API + '/shell/v1/app-icon.webp" alt="" width="30" height="30">' +
        'Togetherly' + tail + '</a>' +
      '<nav class="tg-switch">' + SITES.map(function (s) {
        return '<a href="' + s.href + '"' + (s.id === SITE ? ' class="on"' : '') + '>' +
          '<span class="tg-ms">' + s.icon + '</span><span>' + esc(s.name) + '</span></a>';
      }).join('') + '</nav>' +
      '<span class="tg-sp"></span>' +
      (LANG && LANGALT
        ? '<nav class="tg-switch tg-lang">' +
            '<a class="on" href="' + esc(location.pathname) + '">' + esc(LANG.toUpperCase()) + '</a>' +
            '<a href="' + esc(LANGALT) + '">' + esc(LANG === 'ru' ? 'EN' : 'RU') + '</a>' +
          '</nav>'
        : '') +
      '<button class="tg-icon tg-theme" type="button" title="Тёмная тема">' +
        '<span class="tg-ms">dark_mode</span></button>' +
      '<span class="tg-account"></span>';

    head.querySelector('.tg-theme').addEventListener('click', function () {
      applyTheme(TG.theme() === 'dark' ? 'light' : 'dark');
    });

    var box = head.querySelector('.tg-account');
    if (!TG.token()) {
      box.innerHTML = '<a class="tg-enter" href="https://profile.togetherly.day/">Войти</a>';
    } else {
      // Пока профиль едет, показываем нейтральный кружок: пустое место в шапке
      // прыгает, когда данные доезжают.
      box.innerHTML = '<a class="tg-acc" href="https://profile.togetherly.day/">' +
        '<span class="tg-ava tg-ms" style="font-size:16px">person</span></a>';
      TG.me().then(function (d) {
        var p = d && d.pair && (d.pair.names || []).filter(function (x) { return x.me; })[0];
        if (!p) p = d && d.pair && (d.pair.names || [])[0];
        if (!p) return;
        var letter = (p.name || '?').trim().charAt(0).toUpperCase();
        var a = box.querySelector('.tg-acc');
        a.innerHTML = '<span class="tg-ava">' + esc(letter) + '</span>' +
          '<span class="tg-nm">' + esc(p.name || '') + '</span>';
        if (p.avatar && /^https?:/i.test(p.avatar)) {
          var img = new Image();
          img.alt = '';
          img.onload = function () { a.querySelector('.tg-ava').innerHTML = ''; a.querySelector('.tg-ava').append(img); };
          img.src = p.avatar;
        }
      });
    }
    return head;
  }

  /* ── подвал ── */
  function buildFoot() {
    var col = function (title, links) {
      return '<div class="tg-col"><h5>' + title + '</h5><ul>' + links.map(function (l) {
        return '<li><a href="' + l[1] + '">' + esc(l[0]) + '</a></li>';
      }).join('') + '</ul></div>';
    };
    var f = el('footer', 'tg-shell-foot');
    f.innerHTML =
      '<div class="tg-foot-in"><div class="tg-cols">' +
        '<div class="tg-about"><h4>Togetherly</h4>' +
        '<p>Приложение для двоих: общая лента воспоминаний, чат, холст на двоих, ' +
        'совместный просмотр и виджеты на экране телефона.</p>' +
        '<div class="tg-stores">' +
          '<a class="tg-store" href="https://play.google.com/store/apps/details?id=com.togetherly.love">' +
            '<span class="tg-ms">android</span>Google Play</a>' +
          '<a class="tg-store" href="https://apps.apple.com/app/id6748585863">' +
            '<span class="tg-ms">phone_iphone</span>App Store</a>' +
          '<a class="tg-store" href="https://github.com/THET1ME-1/Togetherly/releases/latest">' +
            '<span class="tg-ms">download</span>APK</a>' +
        '</div></div>' +
        col('ПРОДУКТ', [['Приложение', API + '/'], ['Togetherly+', API + '/#plus'],
                        ['Виджеты', API + '/#widgets'], ['Совместный просмотр', API + '/watch/room/']]) +
        col('САЙТЫ', [['Игры для пар', 'https://games.togetherly.day/'],
                      ['Профиль пары', 'https://profile.togetherly.day/'],
                      ['Открытая разработка', 'https://github.com/THET1ME-1/Togetherly']]) +
        col('ПОДДЕРЖКА', [['Написать в бот', 'https://t.me/TogetherlyBugsBot'],
                          ['Удалить аккаунт', API + '/delete-account/'],
                          ['Безопасность детей', API + '/child-safety/']]) +
      '</div>' +
      '<div class="tg-legal"><span>© ' + new Date().getFullYear() + ' Togetherly</span>' +
        '<span class="tg-sp"></span>' +
        '<a href="' + API + '/privacy-policy/">Конфиденциальность</a>' +
        '<a href="' + API + '/terms/">Условия</a>' +
        '<a href="https://t.me/TogetherlyBugsBot">Контакты</a>' +
      '</div></div><div class="tg-word">TOGETHERLY</div>';
    return f;
  }

  function mount() {
    ensureFonts();
    // Тему ставим ДО вставки шапки: иначе первый кадр рисуется в чужой.
    applyTheme(readCookie(THEME) ||
      (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'));
    if (!NOHEAD && !document.querySelector('.tg-shell-head')) {
      document.body.insertBefore(buildHead(), document.body.firstChild);
    }
    if (!NOFOOT && !document.querySelector('.tg-shell-foot')) {
      document.body.appendChild(buildFoot());
    }
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', mount);
  else mount();
})();
