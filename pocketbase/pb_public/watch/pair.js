/* Канал пары: общее у комнаты совместного просмотра и совместной ленты.
 *
 * Обе страницы живут в одном канале Centrifugo (`watch:<код>`) и говорят на
 * одном языке: `chat`, `hello`, `state` у обеих, свои сообщения у каждой.
 * Здесь — то, что у них одинаковое: вход по сессии Togetherly с ожиданием
 * приложения, подключение с запасным адресом, отправка с придержанием до
 * подписки, счёт зрителей, мост звонка с приложением и подстройка страницы
 * под клавиатуру. Интерфейса тут нет: что показать человеку, решает страница.
 *
 * До 05.10.2026 лента жила поверх страницы комнаты и брала всё это у неё,
 * нажимая спрятанные кнопки. Комната грузилась целиком и мелькала при входе.
 */
(() => {
  'use strict';

  // Два адреса одного и того же Centrifugo, по порядку.
  //
  // Первый ведёт прямо в него, второй — через Caddy. Пока путь был один, через
  // прокси, комната умирала вместе с его перегрузкой: страница открывалась
  // (статику Caddy отдавал), а сокет не поднимался вовсе — `dial tcp
  // 127.0.0.1:8443: i/o timeout`. Со стороны это выглядело как «нас не
  // закидывает в одну комнату» и «не работает интерфейс во время совместного
  // просмотра» (три жалобы за вечер 15.08.2026), хотя сам Centrifugo был
  // здоров и на прямой адрес отвечал мгновенно.
  //
  // Клиент перебирает список сам: не открылся первый — идёт ко второму. Так
  // прямой порт остаётся быстрым путём, а прокси прикрывает сети, где 8443
  // закрыт.
  //
  // Прямой адрес переехал на своё имя 17.08.2026: раньше тут стоял
  // `togetherly.duckdns.org` — поддомен динамического DNS, который человек
  // видел в адресной строке комнаты. `rt.togetherly.day` ведёт на ту же машину
  // и покрыт тем же сертификатом (SAN на оба имени), поэтому вкладки,
  // открытые со старым адресом, продолжают работать.
  // Порядок важен: первым идёт путь через 443 — тот самый, по которому уже
  // пришла эта страница, значит он у человека проходит. Нестандартный 8443 у
  // части операторов не отвергается, а МОЛЧА проглатывается: соединение висит
  // до TCP-таймаута, close не приходит, и перебор внутри centrifuge-js не
  // трогается с места. Со стороны это «у одного всё нажимается, а другой
  // просто существует в комнате» (21.08.2026: четыре живые комнаты, где
  // приложение в канале есть, а страница так и не подписалась).
  const WS = [
    { transport: 'websocket', endpoint: 'wss://togetherly.day/connection/websocket' },
    { transport: 'websocket', endpoint: 'wss://rt.togetherly.day:8443/connection/websocket' },
  ];

  /// Сколько ждём подключения, прежде чем свалиться на запасной адрес.
  const CONNECT_TIMEOUT = 7000;

  /// Сколько раз ждём поручительства приложения, прежде чем сдаться.
  /// Выпущенные сборки открывают страницу без сессии, и пускает их сервер по
  /// СВОЕМУ подключению приложения к каналу, а оно поднимается рядом со
  /// страницей и может не успеть к первому запросу.
  const APP_WAIT_TRIES = 10;
  const APP_WAIT_STEP = 2000;

  /// Что придержать до подписки: реплику, ссылку на ролик и «я здесь».
  /// Команды плеера отбрасываем — через секунду они уже врут о времени.
  const KEEP = { chat: 1, source: 1, file: 1, hello: 1 };

  /** Код комнаты из адреса: всё после `#`, только буквы и цифры. */
  function roomFromHash() {
    return (location.hash || '').replace('#', '').toLowerCase()
      .replace(/[^a-z0-9]/g, '').slice(0, 12);
  }

  /** Страница открыта во встроенном браузере приложения. */
  const inApp = () => !!window.flutter_inappwebview;

  /** Мост приложения, если он умеет отвечать. */
  const bridge = () => {
    const b = window.flutter_inappwebview;
    return b && typeof b.callHandler === 'function' ? b : null;
  };

  /** Имя гостя живёт в браузере: без него каждая перезагрузка вкладки
   *  выглядела бы приходом нового зрителя. */
  function guestId() {
    const KEY = 'watch-guest';
    try {
      const saved = localStorage.getItem(KEY);
      if (/^g[a-z0-9]{14}$/.test(saved || '')) return saved;
      const abc = 'abcdefghijklmnopqrstuvwxyz0123456789';
      const bytes = new Uint8Array(14);
      crypto.getRandomValues(bytes);
      let id = 'g';
      for (let i = 0; i < bytes.length; i++) id += abc[bytes[i] % abc.length];
      localStorage.setItem(KEY, id);
      return id;
    } catch (_) {
      return '';
    }
  }

  /** Зрители считаются по людям, а не по соединениям: у одного человека их
   *  бывает несколько, пока старое не отвалилось.
   *
   *  Приложение вдобавок держит в канале СВОЁ подключение — не ради картинки, а
   *  ради голоса: WebRTC поднимает оно, а зов партнёра ходит по каналу комнаты.
   *  Открыто оно всегда, даже когда никто не звонит, и человек, зашедший один,
   *  видел «смотрят: 2» (жалоба 20.08.2026, подтверждена присутствием живого
   *  канала). Такие подключения помечены в `chan_info` подписки — метку ставит
   *  сервер, поэтому счёт чинится и у выпущенных сборок. */
  function countViewers(presence) {
    const clients = (presence && presence.clients) || {};
    const people = new Set();
    Object.keys(clients).forEach((k) => {
      const c = clients[k] || {};
      const info = c.chanInfo || c.chan_info;
      if (info && info.app) return;
      people.add(c.user);
    });
    return Math.max(1, people.size);
  }

  /** Сессия Togetherly, с которой страница просит пропуск.
   *
   *  Новые сборки приложения кладут её сами (`window.__togetherlyAuth`, скрипт
   *  в начале документа). В браузере она лежит там же, куда её кладёт SDK
   *  PocketBase после входа — на странице комнаты или на /club. Без сессии в
   *  комнату пары не пустят: код мог уйти в чужие руки. */
  function storedAuth() {
    try {
      const given = window.__togetherlyAuth;
      if (given && typeof given.token === 'string' && given.token) {
        return { token: given.token, who: String(given.name || ''), fromApp: true };
      }
    } catch (_) { /* нет — ищем в хранилище */ }
    try {
      const saved = JSON.parse(localStorage.getItem('pocketbase_auth') || 'null');
      if (saved && typeof saved.token === 'string' && saved.token) {
        const rec = saved.record || saved.model || {};
        return { token: saved.token, who: String(rec.email || rec.name || ''), fromApp: false };
      }
    } catch (_) { /* хранилище закрыто */ }
    return null;
  }

  // ── канал ────────────────────────────────────────────────────────────────

  /** Пропуск в канал: токены подключения и подписки. Отказ сервера помечается
   *  `denied` — это не обрыв связи, а повод сказать человеку, что делать. */
  async function ticket(room) {
    const headers = { 'Content-Type': 'application/json' };
    const auth = storedAuth();
    if (auth) headers.Authorization = auth.token;
    const res = await fetch('/api/watch/token', {
      method: 'POST',
      headers,
      body: JSON.stringify({ room, guest: guestId() }),
    });
    let data = {};
    try { data = await res.json(); } catch (_) { data = {}; }
    if (!data.ok) {
      const err = new Error(data.error || 'token');
      // Голая 404 без тела (маршрута нет, выкладка в процессе) отказом не
      // считается — это поломка, а не «комнаты нет».
      if (data.error && [400, 401, 403, 404].indexOf(res.status) >= 0) err.denied = data.error;
      throw err;
    }
    return data;
  }

  /** Подключиться к каналу комнаты [room].
   *
   *  [on]: `message(data)` — чужое сообщение (свои отсекаются здесь),
   *  `viewers(n)` — сколько людей в канале, `subscribed()` — подписка встала
   *  (и после переподключения тоже), `status(kind)` — `ready`, `offline`,
   *  `lost`. Возвращает канал: `me`, `send(type, at, extra)`, `subscribed()`,
   *  `viewers()`. */
  async function open(room, on) {
    const h = on || {};
    const ch = {
      room, me: '', centrifuge: null, sub: null, isSubscribed: false, count: 1, outbox: [],
      subscribed: () => ch.isSubscribed,
      viewers: () => ch.count,
      send: (type, at, extra) => send(ch, type, at, extra),
    };
    let fallbackTried = false;

    const attach = async () => {
      const data = await ticket(room);
      ch.me = data.userId;

      const centrifuge = new Centrifuge(WS, { token: data.connectionToken });
      const sub = centrifuge.newSubscription(data.channel, { token: data.subscriptionToken });

      const refreshViewers = () => {
        sub.presence().then((p) => {
          ch.count = countViewers(p);
          if (h.viewers) h.viewers(ch.count);
        }).catch(() => {});
      };

      sub.on('publication', (ctx) => {
        const msg = ctx.data;
        if (!msg || msg.from === ch.me) return;
        if (h.message) h.message(msg);
      });
      sub.on('subscribed', () => {
        ch.isSubscribed = true;
        if (h.status) h.status('ready');
        refreshViewers();
        flush(ch);
        // Просим тех, кто уже внутри, прислать своё: ролик, переписку.
        send(ch, 'hello');
        if (h.subscribed) h.subscribed(ch);
      });
      sub.on('join', refreshViewers);
      sub.on('leave', refreshViewers);
      sub.on('unsubscribed', () => { ch.isSubscribed = false; });
      sub.on('subscribing', () => { ch.isSubscribed = false; });
      sub.on('error', () => { if (h.status) h.status('lost'); });

      centrifuge.on('connected', () => { if (h.status) h.status('ready'); });
      centrifuge.on('disconnected', () => { if (h.status) h.status('offline'); });

      sub.subscribe();
      centrifuge.connect();
      ch.centrifuge = centrifuge;
      ch.sub = sub;

      // Сторож висящего порта: если за CONNECT_TIMEOUT подключиться не вышло,
      // пересобираем клиента на СЛЕДУЮЩЕМ адресе. Своими силами centrifuge-js
      // этого не сделает — ему нужен close, а заблокированный порт его не даёт.
      if (!fallbackTried) {
        setTimeout(() => {
          if (ch.isSubscribed || centrifuge.state === 'connected') return;
          fallbackTried = true;
          try { centrifuge.disconnect(); } catch (_) {}
          WS.reverse();
          attach().catch(() => { if (h.status) h.status('lost'); });
        }, CONNECT_TIMEOUT);
      }
    };

    await attach();
    return ch;
  }

  // Публиковать в канал разрешено ТОЛЬКО подписчику (allow_publish_for_subscriber),
  // а подписка ставится раундтрипом с токеном. Отправка до неё — это
  // «103 permission denied» на сервере и потерянное сообщение: у себя реплика
  // появляется, до партнёра не доходит. Так и выглядела жалоба «чат в
  // совместном просмотре перестал работать» (19 августа 2026): подписка рвётся
  // при каждом обрыве связи, а send этого не проверял.
  function send(ch, type, at, extra) {
    if (!ch.sub) return;
    const payload = Object.assign({ t: type, at: at || 0, from: ch.me }, extra || {});
    if (ch.isSubscribed) {
      ch.sub.publish(payload).catch(() => {});
      return;
    }
    if (KEEP[type]) {
      ch.outbox.push(payload);
      if (ch.outbox.length > 20) ch.outbox.shift();
    }
  }

  /** Слить придержанное — зовётся, когда подписка встала. */
  function flush(ch) {
    if (!ch.sub || !ch.isSubscribed) return;
    ch.outbox.splice(0, ch.outbox.length).forEach((p) => ch.sub.publish(p).catch(() => {}));
  }

  /** Войти в комнату: [open] с ожиданием приложения.
   *
   *  Старые сборки приложения сессию странице не дают, их пускает сервер по
   *  подключению самого приложения — оно поднимается рядом и может не успеть.
   *  Поэтому `auth_required` во встроенном браузере — повод подождать
   *  (`on.status('connecting')`), а не отказ. [waitApp] = false — не ждать:
   *  человек только что вошёл сам. Отказ сервера отклоняет обещание ошибкой с
   *  `denied`: `auth_required`, `not_member`, `not_found`. */
  async function enter(room, on, waitApp) {
    let tries = waitApp === false ? APP_WAIT_TRIES : 0;
    for (;;) {
      try {
        return await open(room, on);
      } catch (err) {
        if (err && err.denied === 'auth_required' && inApp() && tries < APP_WAIT_TRIES) {
          tries += 1;
          if (on && on.status) on.status('connecting');
          await new Promise((r) => setTimeout(r, APP_WAIT_STEP));
          continue;
        }
        throw err;
      }
    }
  }

  // ── звонок ───────────────────────────────────────────────────────────────

  /// Голос: связь в приложении, кнопки на странице.
  ///
  /// Микрофон, WebRTC и сигналинг живут в приложении — страница только
  /// показывает состояние и отправляет нажатия мостом. Состояние приложение
  /// присылает вызовом `window.watchVoiceState({state, micOn})`, где state —
  /// off, connecting, live, failed. Первое значение может прийти раньше этого
  /// файла: тогда его запомнил скрипт в начале страницы (`__voicePending`).
  ///
  /// Кнопку страница показывает НЕ по наличию моста, а после первого ответа
  /// приложения. Мост есть в любой сборке с WebView, включая выпущенные до
  /// 20.08.2026 — они про звонок из страницы не знают и рисуют свою полосу
  /// снизу. Появись кнопка у них, человек нажимал бы на мёртвое.
  const voice = (() => {
    const fns = [];
    let last = window.__voicePending || null;
    window.watchVoiceState = (s) => {
      last = s || {};
      fns.slice().forEach((fn) => { try { fn(last); } catch (_) {} });
    };
    return {
      /** Звонить отсюда в принципе можно: страница во встроенном браузере. */
      bridged: () => !!bridge(),
      /** Подписаться на состояние; последнее известное приходит сразу. */
      onState(fn) {
        fns.push(fn);
        if (last) fn(last);
      },
      /** Нажатие: call, hangup, mic. */
      say(action) {
        const b = bridge();
        if (!b) return;
        try { b.callHandler('watchVoice', { action }); } catch (_) {
          // Мост пропал вместе с экраном — делать тут нечего.
        }
      },
    };
  })();

  // ── клавиатура ───────────────────────────────────────────────────────────

  /// Держит высоту страницы равной ВИДИМОЙ области: `--vph`, `--vpt`,
  /// `--vph-full` и класс `typing` на теле, пока открыта клавиатура.
  ///
  /// На iPhone клавиатура не уменьшает 100dvh внутри WKWebView: страница
  /// остаётся во весь экран, поле прячется под клавиатурой, а прокрутки у
  /// страницы нет (`overflow: hidden`). Человек тапает по полю, печатает и не
  /// видит ни строки, ни результата — жалоба «ссылка не вводится на iOS».
  /// visualViewport знает настоящую высоту, отдаём её в CSS. [fields] —
  /// поля ввода страницы: по ним снимается класс и возвращается прокрутка.
  function viewport(fields) {
    const vv = window.visualViewport;
    // Высота видимого: visualViewport точнее, но без него остаётся окно —
    // раньше страница в таком случае не делала ничего и жила на 100dvh.
    const seen = () => (vv ? vv.height : window.innerHeight);
    const shift = () => (vv ? vv.offsetTop : 0);
    // Клавиатура СЧИТАЕТСЯ открытой, когда видимая область заметно меньше окна.
    // Раньше сжатие кадра включал сам фокус — и на десктопе, где никакая
    // клавиатура не выезжает, страница всё равно подпрыгивала: кадр ужимался,
    // нижний ряд уезжал вверх на 166 px, а палец бил в то место, где кнопка
    // «Включить» была секунду назад. Отсюда жалобы «кнопка не работает» и
    // «сообщение не отправляется» — нажатие промахивалось мимо уехавшей кнопки.
    const keyboardOpen = () => seen() < window.innerHeight * 0.8;
    let lastH = -1;
    let lastT = -1;
    // Полная высота экрана при этой ширине — без клавиатуры. На Android
    // клавиатура урезает окно целиком, и `keyboardOpen` её не видит; плеер
    // ленты, считавший ширину от урезанной высоты, сужался до края экрана и
    // показывал свои кнопки — лайки и счётчик TikTok (05.10.2026). Новая
    // ширина (поворот) сбрасывает запомненное.
    let fullW = -1;
    let fullH = 0;
    const apply = () => {
      const h = seen();
      const t = shift();
      const w = window.innerWidth;
      const root = document.documentElement.style;
      if (Math.abs(w - fullW) > 1) { fullW = w; fullH = 0; }
      if (h > fullH) { fullH = h; root.setProperty('--vph-full', fullH + 'px'); }
      if (Math.abs(h - lastH) < 1 && Math.abs(t - lastT) < 1) return;
      lastH = h;
      lastT = t;
      root.setProperty('--vph', h + 'px');
      // Клавиатура не только урезает видимое, но и прокручивает документ:
      // без этого сдвига страница уезжает вверх, а прокрутки у неё нет.
      root.setProperty('--vpt', t + 'px');
      document.body.classList.toggle('typing', keyboardOpen());
    };
    apply();
    if (vv) {
      vv.addEventListener('resize', apply);
      vv.addEventListener('scroll', apply);
    }
    // Окно и поворот: события visualViewport шлёт СИСТЕМА — на клавиатуру и
    // поворот экрана. В приложении высоту WebView меняет сам Flutter, и до
    // страницы это доходит не всегда.
    window.addEventListener('resize', apply);
    window.addEventListener('orientationchange', apply);
    if (window.ResizeObserver) {
      new ResizeObserver(apply).observe(document.documentElement);
    }
    // Последняя страховка — сверка раз в полсекунды. Дешёвая (два числа) и
    // единственная, что спасает самый глухой WebView: 20.08.2026 два человека
    // с айфонов написали «опять ничего не нажимается, даже после обновления».
    // Страница держала высоту прежнего экрана, поле сообщения и «Отправить»
    // оставались за нижним краем WebView, а прокрутки у страницы нет.
    setInterval(apply, 500);
    for (const sel of fields || []) {
      const el = document.querySelector(sel);
      if (!el) continue;
      el.addEventListener('blur', () => {
        // Класс снимет apply(), когда клавиатура уедет и вьюпорт вернёт высоту.
        // Здесь его не трогаем: blur приходит и при переходе между полями.
        if (!keyboardOpen()) document.body.classList.remove('typing');
      });
      el.addEventListener('focus', () => {
        // Safari сам прокручивает документ к полю, а страница прибита к видимой
        // области — от такой прокрутки она только уезжает. Возвращаем на место,
        // когда клавиатура доехала.
        setTimeout(() => window.scrollTo(0, 0), 300);
      });
    }
  }

  window.TgPair = {
    roomFromHash, inApp, bridge, guestId, countViewers, storedAuth,
    open, enter, voice, viewport,
    APP_WAIT_TRIES,
  };
})();
