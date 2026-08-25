/* Комната совместного просмотра.
 *
 * Сервер ничего не хранит: комната — это канал в Centrifugo, который живёт,
 * пока в нём есть люди. Ссылка на видео и переписка существуют только в
 * открытых вкладках.
 *
 * Синхронизация: тот, кто трогает плеер, шлёт в канал своё состояние
 * (играет/пауза + секунда). Остальные подтягиваются, если разошлись больше
 * чем на полторы секунды — иначе дёрганье от каждого мелкого расхождения.
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
  const DRIFT = 1.5;          // допустимое расхождение, секунды
  const HEARTBEAT = 3000;     // как часто ведущий шлёт своё время

  const $ = (sel) => document.querySelector(sel);
  const state = {
    room: '', channel: '', me: '', centrifuge: null, sub: null,
    player: null, kind: '', applying: false, lead: false, actedAt: 0, lastSent: 0, viewers: 1,
    subscribed: false, outbox: [], lastLink: '', wsFallbackTried: false,
    // Что показывать пришедшему позже: ссылка, переписка этой вкладки и
    // отложенная команда для плеера, который ещё грузится.
    url: '', log: [], synced: false, pending: null, joinedAt: 0,
    // Ролик из адреса комнаты (?src=): включаем его, как только канал ожил.
    wanted: '',
    // Как подписывать свои сообщения. Приложение присылает имя (?name=), у
    // гостя из браузера его нет — он остаётся «Гостем».
    name: '',
    // Файл с диска: сам он никуда не уходит, партнёру достаётся только имя,
    // чтобы он открыл у себя такой же.
    file: null,
    // VK и Rutube не отвечают на вопросы, а сами рассказывают о себе
    // событиями: последнее услышанное держим здесь.
    remote: { time: 0, playing: false, ready: false },
  };
  const LOG_LIMIT = 60;

  const PLATFORMS = [
    ['YouTube', '#FF0033', 'M8 5.5v13l11-6.5z'],
    ['VK', '#0077FF', 'M4 7h3c.4 3.6 2 5.6 3.2 5.9V7h2.8v4.3c1.2-.1 2.4-1.5 2.8-4.3H19c-.3 2.2-1.4 3.9-2.4 4.6 1 .6 2.3 2 2.9 4.4h-3c-.5-1.6-1.6-2.9-3-3v3H10C6.7 16 4.6 12.4 4 7z'],
    ['Rutube', 'currentColor', 'M5 6h9.5c2.2 0 3.5 1.2 3.5 3s-1.3 3-3.5 3H12l4 6h-3l-3.6-6H8v6H5V6zm3 2.4v2.2h6c.7 0 1.1-.4 1.1-1.1S14.7 8.4 14 8.4H8z'],
    ['Vimeo', '#17D5FF', 'M20 8.8c-.1 2-1.5 4.7-4.2 8.2-2.8 3.6-5.2 5.4-7.1 5.4-1.2 0-2.2-1.1-3-3.3l-1.6-6C3.5 10.9 3 9.8 2.4 9.8c-.1 0-.6.3-1.4.9L0 9.6c1-.9 2-1.8 3-2.7 1.3-1.2 2.3-1.8 3-1.8 1.6-.2 2.6 1 3 3.4.4 2.7.7 4.3.9 5 .5 2.3 1 3.4 1.6 3.4.5 0 1.2-.7 2.1-2.2.9-1.4 1.4-2.5 1.5-3.3.1-1-.3-1.5-1.4-1.5-.5 0-1 .1-1.5.3.9-3.1 2.7-4.6 5.3-4.5 1.9.1 2.8 1.4 2.7 3.8z'],
  ];

  function drawPlatforms(el, size) {
    if (!el) return;
    el.innerHTML = PLATFORMS.map(([name, color, path]) =>
      `<span class="chip"><svg viewBox="0 0 24 24" width="${size}" height="${size}" ` +
      `aria-hidden="true"><path d="${path}" fill="${color}"/></svg>${name}</span>`
    ).join('');
  }

  // ── комната ───────────────────────────────────────────────────────────────

  function roomFromHash() {
    return (location.hash || '').replace('#', '').toLowerCase()
      .replace(/[^a-z0-9]/g, '').slice(0, 12);
  }

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

  function newRoom() {
    // Без похожих символов: код диктуют голосом.
    const abc = 'abcdefghjkmnpqrstuvwxyz23456789';
    let out = '';
    for (let i = 0; i < 6; i++) out += abc[Math.floor(Math.random() * abc.length)];
    return out;
  }

  // ── источники видео ───────────────────────────────────────────────────────

  /** Достаёт из введённого настоящий адрес: первый и без соседей.
   *
   *  В поле уже лежит ссылка (приложение кладёт её параметром `?src=`), и
   *  вставка добавляется к ней, а не заменяет: в историю за 12–13 августа
   *  легло 49 включений вида `<ссылка> <та же ссылка>`, `<ютуб><ivi>` и
   *  `hhttps://…`. Человек при этом смотрит прежний ролик и думает, что кнопка
   *  сломана. Само поле теперь выделяется при нажатии, но выпущенные сборки
   *  открывают комнату с прежним адресом, поэтому чистим и здесь. */
  function cleanLink(raw) {
    let s = String(raw == null ? '' : raw).trim();
    if (!s) return '';
    // Лишняя буква перед схемой — палец задел клавишу мимо поля.
    s = s.replace(/(^|\s)[a-z](https?:\/\/)/i, '$1$2');
    const at = s.search(/https?:\/\//i);
    // Схемы нет вовсе. Мобильные браузеры её давно не показывают, поэтому из
    // адресной строки копируется «youtu.be/xxx» — `new URL()` такое не берёт, и
    // включение молча срывалось («ссылку вставляем, а видео не включается»,
    // 24.08.2026). Дописываем схему сами, если в строке есть что-то похожее на
    // домен; обычный текст остаётся текстом и честно получает отказ.
    if (at < 0) {
      const bare = s.match(/(^|\s)((?:[a-z0-9-]+\.)+[a-z]{2,}(?:[/?#][^\s]*)?)/i);
      return bare ? 'https://' + bare[2] : s;
    }
    let one = s.slice(at).split(/\s/)[0];
    // Вторая ссылка прилипла без пробела: режем по её схеме.
    const more = one.slice(1).search(/https?:\/\//i);
    if (more >= 0) one = one.slice(0, more + 1);
    return one;
  }

  /** Разбирает ссылку в описание источника или null, если площадка чужая. */
  function parseSource(raw) {
    let url;
    try {
      url = new URL(cleanLink(raw));
    } catch (_) {
      return null;
    }
    const host = url.hostname.replace(/^www\./, '');

    if (host === 'youtu.be') {
      return { kind: 'youtube', id: url.pathname.slice(1) };
    }
    if (host.endsWith('youtube.com')) {
      const v = url.searchParams.get('v');
      if (v) return { kind: 'youtube', id: v };
      const m = url.pathname.match(/\/(embed|shorts|live)\/([^/?]+)/);
      if (m) return { kind: 'youtube', id: m[2] };
    }
    if (host.endsWith('vimeo.com')) {
      const m = url.pathname.match(/\/(\d+)/);
      if (m) return { kind: 'vimeo', id: m[1] };
    }
    if (host.endsWith('vk.com') || host.endsWith('vkvideo.ru')) {
      // vk.com/video-123_456 либо ?z=video-123_456
      const m = (url.pathname + url.search).match(/video(-?\d+)_(\d+)/);
      if (m) return { kind: 'vk', id: m[1] + '_' + m[2] };
    }
    if (host.endsWith('rutube.ru')) {
      // Шортсы играют тем же встроенным плеером, что и обычные ролики, а путь
      // у них свой — раньше в комнату их было не поставить.
      const m = url.pathname.match(/\/(?:video|shorts)\/([0-9a-f]+)/);
      if (m) return { kind: 'rutube', id: m[1] };
    }
    if (host.endsWith('disk.yandex.ru') || host.endsWith('disk.yandex.com') || host === 'yadi.sk') {
      // Диск отдаёт настоящую ссылку на файл через открытый API, поэтому
      // видео играет в нашем плеере и синхронизируется посекундно.
      return { kind: 'yadisk', id: url.href };
    }
    if (host.endsWith('dropbox.com')) {
      // dl=1 превращает страницу в сам файл.
      url.searchParams.delete('dl');
      url.searchParams.set('raw', '1');
      return { kind: 'video', id: url.href };
    }
    if (host === 'mega.nz' || host === 'mega.io') {
      const m = url.pathname.match(/\/(?:file|embed)\/([^/]+)/);
      if (m) return { kind: 'mega', id: m[1] + url.hash };
    }
    if (host === 'drive.google.com') {
      // Диск отдаёт только свой просмотрщик: файл он не выдаёт, а плеером
      // изнутри управлять нельзя — отсюда режим пульта ниже.
      const m = url.pathname.match(/\/file\/d\/([^/]+)/);
      if (m) return { kind: 'drive', id: m[1] };
    }
    // Прямая ссылка на файл: браузер играет её сам, поэтому синхронизация тут
    // такая же точная, как у своего файла с диска.
    if (/\.(mp4|m4v|webm|ogv|ogg|mov)$/i.test(url.pathname)) {
      return { kind: 'video', id: url.href };
    }
    return null;
  }

  function embedUrl(src) {
    switch (src.kind) {
      case 'youtube':
        return `https://www.youtube.com/embed/${src.id}?enablejsapi=1&rel=0&playsinline=1`;
      case 'vimeo':
        return `https://player.vimeo.com/video/${src.id}?api=1&playsinline=1`;
      case 'vk': {
        const [oid, id] = src.id.split('_');
        return `https://vk.com/video_ext.php?oid=${oid}&id=${id}&js_api=1`;
      }
      case 'rutube':
        return `https://rutube.ru/play/embed/${src.id}/`;
      case 'drive':
        return `https://drive.google.com/file/d/${src.id}/preview`;
      case 'mega':
        return `https://mega.nz/embed/${src.id}`;
      default:
        return '';
    }
  }

  // ── плееры ────────────────────────────────────────────────────────────────
  //
  // У каждой площадки свой способ управления. Общий интерфейс: play, pause,
  // seek, time. Где площадка не отдаёт время (VK, Rutube), синхронизация идёт
  // «вслепую»: команды доходят, а положение подтягивается при старте.

  /** Свой файл и прямая ссылка играют в обычном <video>: полное управление,
   *  секунда в секунду. */
  function mountVideo(src, label) {
    const holder = $('#player');
    holder.innerHTML = '';
    const v = document.createElement('video');
    // Реферера здесь быть не должно (Яндекс отвечает 403), и его снимает
    // страничная мета в index.html. Вешать `referrerPolicy` на сам тег
    // бесполезно: у медиа-элементов такого атрибута нет, запрос всё равно
    // уходит с реферером — проверено, файл после этого не открывается.
    v.src = src;
    v.controls = true;
    v.playsInline = true;
    v.preload = 'metadata';
    v.className = 'player__video';
    holder.appendChild(v);

    state.kind = 'video';
    state.player = { video: v };
    setManual(false);

    const tell = (cmd) => {
      if (state.applying) return;
      leadHere();
      send(cmd, v.currentTime);
    };
    v.addEventListener('play', () => tell('play'));
    v.addEventListener('pause', () => tell('pause'));
    // Из перемотки уходит только «играем». Браузер держит `paused`, пока
    // догружает кусок после прыжка, и прежнее `tell(v.paused ? …)` рассылало
    // партнёру ложную паузу — у обоих ролик замирал. Настоящую паузу шлёт
    // событие `pause`, оно никуда не делось.
    v.addEventListener('seeked', () => { if (!v.paused) tell('play'); });

    if (state.pending) {
      const p = state.pending;
      state.pending = null;
      v.addEventListener('loadedmetadata', () => apply(p.cmd, p.at), { once: true });
    }
    setStatus(label);
  }

  /** Партнёр включил свой файл: показываем, какой именно, и ждём такой же. */
  function askForFile(info) {
    const holder = $('#player');
    holder.innerHTML = '';
    const box = document.createElement('div');
    box.className = 'player__empty';
    const title = document.createElement('span');
    title.textContent = I18N.t('room.fileWanted', { name: info.name });
    const btn = document.createElement('button');
    btn.className = 'btn btn--light btn--compact';
    btn.textContent = I18N.t('room.fileChoose');
    btn.addEventListener('click', () => $('#file').click());
    box.appendChild(title);
    box.appendChild(btn);
    holder.appendChild(box);
    state.file = info;
    state.kind = '';
  }

  function openLocalFile(file) {
    const info = { name: file.name, size: file.size };
    mountVideo(URL.createObjectURL(file), I18N.t('room.filePlaying', { name: file.name }));
    state.url = '';
    state.file = info;
    send('file', 0, info);
    reportSource({ kind: 'file', id: file.name }, 'file://' + file.name);
  }

  /** Публичная ссылка Диска ведёт на страницу, а нам нужен сам файл: его адрес
   *  выдаёт открытый API Яндекса. Ссылка временная, поэтому каждый участник
   *  запрашивает её у себя. */
  function mountYaDisk(publicUrl) {
    setStatus(I18N.t('room.resolving'));
    const api = 'https://cloud-api.yandex.net/v1/disk/public/resources/download?public_key='
      + encodeURIComponent(publicUrl);
    fetch(api, { referrerPolicy: 'no-referrer' })
      .then((r) => r.json())
      .then((d) => {
        if (!d || !d.href) throw new Error('no href');
        state.url = publicUrl;
        mountVideo(d.href, I18N.t('room.playing', { name: labels.yadisk }));
        reportSource({ kind: 'yadisk', id: publicUrl }, publicUrl);
      })
      .catch(() => setStatus(I18N.t('room.badLink')));
  }

  function mountPlayer(src, url) {
    if (src.kind === 'yadisk') {
      state.kind = 'yadisk';
      setManual(false);
      mountYaDisk(src.id);
      if (url) state.url = url;
      return;
    }
    if (src.kind === 'video') {
      mountVideo(src.id, I18N.t('room.playing', { name: I18N.t('room.fileSource') }));
      if (url) state.url = url;
      reportSource(src, url || src.id);
      return;
    }

    const holder = $('#player');
    holder.innerHTML = '';
    state.kind = src.kind;
    if (url) state.url = url;
    setManual(!!MANUAL[src.kind]);

    const frame = document.createElement('iframe');
    // Исключение из страничного `no-referrer`: ютуб на запрос без реферера
    // отвечает ошибкой 153 и не играет НИ ОДНОГО ролика (жалоба 1 августа —
    // «совершенно любое видео»). У iframe атрибут referrerpolicy работает и
    // перебивает мету, поэтому площадки снова видят, откуда пришёл человек, а
    // ссылки дисков в теге <video> остаются без реферера.
    frame.referrerPolicy = 'strict-origin-when-cross-origin';
    frame.src = embedUrl(src);
    frame.allow = 'autoplay; fullscreen; encrypted-media; picture-in-picture';
    frame.allowFullscreen = true;
    frame.id = 'frame';
    holder.appendChild(frame);

    if (src.kind === 'youtube') {
      whenYT((ready) => {
        // Пока ждали API, могли включить другой ролик — тогда кадр уже не наш.
        if (!frame.isConnected || state.kind !== 'youtube') return;
        if (!ready) {
          // API не доехал: командовать плеером нечем, зато ролик играет. Отдаём
          // комнате пульт — смотреть по отсчёту всё равно можно.
          setManual(true);
          return;
        }
        state.player = new YT.Player('frame', {
          events: {
            onReady: () => {
              // Позиция, доставшаяся от того, кто уже смотрит: применяем её,
              // как только плеер готов принимать команды.
              if (!state.pending) return;
              apply(state.pending.cmd, state.pending.at);
              state.pending = null;
            },
            onStateChange: (e) => {
              if (state.applying) return;
              if (e.data === YT.PlayerState.PLAYING) { leadHere(); send('play', ytTime()); }
              if (e.data === YT.PlayerState.PAUSED) { leadHere(); send('pause', ytTime()); }
            },
          },
        });
      });
    } else {
      state.player = { frame };
      state.remote = { time: 0, playing: false, ready: false };
      if (src.kind === 'vk') {
        // Плеер VK начинает слушать только после init.
        frame.addEventListener('load', () => talk({ method: 'init' }));
      }
      if (src.kind === 'vimeo') {
        // Vimeo рассказывает о себе только подписчикам, а подписку принимает
        // не раньше, чем поднимется сам. Ловить единственный момент готовности
        // ненадёжно, поэтому просим несколько раз: лишняя подписка безвредна.
        const subscribe = () => {
          ['ready', 'play', 'pause', 'playProgress', 'seeked'].forEach((ev) => {
            talk(JSON.stringify({ method: 'addEventListener', value: ev }));
          });
        };
        frame.addEventListener('load', subscribe);
        [400, 1200, 2500, 4500].forEach((ms) => setTimeout(subscribe, ms));
      }
      // Отложенная команда сама применится, как только плеер отзовётся.
    }
    setStatus(I18N.t('room.playing', { name: labelOf(src.kind) }));
    reportSource(src, url || state.url);
  }

  // ── API ютуба ─────────────────────────────────────────────────────────────
  //
  // Скрипт `iframe_api` грузится по требованию, а не тегом в разметке. Пока он
  // стоял обычным `<script src>`, страница целиком зависела от доступности
  // ютуба: у операторов, которые его замедляют, запрос не отвечает и не рвётся,
  // разбор документа до конца не доходит, room.js не выполняется — и комната
  // открывается мёртвой. Снаружи это выглядит поломкой устройства: заголовок,
  // поля и кнопки на месте, но ни одно нажатие не работает, ссылку не включить,
  // в чат не написать (жалоба с айфона 18.08.2026; у партнёра на Android, где
  // ютуб отвечал, всё работало). Замер: при зависшем youtube.com `load` не
  // наступает и через 25 секунд.
  //
  // Теперь без ютуба живут и чат, и свои файлы, и остальные площадки, а сам он
  // нужен ровно там, где включают его ролик. Стережёт
  // tests/room-youtube-hang.test.js.
  const YT_WAIT = 12000;      // сколько ждём API, прежде чем счесть его недоступным
  let ytAsked = false;
  const ytQueue = [];

  function ytDone(ready) {
    const ok = ready && !!(window.YT && window.YT.Player);
    while (ytQueue.length) ytQueue.shift()(ok);
  }

  /** Зовёт `done(true)`, когда API ютуба готов, и `done(false)`, если он не
   *  доехал: ролик тогда просто играет без синхронизации, под пультом. */
  function whenYT(done) {
    if (window.YT && window.YT.Player) { done(true); return; }
    ytQueue.push(done);
    if (ytAsked) return;
    ytAsked = true;
    // API зовёт эту функцию сам, когда поднимется.
    const prev = window.onYouTubeIframeAPIReady;
    window.onYouTubeIframeAPIReady = () => {
      if (typeof prev === 'function') { try { prev(); } catch (_) { /* чужой обработчик */ } }
      ytDone(true);
    };
    const tag = document.createElement('script');
    tag.src = 'https://www.youtube.com/iframe_api';
    tag.async = true;
    tag.onerror = () => ytDone(false);
    document.head.appendChild(tag);
    // Ютуб чаще не отказывает, а молчит: без своего срока ждали бы вечно.
    setTimeout(() => ytDone(false), YT_WAIT);
  }

  const labels = {
    youtube: 'YouTube', vimeo: 'Vimeo', vk: 'VK Видео', rutube: 'Rutube',
    drive: 'Google Диск', mega: 'MEGA', yadisk: 'Яндекс Диск',
  };
  /** Плеер Google Диска команд не принимает вовсе — только ему нужен пульт. */
  const MANUAL = { drive: true, mega: true };
  const labelOf = (k) => labels[k] || k;

  const ytTime = () => {
    try {
      if (state.kind === 'video') return state.player.video.currentTime || 0;
      if (state.kind === 'vk' || state.kind === 'rutube' || state.kind === 'vimeo') {
        return state.remote.time || 0;
      }
      return state.player.getCurrentTime() || 0;
    } catch (_) { return 0; }
  };

  function apply(cmd, at) {
    state.applying = true;
    try {
      if (state.kind === 'video' && state.player && state.player.video) {
        const v = state.player.video;
        if (Math.abs(v.currentTime - at) > DRIFT) v.currentTime = at;
        if (cmd === 'play') v.play().catch(() => {});
        if (cmd === 'pause') v.pause();
      } else if (state.kind === 'youtube' && state.player && state.player.seekTo) {
        const now = ytTime();
        if (Math.abs(now - at) > DRIFT) state.player.seekTo(at, true);
        if (cmd === 'play') state.player.playVideo();
        if (cmd === 'pause') state.player.pauseVideo();
      } else if (state.kind === 'vk' || state.kind === 'rutube') {
        if (!state.remote.ready) {
          // Плеер ещё не поздоровался: команду выполним, когда он ответит.
          state.pending = { cmd: cmd, at: at };
        } else if (state.kind === 'vk') {
          if (Math.abs(state.remote.time - at) > DRIFT) talk({ method: 'seek', time: at });
          talk({ method: cmd === 'play' ? 'play' : 'pause' });
          state.remote.playing = cmd === 'play';
          state.remote.time = at;
        } else {
          if (Math.abs(state.remote.time - at) > DRIFT) {
            talk(JSON.stringify({ type: 'player:setCurrentTime', data: { time: at } }));
          }
          talk(JSON.stringify({ type: 'player:' + cmd, data: {} }));
          state.remote.playing = cmd === 'play';
          state.remote.time = at;
        }
      } else if (state.kind === 'vimeo') {
        if (Math.abs(state.remote.time - at) > DRIFT) {
          talk(JSON.stringify({ method: 'setCurrentTime', value: at }));
        }
        talk(JSON.stringify({ method: cmd === 'play' ? 'play' : 'pause' }));
        state.remote.playing = cmd === 'play';
        state.remote.time = at;
      }
    } catch (_) { /* плеер ещё не готов — команда придёт со следующим тактом */ }
    // Пока флаг стоит, свои же события плеера в комнату не уходят. Прежние
    // 300 мс были короче буферизации после прыжка: `seeked` приходил уже с
    // опущенным флагом, и ответ улетал партнёру — начиналось эхо. Ставим с
    // запасом на догрузку куска.
    setTimeout(() => { state.applying = false; }, state.kind === 'video' ? 1500 : 2500);
  }

  /** Рассказывает приложению, что сейчас включили: комната живёт во встроенном
   *  браузере, и без этого приложение не знает, что писать в историю. В обычном
   *  браузере вызов просто ничего не делает. */
  function reportSource(src, url) {
    try {
      const bridge = window.flutter_inappwebview;
      if (!bridge || !bridge.callHandler) return;
      const info = { url: url || '', kind: src.kind || '', title: '', thumb: '' };
      if (src.kind === 'youtube') {
        info.thumb = 'https://img.youtube.com/vi/' + src.id + '/hqdefault.jpg';
        try { info.title = state.player.getVideoData().title || ''; } catch (_) { /* ещё грузится */ }
      }
      bridge.callHandler('watchSource', info);
    } catch (_) { /* приложения рядом нет */ }
  }

  // ── чужие плееры ─────────────────────────────────────────────────────────
  //
  // VK принимает объекты {method:'play'}, Rutube — строку {type:'player:play'}.
  // Оба сами рассказывают о паузе, старте и перемотке, поэтому обычная кнопка
  // в плеере работает как команда для обоих.

  /** Команда, пришедшая раньше готовности чужого плеера, ждёт своей минуты. */
  function flushPending() {
    if (!state.pending) return;
    const wanted = state.pending;
    state.pending = null;
    apply(wanted.cmd, wanted.at);
  }

  function talk(payload) {
    try {
      state.player.frame.contentWindow.postMessage(payload, '*');
    } catch (_) { /* кадр ещё не готов */ }
  }

  function onFrameMessage(e) {
    if (!state.player || !state.player.frame || e.source !== state.player.frame.contentWindow) return;

    let msg = e.data;
    if (typeof msg === 'string') {
      try { msg = JSON.parse(msg); } catch (_) { return; }
    }
    if (!msg || typeof msg !== 'object') return;

    let playing = null;
    let time = null;

    if (state.kind === 'vk') {
      if (typeof msg.time === 'number') time = msg.time;
      if (msg.event === 'inited') { state.remote.ready = true; flushPending(); return; }
      if (msg.event === 'started' || msg.event === 'resumed') playing = true;
      if (msg.event === 'paused' || msg.event === 'ended') playing = false;
      if (msg.event === 'seeked') playing = state.remote.playing;
    } else if (state.kind === 'vimeo') {
      const d = msg.data || {};
      if (typeof d.seconds === 'number') time = d.seconds;
      if (msg.event === 'ready') { state.remote.ready = true; flushPending(); return; }
      if (msg.event === 'play' || msg.event === 'playProgress') playing = true;
      if (msg.event === 'pause' || msg.event === 'ended') playing = false;
      if (msg.event === 'seeked') playing = state.remote.playing;
    } else if (state.kind === 'rutube') {
      const d = msg.data || {};
      if (typeof d.time === 'number') time = d.time;
      if (typeof d.currentTime === 'number') time = d.currentTime;
      if (msg.type === 'player:ready') { state.remote.ready = true; flushPending(); return; }
      if (msg.type === 'player:changeState') {
        // Пока крутится реклама, плеер отвечает за неё, а не за фильм.
        if (d.state === 'advert' || d.state === 'buffering' || d.state === 'seeking') return;
        if (d.state === 'playing') { playing = true; state.remote.ready = true; flushPending(); }
        if (d.state === 'pause' || d.state === 'stopped' || d.state === 'completed') playing = false;
      }
    } else {
      return;
    }

    if (time !== null) state.remote.time = time;
    if (playing === null) return;

    const changed = playing !== state.remote.playing;
    state.remote.playing = playing;
    // Пока применяем чужую команду, свои же отголоски обратно не шлём.
    if (changed && !state.applying) send(playing ? 'play' : 'pause', state.remote.time);
  }

  // ── пульт ────────────────────────────────────────────────────────────────
  //
  // Плеер Google Диска, VK и Rutube не отдаёт управление, поэтому кнопки жмёт
  // человек. Комната задаёт момент: обратный отсчёт идёт у обоих сразу.

  function showCountdown(seconds) {
    const holder = $('#player');
    let box = holder.querySelector('.countdown');
    if (!box) {
      box = document.createElement('div');
      box.className = 'countdown';
      holder.appendChild(box);
    }
    let left = seconds;
    const tick = () => {
      box.textContent = left > 0 ? String(left) : I18N.t('room.now');
      if (left < 0) { box.remove(); return; }
      left -= 1;
      setTimeout(tick, 1000);
    };
    tick();
  }

  function flashPause() {
    const holder = $('#player');
    const box = document.createElement('div');
    box.className = 'countdown countdown--pause';
    box.textContent = I18N.t('room.pauseNow');
    holder.appendChild(box);
    setTimeout(() => box.remove(), 2600);
  }

  function setManual(on) {
    const bar = $('#manual');
    if (bar) bar.hidden = !on;
  }

  // ── обмен ────────────────────────────────────────────────────────────────

  // Публиковать в канал разрешено ТОЛЬКО подписчику (allow_publish_for_subscriber),
  // а подписка ставится раундтрипом с токеном. Отправка до неё — это
  // «103 permission denied» на сервере и потерянное сообщение: у себя реплика
  // появляется, до партнёра не доходит. Так и выглядела жалоба «чат в
  // совместном просмотре перестал работать» (19 августа 2026): подписка рвётся
  // при каждом обрыве связи, а send этого не проверял.
  function send(type, at, extra) {
    if (!state.sub) return;
    const payload = Object.assign({ t: type, at: at || 0, from: state.me }, extra || {});
    if (state.subscribed) {
      state.sub.publish(payload).catch(() => {});
      return;
    }
    // Реплику, ссылку на ролик и «я здесь» придержим до подписки, команды
    // плеера отбросим: через секунду они уже врут о времени.
    if (type === 'chat' || type === 'source' || type === 'file' || type === 'hello') {
      state.outbox.push(payload);
      if (state.outbox.length > 20) state.outbox.shift();
    }
  }

  /** Слить придержанное — зовётся, когда подписка встала. */
  function flushOutbox() {
    if (!state.sub || !state.subscribed) return;
    const queued = state.outbox.splice(0, state.outbox.length);
    queued.forEach((payload) => state.sub.publish(payload).catch(() => {}));
  }

  // ── кто кого догоняет ────────────────────────────────────────────────────
  //
  // Своё время раз в три секунды шлёт ТОЛЬКО ведущий. Пока это делали оба,
  // выходила качель: у двоих время всегда немного разное (буфер, сеть, разные
  // телефоны), и каждый, увидев расхождение больше DRIFT, перематывал себя к
  // чужому. Перемотка добавляет буферизацию, расхождение растёт — и дальше они
  // возят друг друга по кругу. Жалоба звучит как «видео само отматывается на
  // несколько секунд, и так очень много раз».
  //
  // Ведущим становится тот, кто сам тронул плеер; получивший чужую команду
  // уступает. Одновременное нажатие оставляет комнату без ведущего до
  // следующего действия — это лучше, чем двое, тянущие друг друга.

  /** Я тронул плеер: дальше комната равняется на меня. */
  function leadHere() { state.lead = true; state.actedAt = Date.now(); }

  /** Скомандовал кто-то другой: равняюсь на него. */
  function followHere() { state.lead = false; }

  /** Команда пришла от соседа — решаем, кто теперь ведёт.
   *
   *  Обычно уступаю: он только что нажал, ему и вести. Но если я нажал
   *  секунду назад (оба включили ролик разом — так и бывает, когда садятся
   *  смотреть), уступать обоим нельзя: комната останется без ведущего, время
   *  никто не выравнивает и партнёры незаметно расходятся на десяток секунд.
   *  Спор разрешаем по идентификатору — он у каждого свой, и оба приходят к
   *  одному ответу без переговоров. */
  function yieldTo(from) {
    if (Date.now() - (state.actedAt || 0) > 3000) { state.lead = false; return; }
    state.lead = String(state.me) < String(from);
  }

  /** Включает ссылку у себя и рассказывает о ней комнате. */
  function applySource(raw) {
    const src = parseSource(raw);
    if (!src) { setStatus(I18N.t('room.badLink')); return false; }
    // В комнату и в историю уходит очищенный адрес, а не всё, что набралось в
    // поле: партнёр получает ссылку тем же путём и разбирает её так же.
    const url = cleanLink(raw);
    $('#link').value = url;
    // Включил ролик — значит и веду: комната равняется на моё время.
    leadHere();
    mountPlayer(src, url);
    send('source', 0, { url: url });
    return true;
  }

  function onMessage(data) {
    if (!data || data.from === state.me) return;
    switch (data.t) {
      case 'play':
      case 'pause':
        yieldTo(data.from);
        apply(data.t, data.at);
        break;
      case 'source': {
        const src = parseSource(data.url);
        if (src) { yieldTo(data.from); $('#link').value = data.url; mountPlayer(src, data.url); }
        break;
      }
      case 'chat':
        remember(data.from, data.name, data.text);
        addMessage(data.name || I18N.t('room.guest'), data.text, false);
        break;
      case 'hello':
        // Кто-то вошёл в уже живую комнату. Сервер ничего не хранит, поэтому
        // ссылку на видео и переписку ему передаёт вкладка того, кто внутри.
        if (!state.url && !state.file && !state.log.length) break;
        send('state', ytTime(), {
          to: data.from,
          url: state.url,
          file: state.file,
          playing: isPlaying(),
          log: state.log.slice(-LOG_LIMIT),
        });
        break;
      case 'state':
        adoptState(data);
        break;
      case 'sync':
        // Ведущий чужое время не догоняет: иначе двое подтягивают друг друга
        // по очереди и ролик дёргается у обоих.
        if (state.lead) break;
        if (state.kind && Math.abs(ytTime() - data.at) > DRIFT) {
          apply(data.playing ? 'play' : 'pause', data.at);
        }
        break;
      case 'countdown':
        showCountdown(3);
        break;
      case 'pauseNow':
        flashPause();
        break;
      case 'file':
        // Файл по сети не передать: партнёр открывает свою копию сам.
        if (state.kind === 'video' && state.file && state.file.name === data.name) break;
        if (!state.kind) askForFile({ name: data.name, size: data.size });
        break;
    }
  }

  /** Переписка живёт только в этой вкладке — из неё же её получает новичок. */
  function remember(from, name, text) {
    state.log.push({ from: from, name: name, text: text });
    if (state.log.length > LOG_LIMIT) state.log.shift();
  }

  const isPlaying = () => {
    try {
      if (state.kind === 'video') return !state.player.video.paused;
      if (state.kind === 'vk' || state.kind === 'rutube' || state.kind === 'vimeo') {
        return state.remote.playing;
      }
      return state.player.getPlayerState() === YT.PlayerState.PLAYING;
    } catch (_) { return false; }
  };

  /** Принимает состояние комнаты: видео с той же секунды и прошлые сообщения. */
  function adoptState(data) {
    if (state.synced || data.to !== state.me) return;
    state.synced = true;
    // Пришёл в комнату, где уже смотрят: веду не я.
    followHere();

    (data.log || []).forEach((m) => {
      remember(m.from, m.name, m.text);
      addMessage(m.name || I18N.t('room.guest'), m.text, m.from === state.me);
    });

    if (state.kind) return;
    if (!data.url) {
      if (data.file) askForFile(data.file);
      return;
    }
    const src = parseSource(data.url);
    if (!src) return;
    $('#link').value = data.url;
    state.pending = { cmd: data.playing ? 'play' : 'pause', at: data.at || 0 };
    mountPlayer(src, data.url);
    // Площадки, кроме YouTube, о готовности не сообщают.
    if (src.kind !== 'youtube') {
      setTimeout(() => {
        if (!state.pending) return;
        apply(state.pending.cmd, state.pending.at);
        state.pending = null;
      }, 1500);
    }
  }

  // ── чат ──────────────────────────────────────────────────────────────────

  function addMessage(who, text, mine) {
    const box = $('#chat');
    const el = document.createElement('div');
    el.className = 'msg' + (mine ? ' msg--mine' : '');
    el.innerHTML = `<span class="msg__who"></span>`;
    el.querySelector('.msg__who').textContent = who;
    el.appendChild(document.createTextNode(text));
    box.appendChild(el);
    box.scrollTop = box.scrollHeight;
  }

  function setStatus(text) {
    const el = $('#status');
    if (el) el.textContent = text;
  }

  function setViewers(n) {
    const was = state.viewers;
    state.viewers = n;
    const el = $('#viewers');
    if (el) el.textContent = n === 1 ? I18N.t('room.alone') : I18N.t('room.viewers', { n });
    // Комната открыта сразу, поэтому приход партнёра отмечаем строкой в чате.
    // Переподключения дают дребезг 1↔2, поэтому строка не чаще раза в полминуты.
    if (n > 1 && was <= 1 && performance.now() - state.joinedAt > 30000) {
      state.joinedAt = performance.now();
      addSystem(I18N.t('room.partnerJoined'));
    }
  }

  function addSystem(text) {
    const box = $('#chat');
    if (!box) return;
    const el = document.createElement('div');
    el.className = 'msg msg--system';
    el.textContent = text;
    box.appendChild(el);
    box.scrollTop = box.scrollHeight;
  }

  // ── подключение ──────────────────────────────────────────────────────────

  async function connect(room) {
    const res = await fetch('/api/watch/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ room, guest: guestId() }),
    });
    const data = await res.json();
    if (!data.ok) throw new Error(data.error || 'token');

    state.room = room;
    state.me = data.userId;
    state.channel = data.channel;

    const centrifuge = new Centrifuge(WS, { token: data.connectionToken });
    const sub = centrifuge.newSubscription(data.channel, {
      token: data.subscriptionToken,
    });

    const refreshViewers = () => {
      sub.presence().then((p) => setViewers(countViewers(p))).catch(() => {});
    };

    sub.on('publication', (ctx) => onMessage(ctx.data));
    sub.on('subscribed', () => {
      state.subscribed = true;
      setStatus(I18N.t('room.ready'));
      refreshViewers();
      flushOutbox();
      // Просим тех, кто уже внутри, прислать ссылку и переписку.
      send('hello');
      // Пришли с готовым роликом (приложение открывает комнату с ?src=):
      // включаем только теперь. До подписки publish уходит в никуда, и партнёр
      // остаётся с пустым экраном — ровно это и ломало свои ролики.
      if (state.wanted && !state.kind) {
        const wanted = state.wanted;
        state.wanted = '';
        applySource(wanted);
      }
    });
    sub.on('join', refreshViewers);
    sub.on('leave', refreshViewers);
    sub.on('unsubscribed', () => { state.subscribed = false; });
    sub.on('subscribing', () => { state.subscribed = false; });
    sub.on('error', () => setStatus(I18N.t('room.lost')));

    centrifuge.on('connected', () => setStatus(I18N.t('room.ready')));
    centrifuge.on('disconnected', () => setStatus(I18N.t('room.offline')));

    sub.subscribe();
    centrifuge.connect();

    state.centrifuge = centrifuge;
    state.sub = sub;

    // Сторож висящего порта: если за CONNECT_TIMEOUT подключиться не вышло,
    // пересобираем клиента на СЛЕДУЮЩЕМ адресе. Своими силами centrifuge-js
    // этого не сделает — ему нужен close, а заблокированный порт его не даёт.
    if (!state.wsFallbackTried) {
      setTimeout(() => {
        if (state.subscribed || centrifuge.state === 'connected') return;
        state.wsFallbackTried = true;
        try { centrifuge.disconnect(); } catch (_) {}
        WS.reverse();
        connect(room).catch(() => setStatus(I18N.t('room.lost')));
      }, CONNECT_TIMEOUT);
    }

    // Ведущий — тот, кто последним трогал плеер: он раз в три секунды шлёт
    // своё время, чтобы вылечить накопленный дрейф. Остальные молчат — до
    // 13 августа 2026 проверки ведущего тут не было, и время слали ОБА.
    setInterval(() => {
      if (!state.lead || !state.kind || !isPlaying()) return;
      send('sync', ytTime(), { playing: true });
    }, HEARTBEAT);
  }

  // ── запуск ───────────────────────────────────────────────────────────────

  function shareLink() {
    return location.origin + location.pathname + '#' + (state.room || roomFromHash());
  }

  window.addEventListener('message', onFrameMessage);

  /// Держит высоту страницы равной ВИДИМОЙ области.
  ///
  /// На iPhone клавиатура не уменьшает 100dvh внутри WKWebView: страница
  /// остаётся во весь экран, строка со ссылкой прячется под клавиатурой, а
  /// прокрутки у комнаты нет (`overflow: hidden`). Человек тапает по полю,
  /// печатает и не видит ни строки, ни результата — жалоба «ссылка не
  /// вводится на iOS». visualViewport знает настоящую высоту, отдаём её в CSS
  /// и заодно подводим сфокусированное поле к глазам.
  function followKeyboard() {
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
    const apply = () => {
      const h = seen();
      const t = shift();
      if (Math.abs(h - lastH) < 1 && Math.abs(t - lastT) < 1) return;
      lastH = h;
      lastT = t;
      const root = document.documentElement.style;
      root.setProperty('--vph', h + 'px');
      // Клавиатура не только урезает видимое, но и прокручивает документ:
      // без этого сдвига страница уезжает вверх, а прокрутки у комнаты нет.
      root.setProperty('--vpt', t + 'px');
      document.body.classList.toggle('typing', keyboardOpen());
    };
    apply();
    if (vv) {
      vv.addEventListener('resize', apply);
      vv.addEventListener('scroll', apply);
    }
    // Окно и поворот: события visualViewport шлёт СИСТЕМА — на клавиатуру и
    // поворот экрана. В приложении высоту WebView меняет сам Flutter (полоса
    // голоса выезжает, когда поднялся канал, и отрезает снизу 84 точки), и до
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
    // оставались за нижним краем WebView, а прокрутки у комнаты нет.
    setInterval(apply, 500);
    for (const id of ['#link', '#message']) {
      const el = $(id);
      if (!el) continue;
      el.addEventListener('blur', () => {
        // Класс снимет apply(), когда клавиатура уедет и вьюпорт вернёт высоту.
        // Здесь его не трогаем: blur приходит и при переходе между полями.
        if (!keyboardOpen()) document.body.classList.remove('typing');
      });
      el.addEventListener('focus', () => {
        // Safari сам прокручивает документ к полю, а комната прибита к видимой
        // области — от такой прокрутки она только уезжает. Возвращаем на место,
        // когда клавиатура доехала. Сжатие кадра включает apply() по факту
        // выехавшей клавиатуры, а не по самому фокусу.
        setTimeout(() => window.scrollTo(0, 0), 300);
      });
    }
  }


  /// Голос: кнопка в шапке комнаты, связь в приложении.
  ///
  /// Микрофон, WebRTC и сигналинг живут в приложении — страница только
  /// показывает состояние и отправляет нажатия мостом. В обычном браузере
  /// моста нет, поэтому группа кнопок остаётся скрытой: звонить там нечем.
  ///
  /// Кнопка появляется НЕ по наличию моста, а после первого ответа
  /// приложения. Мост есть в любой сборке с WebView, включая выпущенные до
  /// 20.08.2026 — они про звонок из страницы не знают и рисуют свою полосу
  /// снизу. Появись кнопка у них, человек нажимал бы на мёртвое.
  ///
  /// Разговор объявляется классом `calling` на теле: на телефоне шапке нужно
  /// освободить место, и решает это CSS, а не скрипт.
  function voiceBridge() {
    const box = $('#voice');
    const bridge = window.flutter_inappwebview;
    if (!box || !bridge || typeof bridge.callHandler !== 'function') return;

    const call = $('#voiceCall');
    const hang = $('#voiceHang');
    const mic = $('#voiceMic');
    const state = $('#voiceState');
    const time = $('#voiceTime');

    const say = (action) => {
      try {
        bridge.callHandler('watchVoice', { action });
      } catch (_) {
        // Мост пропал вместе с экраном — показывать тут нечего.
      }
    };
    call.addEventListener('click', () => say('call'));
    hang.addEventListener('click', () => say('hangup'));
    mic.addEventListener('click', () => say('mic'));

    const mmss = (sec) => Math.floor(sec / 60) + ':' + String(sec % 60).padStart(2, '0');

    let timer = 0;
    let since = 0;
    const stopClock = () => { clearInterval(timer); timer = 0; };
    const startClock = () => {
      if (timer) return;
      since = Date.now();
      time.textContent = mmss(0);
      // Секунда считается от начала разговора, а не сложением тиков: вкладка в
      // фоне усыпляет интервалы, и счёт отстал бы от настоящего времени.
      timer = setInterval(() => {
        time.textContent = mmss(Math.floor((Date.now() - since) / 1000));
      }, 1000);
    };

    /** Состояние присылает приложение: off, connecting, live, failed. */
    const apply = (raw) => {
      const data = raw || {};
      // Приложение отозвалось — значит звонок отсюда оно понимает.
      box.hidden = false;
      const now = String(data.state || 'off');
      const live = now === 'live';
      const busy = live || now === 'connecting';

      call.hidden = busy;
      hang.hidden = !busy;
      mic.hidden = !live;
      mic.setAttribute('aria-pressed', data.micOn === false ? 'false' : 'true');
      document.body.classList.toggle('calling', busy);

      if (live) {
        startClock();
      } else {
        stopClock();
        if (now === 'connecting') time.textContent = I18N.t('room.voiceRinging');
        else if (now === 'failed') time.textContent = I18N.t('room.voiceFailed');
      }
      state.hidden = !(busy || now === 'failed');
    };

    window.watchVoiceState = apply;
    // Приложение могло ответить раньше, чем страница дошла до этой строки.
    if (window.__voicePending) apply(window.__voicePending);
  }

  /// Кадр во всю площадь, чат поверх.
  ///
  /// Полноэкранный режим самого плеера отдаёт экран площадке целиком, и чат туда
  /// не положить — «нету чата при просмотре на весь экран». Разворачиваем своими
  /// силами: тогда и видео крупное, и переписка на месте.
  function cinemaToggle() {
    const btn = $('#cinema');
    if (!btn) return;
    btn.addEventListener('click', () => {
      setCinema(!document.body.classList.contains('cinema'));
    });
    catchPlayerFullscreen();
  }

  /// Включает или снимает свой полноэкранный режим.
  function setCinema(on) {
    document.body.classList.toggle('cinema', on);
    const btn = $('#cinema');
    if (btn) btn.setAttribute('aria-pressed', on ? 'true' : 'false');
  }

  /// Кнопка «во весь экран» у самого плеера ведёт в наш режим, а не в системный.
  ///
  /// В приложении комната живёт во встроенном браузере, и когда ютуб уходит в
  /// системный полноэкранный режим, кадр накрывает всё окно: писать становится
  /// некуда, а кнопки выхода из WebView не видно — «не получается писать в
  /// приложении, когда смотрим видео» (24.08.2026). Поэтому на телефоне
  /// выходим из системного режима и включаем свой: кадр во всю площадь, чат
  /// поверх. На широком экране не мешаем — там полноэкранный режим и правда
  /// полноэкранный, а чат человек видит в соседней колонке.
  function catchPlayerFullscreen() {
    // Узкий экран — телефон: и в приложении, и в мобильном браузере.
    const narrow = () => Math.min(window.innerWidth, window.innerHeight) < 700;
    const swap = () => {
      const el = document.fullscreenElement || document.webkitFullscreenElement;
      if (!el || !narrow()) return;
      let exit;
      try {
        exit = document.exitFullscreen
          ? document.exitFullscreen()
          : document.webkitExitFullscreen && document.webkitExitFullscreen();
      } catch (_) {}
      // Свой режим включаем в любом случае: даже если системный не отпустил,
      // человек выйдет из него сам и попадёт в комнату с чатом.
      Promise.resolve(exit).catch(() => {}).then(() => setCinema(true));
    };
    document.addEventListener('fullscreenchange', swap);
    document.addEventListener('webkitfullscreenchange', swap);
  }

  /// Запуск идёт по готовности РАЗМЕТКИ.
  ///
  /// `load` ждёт каждый подресурс страницы, в том числе чужой скрипт: пока
  /// один такой запрос висит, обработчики кнопок не навешены, код комнаты не
  /// проставлен и канал не поднят — комната открыта и мертва. Разметке для
  /// работы хватает самой себя.
  function start() {
    I18N.mount();
    followKeyboard();
    cinemaToggle();
    voiceBridge();
    $('#chat').dataset.empty = I18N.t('room.chatEmpty');

    const room = roomFromHash();
    if (!room) {
      // Прямой заход без кода: комнаты нет, отправляем на главную.
      location.replace('../');
      return;
    }

    state.room = room;
    $('#code').textContent = room;
    if (navigator.share) $('#share').hidden = false;

    // Приложение открывает комнату сразу с роликом: /watch/room/?src=<адрес>#код.
    const params = new URLSearchParams(location.search);
    const wanted = params.get('src');
    if (wanted) {
      state.wanted = wanted;
      $('#link').value = wanted;
    }

    // Имя приходит от приложения (?name=). Без него обе стороны подписывались
    // «Гость», и человек не понимал, кто с ним в комнате. Гость из браузера
    // остаётся гостем: своего имени у него нет.
    state.name = (params.get('name') || '').trim().slice(0, 32);

    connect(room).catch(() => setStatus(I18N.t('room.lost')));

    $('#apply').addEventListener('click', () => {
      const el = $('#link');
      const link = el.value.trim() || state.lastLink || '';
      if (link && !el.value.trim()) el.value = link;
      applySource(link);
    });

    // Первое нажатие по строке освобождает её: прежний адрес уже применён —
    // ролик по нему играет, — и держать его в поле незачем. Вставка попадает в
    // пустую строку, ничего не дописывая в хвост.
    //
    // Раньше тут стояло выделение (`select()` плюс повтор следующим тактом,
    // потому что Safari снимал его сразу). На айфоне это мешало главному:
    // «Вставить» в контекстном меню появляется по долгому нажатию, а повторное
    // выделение закрывало меню. В пустом поле система предлагает вставку сама.
    //
    // Прежний адрес не теряется: пустая строка при нажатии «Включить»
    // означает «оставить как было».
    $('#link').addEventListener('focus', () => {
      const el = $('#link');
      if (!el.value) return;
      state.lastLink = el.value;
      el.value = '';
    });

    $('#together').addEventListener('click', () => {
      send('countdown', 0);
      showCountdown(3);
    });
    $('#pauseBoth').addEventListener('click', () => {
      send('pauseNow', 0);
      flashPause();
    });

    $('#pick').addEventListener('click', () => $('#file').click());
    $('#file').addEventListener('change', (e) => {
      const file = e.target.files && e.target.files[0];
      if (file) openLocalFile(file);
      e.target.value = '';
    });

    $('#send').addEventListener('click', () => {
      const text = $('#message').value.trim();
      if (!text) return;
      const myName = state.name || I18N.t('room.guest');
      addMessage(I18N.t('room.you'), text, true);
      remember(state.me, myName, text);
      send('chat', 0, { text, name: myName });
      $('#message').value = '';
    });
    $('#message').addEventListener('keydown', (e) => {
      if (e.key === 'Enter') $('#send').click();
    });

    const share = $('#share');
    if (share) {
      share.addEventListener('click', () => {
        navigator.share({ url: shareLink() }).catch(() => {});
      });
    }
    $('#copy').addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText(shareLink());
        setStatus(I18N.t('room.copied'));
      } catch (_) {
        setStatus(shareLink());
      }
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start);
  } else {
    start();
  }
})();
