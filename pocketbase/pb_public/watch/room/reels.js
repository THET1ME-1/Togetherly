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
  // Имена не склоняем — «ход Боря» читается ошибкой, поэтому имя всегда в
  // именительном: «Листает Боря».
  const T = RU ? {
    mine: 'Твой ход', theirs: (n) => 'Листает ' + n, partner: 'партнёр',
    hintMine: (n) => 'Свайп вверх — дальше листает ' + n, hintTheirs: 'Свайп вверх — твой ход', hintAlone: 'Свайп вверх — следующий',
    call: 'Позвонить', react: 'Реакция', chat: 'Чат', share: 'Отправить ролик', prev: 'Прошлый ролик', back: 'Назад',
    mic: 'Микрофон', hang: 'Положить трубку', ringing: 'Звоним…', failed: 'Не вышло',
    write: () => 'Написать…', send: 'Отправить',
    loading: 'Собираем ленту…', loadingSub: 'Первые ролики приходят за несколько секунд',
    noFeed: 'Ленту даёт приложение', noFeedSub: 'Откройте «Ленты» в Togetherly на телефоне — ролики пойдут и сюда',
    match: 'Совпало!', matchSub: 'Вам обоим зашёл этот ролик', sound: 'Включить звук',
    copied: 'Ссылка скопирована', ourChat: 'Наш чат', empty: 'Здесь пока пусто', unavailable: 'Ролик недоступен, листаем дальше',
  } : {
    mine: 'Your turn', theirs: (n) => n + ' is scrolling', partner: 'partner',
    hintMine: (n) => 'Swipe up — ' + n + ' goes next', hintTheirs: 'Swipe up — your turn', hintAlone: 'Swipe up for the next one',
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
  const ic = (c) => '<span class="ms" aria-hidden="true">' + c + '</span>';

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

  const S = {
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
        <div class="rl-frame"><div id="rlPlayer"></div></div>
        <div class="rl-shade"></div>
        <div class="rl-tap"></div>
        <div class="rl-paused">${ic(IC.play)}</div>
        <div class="rl-wait"><span class="rl-spin"></span><b></b><span></span></div>
      </div>
      <div class="rl-sheet">
        <span class="rl-handle"></span>
        <div class="rl-tabs"><span>${T.ourChat}</span></div>
        <div class="rl-list"></div>
      </div>
      <div class="rl-ui">
        <div class="rl-top">
          <button class="rl-ib rl-back" aria-label="${T.back}">${ic(IC.back)}</button>
          <span class="rl-pill"><span class="rl-av"></span><b></b><span class="rl-src">SHORTS</span></span>
        </div>
        <div class="rl-hint" hidden>${ic(IC.swipe)}<span></span></div>
        <div class="rl-side">
        <div class="rl-voice" hidden>
          <button class="rl-ib accent rl-call" aria-label="${T.call}">${ic(IC.call)}</button>
          <span class="rl-vlabel">${T.call}</span>
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
      stage: $('.rl-stage', root), tap: $('.rl-tap', root), frame: $('.rl-frame', root),
      wait: $('.rl-wait', root), pill: $('.rl-pill', root), hint: $('.rl-hint', root),
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

    $('.rl-back', root).addEventListener('click', leave);
    el.react.addEventListener('click', (e) => { e.stopPropagation(); el.pick.hidden ? openPick() : closePick(); });
    $('.rl-chatbtn', root).addEventListener('click', () => setChat(!el.root.classList.contains('chat-open')));
    $('.rl-handle', root).addEventListener('click', () => setChat(false));
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
      $('.rl-vlabel', el.voice).hidden = busy;
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
    let y0 = 0, t0 = 0, moved = false, lastTap = 0, single = 0;
    el.tap.addEventListener('pointerdown', (e) => { y0 = e.clientY; t0 = Date.now(); moved = false; });
    el.tap.addEventListener('pointermove', (e) => { if (Math.abs(e.clientY - y0) > 12) moved = true; });
    el.tap.addEventListener('pointerup', (e) => {
      const dy = e.clientY - y0;
      if (moved && Math.abs(dy) > 50 && Date.now() - t0 < 900) {
        if (el.root.classList.contains('chat-open')) { if (dy > 0) setChat(false); return; }
        if (dy < 0) next(); else previous();
        return;
      }
      if (moved) return;
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
    });
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
    (ids || []).forEach((id) => {
      if (typeof id !== 'string' || !/^[A-Za-z0-9_-]{11}$/.test(id)) return;
      if (S.seen.has(id) || S.mine.indexOf(id) >= 0) return;
      S.mine.push(id);
      added++;
    });
    if (!added) return;
    announce();
    if (S.started && !S.cur) next();
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
      return;
    }
    if (owner === S.me) announce();
    if (S.cur) { S.back.push(S.cur); if (S.back.length > 30) S.back.shift(); }
    const cur = { id, owner, by: S.me };
    show(cur);
    R.send('reels-reel', { id, owner, by: S.me, name: S.name });
  }

  function previous() {
    const prev = S.back.pop();
    if (!prev) return;
    const cur = { id: prev.id, owner: prev.owner, by: S.me };
    show(cur, true);
    R.send('reels-reel', { id: cur.id, owner: cur.owner, by: S.me, name: S.name, back: true });
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
    el.frame.classList.remove('rl-slide');
    void el.frame.offsetWidth;
    if (!isBack) el.frame.classList.add('rl-slide');
    play(cur.id);
    // Ролик из своей ленты: скрытая страница приложения «смотрит» его тоже,
    // без звука. Так платформа засчитывает просмотр, а рекомендации учатся.
    const b = bridge();
    if (b && cur.owner === S.me) { try { b.callHandler('reelsWatching', { id: cur.id }); } catch (_) {} }
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

  let soundCheck = 0;
  function play(id) {
    whenYT(() => {
      if (!S.player) {
        S.player = new YT.Player('rlPlayer', {
          videoId: id,
          playerVars: { autoplay: 1, controls: 0, playsinline: 1, rel: 0, modestbranding: 1, fs: 0, iv_load_policy: 3, disablekb: 1, loop: 1, playlist: id },
          events: {
            onReady: () => {
              S.ready = true;
              const iframe = S.player.getIframe && S.player.getIframe();
              if (iframe) iframe.referrerPolicy = 'strict-origin-when-cross-origin';
              if (S.wantMuted) S.player.mute();
              S.player.playVideo();
              checkSound();
            },
            onStateChange: (e) => {
              if (e.data === YT.PlayerState.ENDED) { S.player.seekTo(0, true); S.player.playVideo(); }
            },
            onError: () => {
              // Ролик закрыт для встраивания или удалён. Дальше листает тот,
              // кто его включил, чтобы двое не перескочили дважды.
              if (!S.cur || S.cur.by !== S.me) return;
              R.say(T.unavailable);
              setTimeout(next, 600);
            },
          },
        });
        return;
      }
      if (!S.ready) { setTimeout(() => play(id), 300); return; }
      S.player.loadVideoById({ videoId: id });
      checkSound();
    });
  }

  /** Браузер без касания не даст звук: тогда играем без него и предлагаем включить. */
  function checkSound() {
    clearTimeout(soundCheck);
    soundCheck = setTimeout(() => {
      if (!S.player || S.paused) return;
      let st = -1;
      try { st = S.player.getPlayerState(); } catch (_) {}
      if (st !== YT.PlayerState.PLAYING && st !== YT.PlayerState.BUFFERING) {
        S.wantMuted = true;
        try { S.player.mute(); S.player.playVideo(); } catch (_) {}
        el.sound.hidden = false;
      }
    }, 1800);
  }

  function unmute() {
    S.wantMuted = false;
    el.sound.hidden = true;
    try { S.player.unMute(); S.player.setVolume(100); S.player.playVideo(); } catch (_) {}
  }

  function togglePause(tell) {
    if (!S.player || !S.cur) return;
    if (!el.sound.hidden) { unmute(); return; }
    setPaused(!S.paused);
    if (tell) R.send('reels-pause', { id: S.cur.id, paused: S.paused });
  }

  function setPaused(p) {
    S.paused = p;
    el.root.classList.toggle('is-paused', p);
    try { if (p) S.player.pauseVideo(); else S.player.playVideo(); } catch (_) {}
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
    const together = S.viewers > 1 && S.partnerId;
    el.hint.hidden = !S.cur;
    $('span:last-child', el.hint).textContent = !together ? T.hintAlone : (mine ? T.hintMine(pName) : T.hintTheirs);
    el.input.placeholder = T.write(together ? S.partnerName : '');
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
    if (on) setTimeout(() => { el.list.scrollTop = el.list.scrollHeight; }, 50);
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
        return true;
      case 'reels-reel':
        notePartner(data);
        if (S.cur && S.cur.id !== data.id && !data.back) { S.back.push(S.cur); if (S.back.length > 30) S.back.shift(); }
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
  // Для проверок: что сейчас играет и чья очередь (tests/room-reels.test.js).
  window.__reelsState = () => ({ cur: S.cur, mine: S.mine.length, theirs: S.theirs.length, viewers: S.viewers, partner: S.partnerId });

  R.onReels(onMessage);
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', build);
  else build();
})();
