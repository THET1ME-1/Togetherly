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
 * ролик сейчас не играет, — и рассылает его (`reels-reel`). Так ход
 * переходит сам: ролик из ленты Ани, следующий из ленты Бори. Один в комнате —
 * листает свою ленту.
 */
(() => {
  'use strict';

  if (!/[?&]reels=1\b/.test(location.search)) return;
  const R = window.__togetherlyRoom;
  if (!R) return;

  const RU = (window.I18N && window.I18N.lang) !== 'en';
  const T = RU ? {
    // Имена не склоняем — «ход Боря» читается ошибкой, поэтому имя всегда
    // в именительном: «Листает Боря».
    mine: 'Твой ход', theirs: (n) => 'Листает ' + n, partner: 'партнёр',
    hintMine: (n) => 'Свайп вверх — дальше листает ' + n, hintTheirs: () => 'Свайп вверх — твой ход', hintAlone: 'Свайп вверх — следующий',
    call: 'Позвонить', react: 'Реакция', chat: 'Чат', share: 'Отправить', back: 'Назад',
    loading: 'Собираем ленту…', loadingSub: 'Первые ролики приходят за несколько секунд',
    noFeed: 'Ленту даёт приложение', noFeedSub: 'Откройте «Ленты» в Togetherly на телефоне — ролики пойдут и сюда',
    match: 'Совпало!', matchSub: 'Вам обоим зашёл этот ролик', sound: 'Включить звук',
    copied: 'Ссылка скопирована', ourChat: 'Наш чат', unavailable: 'Ролик недоступен, листаем дальше',
  } : {
    mine: 'Your turn', theirs: (n) => n + ' is scrolling', partner: 'partner',
    hintMine: (n) => 'Swipe up — ' + n + ' goes next', hintTheirs: () => 'Swipe up — your turn', hintAlone: 'Swipe up for the next one',
    call: 'Call', react: 'React', chat: 'Chat', share: 'Share', back: 'Back',
    loading: 'Gathering your feed…', loadingSub: 'The first clips arrive in a few seconds',
    noFeed: 'The feed comes from the app', noFeedSub: 'Open Feeds in Togetherly on your phone and the clips will show up here too',
    match: 'It’s a match!', matchSub: 'You both liked this one', sound: 'Turn sound on',
    copied: 'Link copied', ourChat: 'Our chat', unavailable: 'Clip unavailable, moving on',
  };
  const EMOJI = ['❤️', '😂', '😮', '🥺', '🔥', '👍'];

  const bridge = () => {
    const b = window.flutter_inappwebview;
    return b && typeof b.callHandler === 'function' ? b : null;
  };

  const S = {
    me: '', name: '', partnerId: '', partnerName: '',
    mine: [],          // своя лента: номера, которые ещё не играли
    theirs: [],        // что партнёр объявил из своей
    seen: new Set(),   // что уже играло в этой комнате
    cur: null,         // { id, owner, by }
    back: [],          // прошлые ролики — для «Назад»
    viewers: 1,
    reacts: {},        // id → { me, them }
    started: false,
    paused: false,
    player: null, ready: false, wantMuted: false,
    pulling: false,
  };

  // ── разметка ─────────────────────────────────────────────────────────────

  const svg = (d, fill) => `<svg viewBox="0 0 24 24" fill="${fill ? 'currentColor' : 'none'}" stroke="${fill ? 'none' : 'currentColor'}" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${d}"/></svg>`;
  const IC = {
    back: svg('M19 12H5M11 6l-6 6 6 6'),
    up: svg('M12 19V5M6 11l6-6 6 6'),
    play: svg('M8 5.5v13l11-6.5z', true),
    chat: svg('M21 12a8 8 0 0 1-11.6 7.1L4 20l1-4.4A8 8 0 1 1 21 12z'),
    share: svg('M4 12v7a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-7M12 3v13M8 7l4-4 4 4'),
    prev: svg('M12 5v14M6 13l6 6 6-6'),
    close: svg('M6 6l12 12M18 6L6 18'),
    sound: svg('M4 9v6h4l5 4V5L8 9zM16 9a4 4 0 0 1 0 6M18.5 6.5a8 8 0 0 1 0 11'),
    react: svg('M12 20.5s-7.5-4.6-7.5-10A4.3 4.3 0 0 1 12 7.6a4.3 4.3 0 0 1 7.5 2.9c0 5.4-7.5 10-7.5 10z'),
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
        <div class="rl-paused">${IC.play}</div>
        <div class="rl-wait"><span class="rl-spin"></span><b></b><span></span></div>
      </div>
      <div class="rl-ui">
        <div class="rl-top">
          <button class="rl-ib rl-back" aria-label="${T.back}">${IC.back}</button>
          <span class="rl-pill"><span class="rl-av sm"></span><b></b><span class="rl-src">SHORTS</span></span>
        </div>
        <div class="rl-hint" hidden>${IC.up}<span></span></div>
        <div class="rl-voice" hidden><span class="rl-vlabel">${T.call}</span></div>
        <div class="rl-rail">
          <button class="rl-rx rl-react" aria-label="${T.react}"><span class="e">❤️</span><small>${T.react}</small></button>
          <button class="rl-rx rl-chatbtn" aria-label="${T.chat}">${IC.chat}<small>${T.chat}</small></button>
          <button class="rl-rx rl-share" aria-label="${T.share}">${IC.share}<small>${T.share}</small></button>
          <button class="rl-rx rl-prev" aria-label="${T.back}" disabled>${IC.prev}<small>${T.back}</small></button>
        </div>
        <div class="rl-pick" hidden></div>
        <div class="rl-feedchat"></div>
        <button class="rl-sound" hidden>${IC.sound}${T.sound}</button>
        <div class="rl-compose"></div>
      </div>
      <div class="rl-sheet">
        <button class="rl-handle" aria-label="${T.chat}"></button>
        <div class="rl-sheet-head"><b>${T.ourChat}</b><button class="rl-ib rl-close" aria-label="${T.back}">${IC.close}</button></div>
        <div class="rl-sheet-body"></div>
      </div>`;
    document.body.appendChild(root);

    el = {
      root,
      stage: $('.rl-stage', root), tap: $('.rl-tap', root), frame: $('.rl-frame', root),
      wait: $('.rl-wait', root), pill: $('.rl-pill', root), hint: $('.rl-hint', root),
      voice: $('.rl-voice', root), rail: $('.rl-rail', root), react: $('.rl-react', root),
      pick: $('.rl-pick', root), feed: $('.rl-feedchat', root), sound: $('.rl-sound', root),
      compose: $('.rl-compose', root), sheetBody: $('.rl-sheet-body', root), prev: $('.rl-prev', root),
    };

    // Живые узлы комнаты переезжают в ленту вместе со своими обработчиками:
    // звонок, поле сообщения и сама переписка.
    const voice = document.getElementById('voice');
    if (voice) {
      el.voice.appendChild(voice);
      // Кнопку звонка комната показывает, когда приложение ответило мостом.
      new MutationObserver(() => { el.voice.hidden = voice.hidden; })
        .observe(voice, { attributes: true, attributeFilter: ['hidden'] });
      el.voice.hidden = voice.hidden;
    }
    const composer = document.querySelector('.composer');
    if (composer) el.compose.appendChild(composer);
    const chat = document.getElementById('chat');
    if (chat) {
      el.sheetBody.appendChild(chat);
      new MutationObserver(mirrorChat).observe(chat, { childList: true });
    }

    for (let i = 0; i < EMOJI.length; i++) {
      const b = document.createElement('button');
      b.textContent = EMOJI[i];
      b.addEventListener('click', () => { closePick(); react(EMOJI[i]); });
      el.pick.appendChild(b);
    }

    $('.rl-back', root).addEventListener('click', leave);
    el.react.addEventListener('click', (e) => { e.stopPropagation(); el.pick.hidden ? openPick() : closePick(); });
    $('.rl-chatbtn', root).addEventListener('click', () => setChat(!el.root.classList.contains('chat-open')));
    $('.rl-close', root).addEventListener('click', () => setChat(false));
    $('.rl-handle', root).addEventListener('click', () => setChat(false));
    $('.rl-share', root).addEventListener('click', share);
    el.prev.addEventListener('click', previous);
    el.sound.addEventListener('click', unmute);
    const msg = document.getElementById('message');
    if (msg) msg.addEventListener('focus', closePick);
    wireGestures();
    document.addEventListener('click', (e) => {
      if (!el.pick.hidden && !el.pick.contains(e.target) && !el.react.contains(e.target)) closePick();
    });
    showWait(T.loading, T.loadingSub, true);
    paintTurn();
  }

  // ── жесты по ролику: свайп, касание, двойное касание ─────────────────────

  function wireGestures() {
    let y0 = 0, x0 = 0, t0 = 0, moved = false, lastTap = 0, single = 0;
    el.tap.addEventListener('pointerdown', (e) => {
      y0 = e.clientY; x0 = e.clientX; t0 = Date.now(); moved = false;
    });
    el.tap.addEventListener('pointermove', (e) => {
      if (Math.abs(e.clientY - y0) > 12) moved = true;
    });
    el.tap.addEventListener('pointerup', (e) => {
      const dy = e.clientY - y0;
      if (moved && Math.abs(dy) > 50 && Date.now() - t0 < 900) {
        if (el.root.classList.contains('chat-open')) { if (dy > 0) setChat(false); return; }
        if (dy < 0) next(); else previous();
        return;
      }
      if (moved) return;
      closePick();
      const now = Date.now();
      if (now - lastTap < 300) {
        // Двойное касание — сердце, как в лентах платформ.
        clearTimeout(single);
        lastTap = 0;
        heartAt(e.clientX, e.clientY);
        if (!S.cur || (S.reacts[S.cur.id] || {}).me !== '❤️') react('❤️');
        return;
      }
      lastTap = now;
      single = setTimeout(() => togglePause(true), 300);
    });
    // Колесо и клавиши — для компьютера.
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
  let wheelLock = false;

  function heartAt(x, y) {
    const h = document.createElement('div');
    h.className = 'rl-heart';
    h.textContent = '❤️';
    const box = el.root.getBoundingClientRect();
    h.style.left = (x - box.left) + 'px';
    h.style.top = (y - box.top) + 'px';
    el.root.appendChild(h);
    setTimeout(() => h.remove(), 950);
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

  // ── ход, реакции, переписка ──────────────────────────────────────────────

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
    $('span', el.hint).textContent = !together ? T.hintAlone : (mine ? T.hintMine(pName) : T.hintTheirs(pName));
  }

  function openPick() {
    const r = el.react.getBoundingClientRect();
    const box = el.root.getBoundingClientRect();
    el.pick.style.top = (r.top - box.top + r.height / 2 - 26) + 'px';
    const mine = S.cur ? (S.reacts[S.cur.id] || {}).me : '';
    Array.from(el.pick.children).forEach((b) => b.classList.toggle('is-on', b.textContent === mine));
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
    $('.e', el.react).textContent = r.me || '❤️';
    el.react.classList.toggle('is-on', !!r.me);
  }

  function theirReaction(data) {
    const r = S.reacts[data.id] || (S.reacts[data.id] = {});
    r.them = data.e || '';
    if (!S.cur || data.id !== S.cur.id || !r.them) return;
    const pop = document.createElement('div');
    pop.className = 'rl-pop';
    pop.innerHTML = '<span class="rl-av sm is-partner"></span><span></span>';
    pop.firstChild.textContent = initial(S.partnerName);
    pop.lastChild.textContent = r.them;
    const rr = el.react.getBoundingClientRect();
    const box = el.root.getBoundingClientRect();
    pop.style.top = (rr.top - box.top + 6) + 'px';
    el.root.appendChild(pop);
    setTimeout(() => pop.remove(), 2700);
    if (r.me && r.me === r.them) matched(r.me);
  }

  function matched(e) {
    const old = $('.rl-match', el.root);
    if (old) old.remove();
    const m = document.createElement('div');
    m.className = 'rl-match';
    m.innerHTML = '<span class="e"></span><span><b></b><small></small></span>';
    m.querySelector('.e').textContent = e;
    m.querySelector('b').textContent = T.match;
    m.querySelector('small').textContent = T.matchSub;
    el.root.appendChild(m);
    setTimeout(() => m.remove(), 3500);
  }

  /** Две свежие реплики висят над полем ввода и гаснут, весь чат — в листе. */
  let fadeTimer = 0;
  function mirrorChat() {
    const chat = document.getElementById('chat');
    if (!chat) return;
    const last = Array.from(chat.children).slice(-2);
    el.feed.innerHTML = '';
    last.forEach((m, i) => {
      const c = m.cloneNode(true);
      if (i < last.length - 1) c.classList.add('is-old');
      el.feed.appendChild(c);
    });
    el.feed.style.opacity = '1';
    clearTimeout(fadeTimer);
    fadeTimer = setTimeout(() => { el.feed.style.opacity = '0'; }, 7000);
    el.feed.style.transition = 'opacity .6s';
  }

  function setChat(on) {
    closePick();
    el.root.classList.toggle('chat-open', on);
    $('.rl-chatbtn', el.root).classList.toggle('is-on', on);
    const chat = document.getElementById('chat');
    if (on && chat) setTimeout(() => { chat.scrollTop = chat.scrollHeight; }, 50);
  }

  function shortUrl() { return S.cur ? 'https://youtube.com/shorts/' + S.cur.id : ''; }

  async function share() {
    const url = shortUrl();
    if (!url) return;
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
