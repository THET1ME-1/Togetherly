// Живой регресс доступа в комнаты совместного просмотра.
//
// 16.09.2026 к паре в `watch:4ejxgjve` зашли двое посторонних: сервер выдавал
// пропуск на любой код, а Centrifugo вдобавок пускал в любой `watch:*` без
// пропуска подписки. Здесь проверяется, что обе двери закрыты, а свои по-прежнему
// входят — и из браузера со входом, и из выпущенных сборок приложения, которые
// открывают комнату без сессии (их пускает поручительство подключения
// приложения к каналу).
//
// Гоняется по живому серверу, за собой убирает:
//     node pocketbase/watch_access.test.mjs

const BASE = process.argv[2] || 'https://togetherly.day';
const WS = BASE.replace(/^http/, 'ws') + '/connection/websocket';
const T0 = Date.now();
const ok = [];
const fail = [];

const log = (...a) => console.log(`[${((Date.now() - T0) / 1000).toFixed(2).padStart(6)}s]`, ...a);
function check(name, cond, detail = '') {
  (cond ? ok : fail).push(name);
  log((cond ? '  ✓ ' : '  ✗ ') + name + (cond || !detail ? '' : ` — ${detail}`));
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const rnd = (n) => Array.from({ length: n }, () => 'abcdefghijklmnopqrstuvwxyz0123456789'[Math.floor(Math.random() * 36)]).join('');

async function api(path, body, token, method) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = token;
  const res = await fetch(BASE + path, {
    method: method || (body !== undefined ? 'POST' : 'GET'),
    headers,
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  let data = {};
  try { data = await res.json(); } catch (_) { data = {}; }
  return [res.status, data];
}

async function signup(tag) {
  const email = `watch-probe-${tag}-${rnd(6)}@example.com`;
  const pwd = 'Probe' + rnd(10) + '!';
  let [st, r] = await api('/api/collections/users/records', {
    email, password: pwd, passwordConfirm: pwd, name: `Probe ${tag}`, display_name: `Probe ${tag}`,
  });
  if (st !== 200 && st !== 201) throw new Error(`регистрация ${tag}: ${st} ${JSON.stringify(r)}`);
  [st, r] = await api('/api/collections/users/auth-with-password', { identity: email, password: pwd });
  log(`${tag}: uid=${r.record.id}`);
  return { uid: r.record.id, token: r.token };
}

/** Клиент Centrifugo на голом протоколе: подключиться и подписаться. */
function rt(connToken) {
  const ws = new WebSocket(WS);
  let seq = 0;
  const waiting = new Map();
  ws.addEventListener('message', (ev) => {
    String(ev.data).split('\n').filter(Boolean).forEach((line) => {
      let msg;
      try { msg = JSON.parse(line); } catch (_) { return; }
      if (!msg.id) { if (Object.keys(msg).length === 0) ws.send('{}'); return; }
      const done = waiting.get(msg.id);
      if (done) { waiting.delete(msg.id); done(msg); }
    });
  });
  const call = (cmd) => new Promise((resolve) => {
    seq += 1;
    waiting.set(seq, resolve);
    ws.send(JSON.stringify({ id: seq, ...cmd }));
    setTimeout(() => { if (waiting.delete(seq)) resolve({ error: { code: -1, message: 'timeout' } }); }, 8000);
  });
  const opened = new Promise((resolve, reject) => {
    ws.addEventListener('open', resolve, { once: true });
    ws.addEventListener('error', reject, { once: true });
  });
  return {
    async connect() { await opened; return call({ connect: { token: connToken, name: 'probe' } }); },
    subscribe: (channel, token) => call({ subscribe: token ? { channel, token } : { channel } }),
    close: () => { try { ws.close(); } catch (_) {} },
  };
}

async function main() {
  const her = await signup('Она');
  const stranger = await signup('Чужой');
  const sockets = [];
  let pair = '';

  try {
    log('=== пара и её комната ===');
    let [st, r] = await api('/api/waiting/create', { name: 'Проба', returnDate: '' }, her.token);
    pair = r.pairId || '';
    check('пара заведена', st === 200 && !!pair, `${st} ${JSON.stringify(r)}`);

    let room = '';
    // Свежую пару зеркало групп подхватывает за пару минут.
    for (let i = 0; i < 40 && !room; i++) {
      [st, r] = await api('/api/watch/room', { groupId: pair }, her.token);
      room = (st === 200 && r.room) || '';
      if (!room) await sleep(5000);
    }
    check('код комнаты пары выдан', /^[efghjkuvwxyz2345]{8}$/.test(room), `${st} ${JSON.stringify(r)}`);

    log('=== 1. набранный руками код ===');
    [st, r] = await api('/api/watch/token', { room: 'zq' + rnd(4) });
    check('выдуманный код: комнаты нет', st === 404 && r.error === 'not_found', `${st} ${JSON.stringify(r)}`);
    [st, r] = await api('/api/watch/token', { room: '23452345' });
    check('цифры в форме кода пары: без входа не пускает', st === 401, `${st} ${JSON.stringify(r)}`);

    log('=== 2. открытая комната ===');
    [st, r] = await api('/api/watch/new', {});
    const open = r.room || '';
    check('сервер выдал код открытой комнаты', st === 200 && open.length === 10, `${st} ${JSON.stringify(r)}`);
    [st, r] = await api('/api/watch/token', { room: open });
    check('в открытую комнату пускают без входа', st === 200 && r.kind === 'open', `${st} ${JSON.stringify(r)}`);
    const guestOpen = r;
    const forged = open.slice(0, 9) + (open[9] === 'a' ? 'b' : 'a');
    [st, r] = await api('/api/watch/token', { room: forged });
    check('подделанная подпись: комнаты нет', st === 404, `${st} ${JSON.stringify(r)}`);

    log('=== 3. комната пары ===');
    [st, r] = await api('/api/watch/token', { room });
    check('без входа и без приложения: просят войти', st === 401 && r.error === 'auth_required', `${st} ${JSON.stringify(r)}`);
    [st, r] = await api('/api/watch/token', { room }, stranger.token);
    check('чужой аккаунт: не пускают', st === 403 && r.error === 'not_member', `${st} ${JSON.stringify(r)}`);
    [st, r] = await api('/api/watch/token', { room }, her.token);
    check('участница пары: пускают', st === 200 && r.kind === 'member', `${st} ${JSON.stringify(r)}`);

    log('=== 4. в канал пары без пропуска не войти ===');
    const sneak = rt(guestOpen.connectionToken);
    sockets.push(sneak);
    const c1 = await sneak.connect();
    check('гость открытой комнаты подключился', !c1.error, JSON.stringify(c1));
    const s1 = await sneak.subscribe('watch:' + room);
    check('подписка на комнату пары без пропуска отбита', !!s1.error, JSON.stringify(s1));
    const s2 = await sneak.subscribe(guestOpen.channel, guestOpen.subscriptionToken);
    check('своя открытая комната по пропуску работает', !s2.error, JSON.stringify(s2));

    log('=== 5. выпущенная сборка приложения ===');
    [st, r] = await api('/api/centrifugo/connection-token', {}, her.token);
    const appConn = r.token;
    [st, r] = await api('/api/centrifugo/subscription-token', { channel: 'watch:' + room }, her.token);
    check('приложению выдан пропуск в свою комнату', st === 200 && !!r.token, `${st} ${JSON.stringify(r)}`);
    const app = rt(appConn);
    sockets.push(app);
    await app.connect();
    const s3 = await app.subscribe('watch:' + room, r.token);
    check('приложение сидит в канале', !s3.error, JSON.stringify(s3));
    await sleep(500);

    const gA = 'g' + rnd(14);
    const gB = 'g' + rnd(14);
    [st, r] = await api('/api/watch/token', { room, guest: gA });
    check('страница рядом с приложением входит без сессии', st === 200 && r.kind === 'vouch', `${st} ${JSON.stringify(r)}`);
    const page = rt(r.connectionToken);
    sockets.push(page);
    await page.connect();
    const s4 = await page.subscribe(r.channel, r.subscriptionToken);
    check('страница подписалась', !s4.error, JSON.stringify(s4));
    await sleep(500);

    [st, r] = await api('/api/watch/token', { room, guest: gB });
    check('второй без сессии: место занято, просят войти', st === 401, `${st} ${JSON.stringify(r)}`);
    [st, r] = await api('/api/watch/token', { room, guest: gA });
    check('перезагрузка своей страницы: пускают', st === 200 && r.kind === 'vouch', `${st} ${JSON.stringify(r)}`);
  } finally {
    sockets.forEach((s) => s.close());
    log('=== уборка ===');
    if (pair) {
      const [st] = await api('/api/waiting/cancel', { groupId: pair }, her.token);
      log(`пара распущена → ${st}`);
    }
    for (const [name, u] of [['Она', her], ['Чужой', stranger]]) {
      const [st] = await api(`/api/collections/users/records/${u.uid}`, undefined, u.token, 'DELETE');
      log(`аккаунт ${name} удалён → ${st}`);
    }
  }

  log(`ИТОГ: пройдено ${ok.length}, провалено ${fail.length}` + (fail.length ? ` → ${fail.join('; ')}` : ''));
  process.exit(fail.length ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
