/* Ленты вдвоём: короткие ролики по очереди из лент обоих.
 *
 * Живёт поверх комнаты пары (`?reels=1`): канал, чат и звонок берёт у room.js
 * через `window.__togetherlyRoom`, а сам ведёт ролики, очередь и реакции.
 *
 * Откуда ролики. Ленту платформы держит приложение — скрытым браузером, где
 * человек как будто листает Shorts сам. Оттуда приходят только номера роликов
 * (`reelsFeed` и `window.reelsFeedPush`), а смотрят оба здесь, официальным
 * плеером, поэтому у пары одна и та же картинка и ничего не накладывается.
 *
 * Очередь. Каждая страница объявляет партнёру первые номера своей ленты
 * (`reels-queue`). Свайп берёт следующий ролик из ленты ДРУГОГО — того, чей
 * ролик сейчас не играет, — и рассылает его (`reels-reel`). Так ход переходит
 * сам: ролик из ленты Ани, следующий из ленты Бори. Один в комнате — листает
 * свою ленту.
 *
 * Кнопки звонка и поле сообщения лента рисует свои, по макету, а нажатия
 * передаёт спрятанным кнопкам комнаты: у сайта у .btn и .input минимальная
 * высота 56, и перенесённые узлы вытягивались в овал. Переписку лента читает
 * из спрятанного #chat комнаты.
 */
(() => {
  'use strict';

  if (!/[?&]reels=1\b/.test(location.search)) return;
  const R = window.__togetherlyRoom;
  if (!R) return;

  const RU = (window.I18N && window.I18N.lang) !== 'en';
  // В плашке — чья лента сейчас играет. Имена не склоняем («лента Бори» из
  // имени не собрать), поэтому имя в именительном: «Лента · Боря».
  const T = RU ? {
    mine: 'Твоя лента', theirs: (n) => 'Лента · ' + n, partner: 'партнёр',
    refresh: 'Обновить рекомендации', refreshing: 'Подбираем свежие ролики…',
    call: 'Позвонить', react: 'Реакция', chat: 'Чат', share: 'Отправить ролик', prev: 'Прошлый ролик', back: 'Назад',
    mic: 'Микрофон', hang: 'Положить трубку', ringing: 'Звоним…', failed: 'Не вышло',
    write: () => 'Написать…', send: 'Отправить',
    loading: 'Собираем ленту…', loadingSub: 'Первые ролики приходят за несколько секунд',
    noFeed: 'Ленту даёт приложение', noFeedSub: 'Откройте «Ленты» в Togetherly на телефоне — ролики пойдут и сюда',
    match: 'Совпало!', matchSub: 'Вам обоим зашёл этот ролик', sound: 'Включить звук',
    copied: 'Ссылка скопирована', ourChat: 'Наш чат', empty: 'Здесь пока пусто', unavailable: 'Ролик недоступен, листаем дальше',
  } : {
    mine: 'Your feed', theirs: (n) => 'Feed · ' + n, partner: 'partner',
    refresh: 'Refresh recommendations', refreshing: 'Picking fresh clips…',
    call: 'Call', react: 'React', chat: 'Chat', share: 'Send clip', prev: 'Previous clip', back: 'Back',
    mic: 'Microphone', hang: 'Hang up', ringing: 'Calling…', failed: 'Failed',
    write: () => 'Message…', send: 'Send',
    loading: 'Gathering your feed…', loadingSub: 'The first clips arrive in a few seconds',
    noFeed: 'The feed comes from the app', noFeedSub: 'Open Feeds in Togetherly on your phone and the clips will show up here too',
    match: 'It’s a match!', matchSub: 'You both liked this one', sound: 'Turn sound on',
    copied: 'Link copied', ourChat: 'Our chat', empty: 'Nothing here yet', unavailable: 'Clip unavailable, moving on',
  };

  // Значки — из того же набора Material Symbols Rounded, что в приложении
  // (symbols.woff2 — нужные глифы, собраны из assets/fonts).
  const IC = {
    back: '', call: '', end: '', mic: '', micOff: '', chat: '',
    swipe: '', send: '', share: '', undo: '', play: '', close: '', sound: '',
  };
  IC.refresh = '';
  const ic = (c) => '<span class="ms" aria-hidden="true">' + c + '</span>';
  // На iPhone нет системного «назад»: без своей кнопки из лент не выйти.
  const IOS = /iPhone|iPad|iPod/.test(navigator.userAgent);

  // Реакции — наши рисунки (те же, что в чате приложения), а не системные
  // эмодзи. По каналу ездит эмодзи, рисунок подставляется при показе.
  const REACT = [['heart', '❤️'], ['laugh', '😂'], ['wow', '😮'], ['cry', '😢'], ['fire', '🔥'], ['thumbs_up', '👍']];
  const ART = { '❤️': 'heart', '❤': 'heart', '😂': 'laugh', '😮': 'wow', '😢': 'cry', '🥺': 'cry', '🔥': 'fire', '👍': 'thumbs_up' };
  const MOVING = {};   // id рисунка → анимированный файл из каталога
  const artOf = (e, still) => {
    const id = ART[e] || 'heart';
    return (!still && MOVING[id]) || ('reactions/' + id + '.webp');
  };
  const artImg = (e, still) => '<img class="rl-art" alt="" src="' + artOf(e, still) + '">';

  const bridge = () => {
    const b = window.flutter_inappwebview;
    return b && typeof b.callHandler === 'function' ? b : null;
  };

  // Площадка своей ленты выбрана в приложении (`?feed=`); партнёр может
  // смотреть другую — у каждого ролика своя метка в ключе.
  const SOURCES = { shorts: 'SHORTS', tiktok: 'TIKTOK', rutube: 'RUTUBE', vk: 'ВК КЛИПЫ', dzen: 'ДЗЕН' };
  const feedParam = (new URLSearchParams(location.search).get('feed') || 'shorts').toLowerCase();
  const S = {
    src: SOURCES[feedParam] ? feedParam : 'shorts',
    me: '', name: '', partnerId: '', partnerName: '',
    mine: [], theirs: [], seen: new Set(),
    cur: null, back: [],
    viewers: 1, reacts: {},
    started: false, paused: false,
    player: null, ready: false, wantMuted: false, pulling: false,
  };

  const $ = (s, root) => (root || document).querySelector(s);
  let el = {};

  function build() {
    document.body.classList.add('reels');
    const root = document.createElement('div');
    root.className = 'rl';
    root.innerHTML = `
      <div class="rl-stage">
        <div class="rl-cards"></div>
        <div class="rl-shade"></div>
        <div class="rl-tap"></div>
        <div class="rl-paused">${ic(IC.play)}</div>
        <div class="rl-wait"><span class="rl-spin"></span><b></b><span></span></div>
      </div>
      <div class="rl-sheet">
        <div class="rl-grab">
          <span class="rl-handle"></span>
          <div class="rl-head"><b>${T.ourChat}</b><button class="rl-x" aria-label="${T.back}">${ic(IC.close)}</button></div>
        </div>
        <div class="rl-list"></div>
      </div>
      <div class="rl-ui">
        <div class="rl-top">
          ${IOS ? `<button class="rl-ib rl-back" aria-label="${T.back}">${ic(IC.back)}</button>` : ''}
          <button class="rl-ib rl-refresh" aria-label="${T.refresh}">${ic(IC.refresh)}</button>
          <span class="rl-pill"><span class="rl-av"></span><b></b><span class="rl-src">SHORTS</span></span>
        </div>
        <div class="rl-voice" hidden>
          <button class="rl-ib accent rl-call" aria-label="${T.call}">${ic(IC.call)}</button>
          <span class="rl-av lg is-partner rl-vwho" hidden></span>
          <button class="rl-ib accent rl-mic" aria-label="${T.mic}" hidden>${ic(IC.mic)}</button>
          <button class="rl-ib end rl-hang" aria-label="${T.hang}" hidden>${ic(IC.end)}</button>
          <span class="rl-vtime" hidden></span>
        </div>
        <div class="rl-rail">
          <button class="rl-rx rl-react" aria-label="${T.react}">${artImg('❤️', true)}</button>
          <button class="rl-rx rl-chatbtn" aria-label="${T.chat}">${ic(IC.chat)}</button>
          <button class="rl-rx rl-share" aria-label="${T.share}">${ic(IC.share)}</button>
          <button class="rl-rx rl-prev" aria-label="${T.prev}" disabled>${ic(IC.undo)}</button>
        </div>
        <div class="rl-pick" hidden></div>
        <div class="rl-feed"></div>
        <button class="rl-sound" hidden>${ic(IC.sound)}${T.sound}</button>
        <form class="rl-compose" autocomplete="off">
          <input class="rl-input" enterkeyhint="send" maxlength="500">
          <button class="rl-send" type="submit" aria-label="${T.send}">${ic(IC.send)}</button>
        </form>
      </div>`;
    document.body.appendChild(root);

    el = {
      root,
      stage: $('.rl-stage', root), tap: $('.rl-tap', root), cards: $('.rl-cards', root),
      wait: $('.rl-wait', root), pill: $('.rl-pill', root), refresh: $('.rl-refresh', root),
      voice: $('.rl-voice', root), rail: $('.rl-rail', root), react: $('.rl-react', root),
      pick: $('.rl-pick', root), feed: $('.rl-feed', root), sound: $('.rl-sound', root),
      list: $('.rl-list', root), prev: $('.rl-prev', root), input: $('.rl-input', root),
    };

    REACT.forEach(([, e]) => {
      const b = document.createElement('button');
      b.dataset.e = e;
      b.innerHTML = artImg(e, true);
      b.addEventListener('click', (ev) => { ev.stopPropagation(); closePick(); react(e); });
      el.pick.appendChild(b);
    });

    if (IOS) $('.rl-back', root).addEventListener('click', leave);
    el.refresh.addEventListener('click', refreshFeed);
    el.react.addEventListener('click', (e) => { e.stopPropagation(); el.pick.hidden ? openPick() : closePick(); });
    $('.rl-chatbtn', root).addEventListener('click', () => setChat(!el.root.classList.contains('chat-open')));
    $('.rl-x', root).addEventListener('click', () => setChat(false));
    wireSheetDrag();
    $('.rl-share', root).addEventListener('click', share);
    el.prev.addEventListener('click', previous);
    el.sound.addEventListener('click', unmute);
    $('.rl-compose', root).addEventListener('submit', (e) => { e.preventDefault(); sendText(); });
    el.input.addEventListener('focus', closePick);
    document.addEventListener('click', (e) => {
      if (!el.pick.hidden && !el.pick.contains(e.target) && !el.react.contains(e.target)) closePick();
    });

    wireVoice();
    wireChat();
    wireGestures();
    loadArt();
    showWait(T.loading, T.loadingSub, true);
    paintTurn();
  }

  /** Анимированные рисунки реакций лежат в каталоге — тянем, когда есть сеть. */
  function loadArt() {
    fetch('/api/collections/catalog_items/records?perPage=50&fields=id,data&filter=' + encodeURIComponent('kind="reaction"'))
      .then((r) => r.json())
      .then((d) => (d.items || []).forEach((it) => {
        const k = it.data && it.data.key;
        if (k && it.data.sm) MOVING[k] = it.data.sm;
      }))
      .catch(() => {});
  }

  // ── звонок: свои кнопки, связь в приложении ──────────────────────────────

  function wireVoice() {
    const v = document.getElementById('voice');
    if (!v) return;
    const press = (id) => { const b = document.getElementById(id); if (b) b.click(); };
    $('.rl-call', el.voice).addEventListener('click', () => press('voiceCall'));
    $('.rl-mic', el.voice).addEventListener('click', () => press('voiceMic'));
    $('.rl-hang', el.voice).addEventListener('click', () => press('voiceHang'));
    const paint = () => {
      // Комната открывает кнопку, только когда приложение ответило мостом.
      el.voice.hidden = v.hidden;
      const busy = !document.getElementById('voiceHang').hidden;
      const live = !document.getElementById('voiceMic').hidden;
      const micOn = document.getElementById('voiceMic').getAttribute('aria-pressed') !== 'false';
      $('.rl-call', el.voice).hidden = busy;
      // В покое — одна круглая кнопка, без подложки и подписи: колонке звонка
      // подложка нужна, только когда в ней трубка, микрофон и время.
      el.voice.classList.toggle('is-idle', !busy);
      const who = $('.rl-vwho', el.voice);
      who.hidden = !live;
      who.textContent = initial(S.partnerName);
      who.classList.toggle('talking', live);
      const mic = $('.rl-mic', el.voice);
      mic.hidden = !live;
      mic.className = 'rl-ib rl-mic ' + (micOn ? 'accent' : 'mute');
      mic.innerHTML = ic(micOn ? IC.mic : IC.micOff);
      $('.rl-hang', el.voice).hidden = !busy;
      const time = $('.rl-vtime', el.voice);
      const t = document.getElementById('voiceTime');
      // Пока ждём ответа — «Звоним…», в разговоре — время разговора.
      time.hidden = !busy;
      time.textContent = t ? t.textContent : '';
    };
    new MutationObserver(paint).observe(v, { subtree: true, attributes: true, childList: true, characterData: true });
    paint();
  }

  // ── переписка: читаем спрятанный чат комнаты ─────────────────────────────

  function readMsg(node) {
    const whoEl = node.querySelector('.msg__who');
    const who = whoEl ? whoEl.textContent : '';
    let text = '';
    node.childNodes.forEach((c) => { if (c !== whoEl) text += c.textContent; });
    return {
      who, text,
      mine: node.classList.contains('msg--mine'),
      sys: node.classList.contains('msg--system'),
    };
  }

  function bubble(m, inList) {
    const b = document.createElement('div');
    b.className = 'rl-msg' + (m.mine ? ' me' : '') + (m.sys ? ' sys' : '');
    if (!inList && !m.mine && !m.sys && m.who) {
      const name = document.createElement('b');
      name.textContent = m.who + ': ';
      b.appendChild(name);
    }
    b.appendChild(document.createTextNode(m.text));
    if (inList && !m.sys) {
      const small = document.createElement('small');
      const hm = new Date().toTimeString().slice(0, 5);
      small.textContent = m.mine ? hm : (m.who ? m.who + ' · ' : '') + hm;
      b.appendChild(small);
    }
    return b;
  }

  let fadeTimer = 0;
  function wireChat() {
    const chat = document.getElementById('chat');
    if (!chat) return;
    const empty = () => {
      if (el.list.children.length) return;
      const e = document.createElement('span');
      e.className = 'rl-empty';
      e.textContent = T.empty;
      el.list.appendChild(e);
    };
    empty();
    new MutationObserver((recs) => {
      recs.forEach((r) => r.addedNodes.forEach((n) => {
        if (!(n instanceof HTMLElement) || !n.classList.contains('msg')) return;
        const m = readMsg(n);
        if (!m.sys && !m.mine && m.who) S.partnerName = S.partnerName || m.who;
        const e = $('.rl-empty', el.list);
        if (e) e.remove();
        el.list.appendChild(bubble(m, true));
        el.list.scrollTop = el.list.scrollHeight;
        // Над полем — две последние, старшая бледнее, через 7 секунд гаснут.
        el.feed.appendChild(bubble(m, false));
        while (el.feed.children.length > 2) el.feed.firstChild.remove();
        Array.from(el.feed.children).forEach((c, i, all) => c.classList.toggle('old', i < all.length - 1));
        el.feed.style.opacity = '1';
        clearTimeout(fadeTimer);
        fadeTimer = setTimeout(() => { el.feed.style.opacity = '0'; }, 7000);
      }));
    }).observe(chat, { childList: true });
  }

  function sendText() {
    const text = el.input.value.trim();
    if (!text) return;
    const box = document.getElementById('message');
    const btn = document.getElementById('send');
    if (!box || !btn) return;
    box.value = text;
    btn.click();
    el.input.value = '';
  }

  // ── жесты по ролику: свайп, касание, двойное касание ─────────────────────

  let wheelLock = false;
  function wireGestures() {
    let y0 = 0, t0 = 0, moved = false, down = false, lastTap = 0, single = 0;
    el.tap.addEventListener('pointerdown', (e) => {
      y0 = e.clientY; t0 = Date.now(); moved = false; down = true;
      try { el.tap.setPointerCapture(e.pointerId); } catch (_) {}
    });
    el.tap.addEventListener('pointermove', (e) => {
      if (!down) return;
      const dy = e.clientY - y0;
      if (!moved && Math.abs(dy) > 12) { moved = true; closePick(); }
      // Ролик едет за пальцем, следующий выезжает снизу — как в лентах.
      if (moved && !el.root.classList.contains('chat-open')) dragCards(dy);
    });
    const finish = (e) => {
      if (!down) return;
      down = false;
      const dy = e.clientY - y0;
      const h = el.stage.clientHeight || 1;
      const fast = Date.now() - t0 < 350 && Math.abs(dy) > 40;
      if (moved && (Math.abs(dy) > h * 0.18 || fast)) {
        if (el.root.classList.contains('chat-open')) { if (dy > 0) setChat(false); return; }
        if (!(dy < 0 ? next() : previous())) settleCards();
        return;
      }
      if (moved) { settleCards(); return; }
      onTap(e);
    };
    el.tap.addEventListener('pointerup', finish);
    el.tap.addEventListener('pointercancel', (e) => { if (down) { down = false; settleCards(); } });
    const onTap = (e) => {
      if (!el.pick.hidden) { closePick(); return; }
      if (document.activeElement === el.input) { el.input.blur(); return; }
      const now = Date.now();
      if (now - lastTap < 300) {
        // Двойное касание — сердце, как в лентах платформ.
        clearTimeout(single);
        lastTap = 0;
        burstAt(e.clientX, e.clientY, '❤️');
        if (!S.cur || (S.reacts[S.cur.id] || {}).me !== '❤️') react('❤️');
        return;
      }
      lastTap = now;
      single = setTimeout(() => togglePause(true), 300);
    };
    el.tap.addEventListener('wheel', (e) => {
      if (Math.abs(e.deltaY) < 30 || wheelLock) return;
      wheelLock = true; setTimeout(() => { wheelLock = false; }, 700);
      if (e.deltaY > 0) next(); else previous();
    }, { passive: true });
    document.addEventListener('keydown', (e) => {
      if (e.target && /INPUT|TEXTAREA/.test(e.target.tagName)) return;
      if (e.key === 'ArrowDown') next();
      if (e.key === 'ArrowUp') previous();
      if (e.key === ' ') { e.preventDefault(); togglePause(true); }
    });
  }

  function burstAt(x, y, e) {
    const h = document.createElement('img');
    h.className = 'rl-burst';
    h.alt = '';
    h.src = artOf(e);
    const box = el.root.getBoundingClientRect();
    h.style.left = (x - box.left) + 'px';
    h.style.top = (y - box.top) + 'px';
    el.root.appendChild(h);
    setTimeout(() => h.remove(), 1000);
  }

  // ── очередь ──────────────────────────────────────────────────────────────

  function addMine(ids) {
    let added = 0;
    (ids || []).forEach((raw) => {
      if (typeof raw !== 'string') return;
      // Приложение отдаёт голые номера своей площадки — ключ собираем здесь.
      const id = raw.indexOf(':') > 0 ? raw : S.src + ':' + raw;
      if (!/^[a-z]+:-?[A-Za-z0-9_-]{6,80}$/.test(id)) return;
      if (S.seen.has(id) || S.mine.indexOf(id) >= 0) return;
      S.mine.push(id);
      added++;
    });
    if (!added) return;
    announce();
    if (S.started && !S.cur) next();
    else preloadSoon();
  }

  let announceTimer = 0;
  function announce() {
    clearTimeout(announceTimer);
    announceTimer = setTimeout(() => {
      if (!R.subscribed()) return;
      R.send('reels-queue', { ids: S.mine.slice(0, 4), name: S.name });
    }, 150);
  }

  async function pull(n) {
    const b = bridge();
    if (!b || S.pulling) return;
    S.pulling = true;
    try {
      const ids = await b.callHandler('reelsFeed', { need: n || 8 });
      if (Array.isArray(ids)) addMine(ids);
    } catch (_) {
      // Старое приложение без ленты — останутся ролики партнёра.
    } finally {
      S.pulling = false;
    }
  }

  /** Следующий ролик: из ленты того, чей ролик сейчас НЕ играет. */
  function next() {
    closePick();
    const together = S.viewers > 1 && S.partnerId;
    let id = '', owner = '';
    const fromTheirs = () => {
      while (S.theirs.length && !id) {
        const c = S.theirs.shift();
        if (!S.seen.has(c)) { id = c; owner = S.partnerId; }
      }
    };
    const fromMine = () => {
      while (S.mine.length && !id) {
        const c = S.mine.shift();
        if (!S.seen.has(c)) { id = c; owner = S.me; }
      }
    };
    if (together && (!S.cur || S.cur.owner === S.me)) { fromTheirs(); fromMine(); } else { fromMine(); if (together) fromTheirs(); }
    if (S.mine.length < 4) pull(8);
    if (!id) {
      if (!S.cur) showWait(bridge() ? T.loading : T.noFeed, bridge() ? T.loadingSub : T.noFeedSub, !!bridge());
      return false;
    }
    if (owner === S.me) announce();
    if (S.cur) { S.back.push(S.cur); if (S.back.length > 30) S.back.shift(); }
    const cur = { id, owner, by: S.me };
    show(cur);
    R.send('reels-reel', { id, owner, by: S.me, name: S.name });
    return true;
  }

  /** Какой ролик покажет следующий свайп — по тем же правилам, что [next],
   *  только ничего не забирая из очередей. Его плеер грузится заранее. */
  function peekNext() {
    const together = S.viewers > 1 && S.partnerId;
    const first = (arr) => arr.find((x) => !S.seen.has(x)) || '';
    if (together && (!S.cur || S.cur.owner === S.me)) return first(S.theirs) || first(S.mine);
    return first(S.mine) || (together ? first(S.theirs) : '');
  }

  function previous() {
    const prev = S.back.pop();
    if (!prev) return false;
    const cur = { id: prev.id, owner: prev.owner, by: S.me };
    show(cur, true);
    R.send('reels-reel', { id: cur.id, owner: cur.owner, by: S.me, name: S.name, back: true });
    return true;
  }

  function show(cur, isBack) {
    S.cur = cur;
    S.seen.add(cur.id);
    const i = S.mine.indexOf(cur.id);
    if (i >= 0) { S.mine.splice(i, 1); announce(); }
    S.theirs = S.theirs.filter((x) => x !== cur.id);
    S.paused = false;
    el.root.classList.remove('is-paused');
    el.prev.disabled = !S.back.length;
    hideWait();
    paintTurn();
    paintReact();
    swapTo(cur.id, !!isBack);
    // Ролик из своей ленты: скрытая страница приложения «смотрит» его тоже,
    // без звука. Так платформа засчитывает просмотр, а рекомендации учатся.
    const b = bridge();
    if (b && cur.owner === S.me && keySrc(cur.id) === S.src) { try { b.callHandler('reelsWatching', { id: keyId(cur.id) }); } catch (_) {} }
  }

  // ── плеер ────────────────────────────────────────────────────────────────

  let ytAsked = false;
  const ytWait = [];
  function whenYT(done) {
    if (window.YT && window.YT.Player) { done(); return; }
    ytWait.push(done);
    if (ytAsked) return;
    ytAsked = true;
    const prev = window.onYouTubeIframeAPIReady;
    window.onYouTubeIframeAPIReady = () => {
      if (typeof prev === 'function') { try { prev(); } catch (_) {} }
      while (ytWait.length) ytWait.shift()();
    };
    const tag = document.createElement('script');
    tag.src = 'https://www.youtube.com/iframe_api';
    tag.async = true;
    document.head.appendChild(tag);
  }

  // Каждый ролик — своя карточка со своим плеером. Следующий грузится заранее
  // под экраном и тихо играет: свайп просто сдвигает карточки, а кнопки,
  // которые YouTube показывает первые секунды после старта, успевают
  // спрятаться до показа. Раньше один плеер перезаряжался `loadVideoById` и
  // сам перезапускал повтор — и кнопка паузы всплывала в центре без конца.
  // Прошлый ролик тоже живёт — над экраном: свайп вниз тянет его за пальцем,
  // как свайп вверх тянет следующий.
  const cards = { cur: null, next: null, prev: null };
  let cardSeq = 0;

  // Ключ ролика — «площадка:номер» («tiktok:7654…», «vk:-2326_4562_c1df»):
  // у партнёра может быть своя площадка, и по ключу видно, чем играть.
  // Ключ без площадки — Shorts: так шлют сборки, вышедшие до остальных лент.
  const keySrc = (key) => (key.indexOf(':') > 0 ? key.slice(0, key.indexOf(':')) : 'shorts');
  const keyId = (key) => (key.indexOf(':') > 0 ? key.slice(key.indexOf(':') + 1) : key);

  /** Плееры площадок, кроме YouTube: официальный iframe и его команды.
   *  `keep: false` — команд у плеера нет (Дзен), поэтому заранее под экраном
   *  его не держим: молчать по просьбе он не умеет. */
  const FRAMES = {
    tiktok: {
      url: (id) => 'https://www.tiktok.com/player/v1/' + id + '?autoplay=1&loop=1&controls=0&progress_bar=0&play_button=0&volume_control=0&fullscreen_button=0&timestamp=0&music_info=0&description=0&rel=0&native_context_menu=0&closed_caption=0',
      say: (w, cmd) => w.postMessage({ type: { play: 'play', pause: 'pause', mute: 'mute', unmute: 'unMute' }[cmd], 'x-tiktok-player': true }, '*'),
      playing: (m) => m && m.type === 'onStateChange' && m.value === 1,
      keep: true,
    },
    rutube: {
      url: (id) => 'https://rutube.ru/play/embed/' + id + '/?autoplay=1',
      say: (w, cmd) => w.postMessage(JSON.stringify({ type: 'player:' + { play: 'play', pause: 'pause', mute: 'mute', unmute: 'unMute' }[cmd], data: {} }), '*'),
      // Rutube в конце ролика встаёт: повтор просим сами.
      ended: (m) => m && m.type === 'player:changeState' && m.data && (m.data.state === 'completed' || m.data.state === 'stopped'),
      playing: (m) => m && m.type === 'player:changeState' && m.data && m.data.state === 'playing',
      keep: true,
    },
    vk: {
      url: (id) => { const p = id.split('_'); return 'https://vk.com/video_ext.php?oid=' + p[0] + '&id=' + p[1] + '&hash=' + p[2] + '&autoplay=1&loop=1&js_api=1'; },
      init: (w) => w.postMessage({ method: 'init' }, '*'),
      say: (w, cmd) => w.postMessage({ method: cmd }, '*'),
      ended: (m) => m && m.event === 'ended',
      playing: (m) => m && (m.event === 'started' || m.event === 'resumed'),
      keep: true,
    },
    dzen: {
      url: (id) => 'https://dzen.ru/embed/' + id + '?autoplay=1&mute=0&loop=1',
      keep: false,
    },
  };
  const canKeep = (key) => keySrc(key) === 'shorts' || !!(FRAMES[keySrc(key)] || {}).keep;
  // Прошлый ролик живым держим только у YouTube: без этого он показал бы свои
  // кнопки. Плееры остальных площадок крутят свой код и на паузе, а у WebView
  // он идёт в одном потоке со страницей — лишний плеер добавлял рывков
  // (замер room-reels-perf: 8% тяжёлых кадров анимации против 4%).
  const canKeepPrev = (key) => keySrc(key) === 'shorts';

  /** [lazy] — плеер поднимет `card.boot()` позже (после анимации свайпа). */
  function makeCard(key, lazy) {
    const node = document.createElement('div');
    node.className = 'rl-card';
    const frame = document.createElement('div');
    frame.className = 'rl-frame';
    const holder = document.createElement('div');
    holder.id = 'rlCard' + (++cardSeq);
    frame.appendChild(holder);
    node.appendChild(frame);
    el.cards.appendChild(node);
    const card = { id: key, el: node, api: null, ready: false, active: false, dead: false };
    const src = keySrc(key);
    card.boot = () => {
      card.boot = null;
      if (src === 'shorts') ytCard(card, holder, keyId(key));
      else frameCard(card, holder, src, keyId(key));
    };
    if (!lazy) card.boot();
    return card;
  }

  /** Ролик не открылся: соседний — просто убрать, текущий — листать дальше.
   *  Листает тот, кто его включил, чтобы двое не перескочили дважды. */
  function failed(card) {
    if (card === cards.next) {
      // Закрытый для встраивания ролик вычёркиваем и грузим следующий.
      drop(card); cards.next = null;
      S.seen.add(card.id);
      S.mine = S.mine.filter((x) => x !== card.id);
      S.theirs = S.theirs.filter((x) => x !== card.id);
      preloadSoon();
      return;
    }
    if (card === cards.prev) { drop(card); cards.prev = null; return; }
    if (card !== cards.cur || !S.cur || S.cur.by !== S.me) return;
    R.say(T.unavailable);
    setTimeout(next, 600);
  }

  function ytCard(card, holder, id) {
    whenYT(() => {
      if (card.dead) return;
      const p = new YT.Player(holder.id, {
        videoId: id,
        // Повтор делает сам плеер (`loop` с `playlist` из одного ролика):
        // наш перезапуск через seekTo снова вызывал его кнопки.
        playerVars: { autoplay: 1, mute: 1, controls: 0, playsinline: 1, rel: 0, modestbranding: 1, fs: 0, iv_load_policy: 3, disablekb: 1, loop: 1, playlist: id },
        events: {
          onReady: () => {
            card.ready = true;
            if (card.active) wake(card);
            // Под экраном ролик играет без звука в четверть скорости: кнопки
            // YouTube за это время прячутся, а ролик почти не уходит вперёд.
            // Останавливать его нельзя — пауза снова вызывает кнопки.
            else card.api.shelve();
          },
          onError: () => failed(card),
        },
      });
      card.api = {
        play: () => p.playVideo(),
        pause: () => p.pauseVideo(),
        mute: () => p.mute(),
        unmute: () => { p.unMute(); p.setVolume(100); },
        muted: () => p.isMuted(),
        // Без паузы и без перемотки: и то и другое вызывает кнопки YouTube.
        shelve: () => { p.mute(); p.setPlaybackRate(0.25); p.playVideo(); },
        wake: () => p.setPlaybackRate(1),
        destroy: () => p.destroy(),
      };
    });
  }

  function frameCard(card, holder, src, id) {
    const spec = FRAMES[src];
    if (!spec) { setTimeout(() => failed(card), 0); return; }
    const f = document.createElement('iframe');
    f.src = spec.url(id);
    f.allow = 'autoplay; encrypted-media; picture-in-picture';
    // Страница комнаты без реферера (ради дисков), а площадкам он нужен.
    f.referrerPolicy = 'strict-origin-when-cross-origin';
    holder.appendChild(f);
    card.frame = f;
    card.spec = spec;
    const say = (cmd) => { try { if (spec.say) spec.say(f.contentWindow, cmd); } catch (_) {} };
    card.api = {
      play: () => say('play'),
      pause: () => say('pause'),
      mute: () => say('mute'),
      unmute: () => say('unmute'),
      muted: () => false,
      shelve: () => { card.playing = false; say('mute'); say('pause'); },
      // После сворачивания система ставит видео на паузу. Плеер с командами
      // будим «играть», а Дзен их не понимает — его перезагружаем, и он
      // стартует сам (эмулятор, 04.10.2026: после возврата был чёрный экран).
      revive: () => {
        if (spec.say) { say('play'); if (card.nudge) card.nudge(); return; }
        const u = f.src;
        f.src = 'about:blank';
        setTimeout(() => { f.src = u; }, 50);
      },
      wake: () => {},
      destroy: () => f.remove(),
    };
    f.addEventListener('load', () => {
      card.ready = true;
      try { if (spec.init) spec.init(f.contentWindow); } catch (_) {}
      // Плееры поднимаются не сразу и первые команды теряют — повторяем.
      [0, 700, 1800, 3500].forEach((ms) => setTimeout(() => {
        if (card.dead) return;
        if (card.active) wake(card); else card.api.shelve();
      }, ms));
    });
    // Плеер ВК на телефоне принимает «играть» не с первого раза и стоит с
    // кнопкой на кадре (эмулятор, 04.10.2026). Пока он сам не скажет, что
    // пошёл, текущий ролик будим раз в полторы секунды, до 15 секунд.
    let tries = 0;
    card.nudge = () => {
      clearInterval(card.nudgeTimer);
      tries = 0;
      card.nudgeTimer = setInterval(() => {
        if (card.dead || !card.active || card.playing || ++tries > 10) { clearInterval(card.nudgeTimer); return; }
        try { if (spec.init) spec.init(f.contentWindow); } catch (_) {}
        if (!S.paused) { if (!S.wantMuted) card.api.unmute(); card.api.play(); }
      }, 1500);
    };
  }

  // Ответы плееров площадок: пошёл — больше не будим, конец ролика — повтор.
  window.addEventListener('message', (e) => {
    const all = [cards.cur, cards.next, cards.prev];
    const card = all.find((c) => c && c.frame && c.frame.contentWindow === e.source);
    if (!card || !card.spec) return;
    let m = e.data;
    if (typeof m === 'string') { try { m = JSON.parse(m); } catch (_) { return; } }
    if (card.spec.playing && card.spec.playing(m)) card.playing = true;
    if (card.active && card.spec.ended && card.spec.ended(m)) card.api.play();
  });

  function drop(card) {
    if (!card) return;
    card.dead = true;
    try { if (card.api) card.api.destroy(); } catch (_) {}
    card.el.remove();
  }

  /** Карточка стала текущей: обычная скорость и звук. Без перемотки в начало:
   *  `seekTo` вызывает у YouTube полный набор кнопок поверх ролика (проверено
   *  перебором в scratchpad/ytui), а смена скорости и звука — нет. */
  function wake(card) {
    if (!card.ready || !card.api) return;
    try {
      card.api.wake();
      if (S.wantMuted) card.api.mute(); else card.api.unmute();
      card.api.play();
    } catch (_) {}
    checkSound(card);
  }

  const place = (card, y, animate) => {
    if (!card) return;
    card.el.style.transition = animate ? 'transform .3s cubic-bezier(.2, 0, 0, 1)' : 'none';
    card.el.style.transform = 'translate3d(0,' + y + ',0)';
  };

  /** Палец тянет: текущая едет за ним, соседняя выезжает с той стороны. */
  function dragCards(dy) {
    const h = el.stage.clientHeight;
    // Назад без прошлого ролика тянется туже — это лишь отклик на жест.
    const y = dy < 0 || cards.prev ? dy : dy * 0.45;
    place(cards.cur, y + 'px', false);
    if (cards.next) place(cards.next, (h + Math.min(0, dy)) + 'px', false);
    if (cards.prev) place(cards.prev, (-h + Math.max(0, dy)) + 'px', false);
  }

  /** Свайп не дотянул — всё на место. */
  function settleCards() {
    place(cards.cur, '0', true);
    if (cards.next) place(cards.next, '100%', true);
    if (cards.prev) place(cards.prev, '-100%', true);
  }

  /** Карточка ушла с экрана: молчит (YouTube — в четверть скорости, без
   *  паузы; остальные — на паузе). */
  function shelve(card) {
    card.active = false;
    card.el.classList.remove('is-cur');
    try { if (card.api) card.api.shelve(); } catch (_) {}
  }

  function swapTo(id, isBack) {
    flushSettle();
    let card = null;
    if (cards.prev && cards.prev.id === id) { card = cards.prev; cards.prev = null; }
    else if (cards.next && cards.next.id === id) { card = cards.next; cards.next = null; }
    // Новый плеер (не загруженный заранее) поднимаем после того, как карточки
    // доедут: плееры площадок работают в одном потоке со страницей (у WebView
    // нет отдельных процессов для iframe), и их запуск посреди анимации рвал
    // свайп — замер room-reels-perf, 04.10.2026.
    else { card = makeCard(id, true); place(card, isBack ? '-100%' : '100%', false); }
    const old = cards.cur;
    cards.cur = card;
    card.active = true;
    card.el.classList.add('is-cur');
    requestAnimationFrame(() => place(card, '0', true));
    if (old) {
      old.active = false;
      old.el.classList.remove('is-cur');
      place(old, isBack ? '100%' : '-100%', true);
    }
    // Команды плеерам — тоже после анимации: «играть», «пауза» и звук
    // запускают декодирование, и посреди сдвига это давало рывки.
    pendingSettle = () => {
      if (old && !old.dead) {
        shelve(old);
        if (isBack || !canKeepPrev(old.id)) drop(old);
        else {
          // Ушедший вверх ролик и есть прошлый: свайп вниз вернёт его сразу.
          if (cards.prev && cards.prev !== old) drop(cards.prev);
          cards.prev = old;
        }
      }
      if (card.dead || cards.cur !== card) return;
      if (card.boot) card.boot();
      wake(card);
      if (card.nudge) card.nudge();
      idle(() => { preloadNext(); ensurePrev(); });
    };
    settleTimer = setTimeout(flushSettle, SLIDE_MS);
  }
  const SLIDE_MS = 320;
  let settleTimer = 0;
  let pendingSettle = null;
  /** Доделать прошлую смену сразу — новый свайп пришёл раньше, чем она доехала. */
  function flushSettle() {
    clearTimeout(settleTimer);
    const f = pendingSettle;
    pendingSettle = null;
    if (f) f();
  }
  /** Свободное время потока — для заранее загружаемых плееров. */
  const idle = (fn) => (window.requestIdleCallback ? requestIdleCallback(fn, { timeout: 1500 }) : setTimeout(fn, 600));

  /** Над экраном лежит ролик, на который ведёт «назад». */
  function ensurePrev() {
    const want = S.back.length ? S.back[S.back.length - 1].id : '';
    if (cards.prev && cards.prev.id === want) return;
    if (cards.prev) { drop(cards.prev); cards.prev = null; }
    if (!want || !canKeepPrev(want)) return;
    cards.prev = makeCard(want);
    place(cards.prev, '-100%', false);
  }

  /** «Обновить рекомендации»: свой запас в сторону, скрытая лента начинает
   *  заново, и первый свежий ролик включается сам. */
  let refreshing = false;
  async function refreshFeed() {
    const b = bridge();
    if (!b || refreshing) return;
    refreshing = true;
    el.refresh.classList.add('is-busy');
    S.mine = [];
    if (cards.next) { drop(cards.next); cards.next = null; }
    // Сборка без этого обработчика может не ответить вовсе — ждём недолго.
    const wait = (ms) => new Promise((r) => setTimeout(r, ms));
    try { await Promise.race([b.callHandler('reelsRefresh', {}), wait(3000)]); } catch (_) {}
    // Запрос ленты мог уже идти (тогда pull сразу выходит) — ждём, пока
    // придёт хоть один свежий ролик, до 14 секунд.
    pull(10);
    for (let t = 0; t < 14000 && !S.mine.some((x) => !S.seen.has(x)); t += 300) await wait(300);
    refreshing = false;
    el.refresh.classList.remove('is-busy');
    const id = S.mine.find((x) => !S.seen.has(x));
    if (!id) return;
    S.mine = S.mine.filter((x) => x !== id);
    announce();
    if (S.cur) { S.back.push(S.cur); if (S.back.length > 30) S.back.shift(); }
    show({ id, owner: S.me, by: S.me });
    R.send('reels-reel', { id, owner: S.me, by: S.me, name: S.name });
  }

  /** Следующий ролик заранее, под экраном. */
  function preloadNext() {
    if (!S.cur) return;
    const id = peekNext();
    if (cards.next && cards.next.id === id) return;
    if (cards.next) { drop(cards.next); cards.next = null; }
    if (!id || !canKeep(id)) return;
    cards.next = makeCard(id);
    place(cards.next, '100%', false);
  }
  let preloadTimer = 0;
  const preloadSoon = () => { clearTimeout(preloadTimer); preloadTimer = setTimeout(preloadNext, 300); };

  /** Браузер без касания не даст звук: тогда играем без него и предлагаем включить. */
  let soundCheck = 0;
  function checkSound(card) {
    clearTimeout(soundCheck);
    soundCheck = setTimeout(() => {
      if (card !== cards.cur || !card.api || S.paused) return;
      let muted = false;
      try { muted = card.api.muted(); } catch (_) {}
      if (muted && !S.wantMuted) {
        S.wantMuted = true;
        el.sound.hidden = false;
      }
    }, 1200);
  }

  function unmute() {
    S.wantMuted = false;
    el.sound.hidden = true;
    const c = cards.cur;
    try { c.api.unmute(); c.api.play(); } catch (_) {}
  }

  function togglePause(tell) {
    if (!cards.cur || !S.cur) return;
    if (!el.sound.hidden) { unmute(); return; }
    setPaused(!S.paused);
    if (tell) R.send('reels-pause', { id: S.cur.id, paused: S.paused });
  }

  function setPaused(p) {
    S.paused = p;
    el.root.classList.toggle('is-paused', p);
    const c = cards.cur;
    try { if (p) c.api.pause(); else c.api.play(); } catch (_) {}
  }

  // ── ход, реакции ─────────────────────────────────────────────────────────

  const initial = (name) => (String(name || '').trim()[0] || '·').toUpperCase();

  function paintTurn() {
    const pName = S.partnerName || T.partner;
    const mine = !S.cur || S.cur.owner === S.me;
    const av = $('.rl-av', el.pill);
    av.textContent = initial(mine ? S.name : S.partnerName);
    av.classList.toggle('is-partner', !mine);
    $('b', el.pill).textContent = mine ? T.mine : T.theirs(pName);
    $('.rl-src', el.pill).textContent = SOURCES[S.cur ? keySrc(S.cur.id) : S.src] || 'SHORTS';
    el.input.placeholder = T.write();
  }

  function openPick() {
    const r = el.react.getBoundingClientRect();
    const box = el.root.getBoundingClientRect();
    el.pick.style.top = (r.top - box.top + r.height / 2 - 26) + 'px';
    const mine = S.cur ? (S.reacts[S.cur.id] || {}).me : '';
    Array.from(el.pick.children).forEach((b) => b.classList.toggle('is-on', b.dataset.e === mine));
    el.pick.hidden = false;
  }
  function closePick() { if (el.pick) el.pick.hidden = true; }

  function react(e) {
    if (!S.cur) return;
    const r = S.reacts[S.cur.id] || (S.reacts[S.cur.id] = {});
    r.me = r.me === e ? '' : e;
    paintReact();
    R.send('reels-react', { id: S.cur.id, e: r.me });
    if (r.me && r.me === r.them) matched(r.me);
  }

  function paintReact() {
    const r = (S.cur && S.reacts[S.cur.id]) || {};
    $('img', el.react).src = artOf(r.me || '❤️', !r.me);
    el.react.classList.toggle('is-on', !!r.me);
  }

  function theirReaction(data) {
    const r = S.reacts[data.id] || (S.reacts[data.id] = {});
    r.them = data.e || '';
    if (!S.cur || data.id !== S.cur.id || !r.them) return;
    const pop = document.createElement('div');
    pop.className = 'rl-pop';
    pop.innerHTML = '<span class="rl-av is-partner"></span>' + artImg(r.them);
    pop.firstChild.textContent = initial(S.partnerName);
    const rr = el.react.getBoundingClientRect();
    const box = el.root.getBoundingClientRect();
    pop.style.top = (rr.top - box.top + 2) + 'px';
    el.root.appendChild(pop);
    setTimeout(() => pop.remove(), 2700);
    if (r.me && r.me === r.them) matched(r.me);
  }

  function matched(e) {
    const old = $('.rl-match', el.root);
    if (old) old.remove();
    const m = document.createElement('div');
    m.className = 'rl-match';
    m.innerHTML = artImg(e) + '<span><b></b><small></small></span>';
    m.querySelector('b').textContent = T.match;
    m.querySelector('small').textContent = T.matchSub;
    el.root.appendChild(m);
    setTimeout(() => m.remove(), 3500);
  }

  function setChat(on) {
    closePick();
    el.root.classList.toggle('chat-open', on);
    $('.rl-chatbtn', el.root).classList.toggle('is-on', on);
    const sheet = $('.rl-sheet', el.root);
    sheet.style.transition = '';
    sheet.style.transform = '';
    if (on) setTimeout(() => { el.list.scrollTop = el.list.scrollHeight; }, 50);
  }

  /** Лист чата закрывается свайпом вниз — за шапку листа или по переписке,
   *  когда она уже прокручена до верха. */
  function wireSheetDrag() {
    const sheet = $('.rl-sheet', el.root);
    let y0 = 0, dy = 0, on = false;
    sheet.addEventListener('pointerdown', (e) => {
      if (e.target.closest('.rl-x')) return;
      const fromHead = !!e.target.closest('.rl-grab');
      if (!fromHead && el.list.scrollTop > 0) return;
      y0 = e.clientY; dy = 0; on = true;
    });
    sheet.addEventListener('pointermove', (e) => {
      if (!on) return;
      dy = Math.max(0, e.clientY - y0);
      if (dy < 8) return;
      sheet.style.transition = 'none';
      sheet.style.transform = 'translateY(' + dy + 'px)';
    });
    const end = () => {
      if (!on) return;
      on = false;
      if (dy > Math.min(120, sheet.clientHeight * 0.25)) { setChat(false); return; }
      sheet.style.transition = '';
      sheet.style.transform = '';
    };
    sheet.addEventListener('pointerup', end);
    sheet.addEventListener('pointercancel', end);
  }

  async function share() {
    if (!S.cur) return;
    const url = 'https://youtube.com/shorts/' + S.cur.id;
    const b = bridge();
    if (b) { try { await b.callHandler('reelsShare', { url }); return; } catch (_) {} }
    if (navigator.share) { navigator.share({ url }).catch(() => {}); return; }
    try { await navigator.clipboard.writeText(url); R.say(T.copied); } catch (_) { R.say(url); }
  }

  function leave() {
    const b = bridge();
    if (b && window.__togetherlyChrome) { try { b.callHandler('watchBack', {}); return; } catch (_) {} }
    location.href = location.pathname + location.hash;
  }

  function showWait(title, sub, spin) {
    el.wait.hidden = false;
    $('.rl-spin', el.wait).style.display = spin ? '' : 'none';
    $('b', el.wait).textContent = title;
    $('span:last-child', el.wait).textContent = sub;
  }
  function hideWait() { el.wait.hidden = true; }

  // ── канал ────────────────────────────────────────────────────────────────

  function onMessage(data) {
    switch (data.t) {
      case 'reels-subscribed':
        S.me = R.me();
        S.name = R.name() || '';
        announce();
        pull(10);
        // Партнёр уже листает — его ролик придёт ответом на «hello» комнаты.
        setTimeout(() => { S.started = true; if (!S.cur) next(); }, 1500);
        return true;
      case 'reels-viewers':
        S.viewers = data.n;
        paintTurn();
        return true;
      case 'hello':
        // Новичку — наш ролик и наша очередь. Комнате «hello» тоже нужен.
        if (S.cur) R.send('reels-state', { to: data.from, cur: S.cur, name: S.name, ids: S.mine.slice(0, 4) });
        else announce();
        return false;
      case 'reels-state':
        if (data.to !== S.me) return true;
        notePartner(data);
        if (Array.isArray(data.ids)) S.theirs = data.ids.filter((x) => !S.seen.has(x));
        if (data.cur && data.cur.id && (!S.cur || S.cur.id !== data.cur.id)) {
          if (S.cur) S.back.push(S.cur);
          show({ id: data.cur.id, owner: data.cur.owner, by: data.cur.by });
        }
        return true;
      case 'reels-queue':
        notePartner(data);
        S.theirs = (data.ids || []).filter((x) => !S.seen.has(x));
        if (S.started && !S.cur) next();
        else preloadSoon();
        return true;
      case 'reels-reel':
        notePartner(data);
        // Тот же ролик (напоминание листающего) — ничего не перезапускаем.
        if (S.cur && S.cur.id === data.id) return true;
        if (S.cur && !data.back) { S.back.push(S.cur); if (S.back.length > 30) S.back.shift(); }
        if (data.back) {
          const i = S.back.map((x) => x.id).lastIndexOf(data.id);
          if (i >= 0) S.back.splice(i);
        }
        show({ id: data.id, owner: data.owner, by: data.by }, !!data.back);
        if (S.mine.length < 4) pull(8);
        return true;
      case 'reels-react':
        notePartner(data);
        theirReaction(data);
        return true;
      case 'reels-pause':
        if (S.cur && data.id === S.cur.id) setPaused(!!data.paused);
        return true;
      default:
        if (data.t === 'chat' && data.name) notePartner(data);
        return false;
    }
  }

  function notePartner(data) {
    if (!data.from || data.from === S.me) return;
    const changed = S.partnerId !== data.from || (data.name && S.partnerName !== data.name);
    S.partnerId = data.from;
    if (data.name) S.partnerName = data.name;
    if (changed) paintTurn();
  }

  // Приложение досылает свежие номера само, когда скрытая лента их принесла.
  window.reelsFeedPush = (ids) => addMine(ids);

  // Свёрнутое приложение: оба плеера спят. Иначе, пока человека нет, они
  // крутят видео, а при возврате просыпаются разом — отсюда лаги. Зовёт
  // приложение (жизненный цикл), браузер — сменой видимости вкладки.
  let asleep = false;
  function sleep(on) {
    if (asleep === on) return;
    asleep = on;
    [cards.cur, cards.next, cards.prev].forEach((c) => {
      if (!c || !c.api || !c.ready) return;
      try {
        if (on) c.api.pause();
        else if (c !== cards.cur) c.api.shelve();
        else if (!S.paused) (c.api.revive || c.api.play)();
      } catch (_) {}
    });
  }
  window.reelsSleep = (on) => sleep(!!on);

  // Сообщение о свайпе может разминуться с партнёром: он заходил в комнату
  // в ту же секунду (проверка смешанных лент, 04.10.2026). Листавший
  // последним раз в 12 секунд напоминает, какой ролик идёт.
  setInterval(() => {
    if (!S.cur || S.cur.by !== S.me || !R.subscribed() || S.viewers < 2) return;
    R.send('reels-reel', { id: S.cur.id, owner: S.cur.owner, by: S.me, name: S.name });
  }, 12000);
  document.addEventListener('visibilitychange', () => sleep(document.hidden));
  // Для проверок: что сейчас играет и чья очередь (tests/room-reels.test.js).
  window.__reelsState = () => ({ cur: S.cur, mine: S.mine.length, theirs: S.theirs.length, viewers: S.viewers, partner: S.partnerId });

  R.onReels(onMessage);
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', build);
  else build();
})();
