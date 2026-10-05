/* Совместная лента на своей странице (/watch/reels/), без комнаты под ней.
 *
 * До 05.10.2026 лента жила поверх страницы комнаты: комната грузилась целиком,
 * мелькала при входе, а лента нажимала её спрятанные кнопки. Тест стережёт
 * переезд:
 *   - на странице ленты нет ни одного узла комнаты;
 *   - старый адрес `/watch/room/?reels=1` уводит на новую страницу с теми же
 *     параметрами и кодом — так открывают ленту выпущенные сборки;
 *   - комната и лента пишут друг другу (`chat`), а пришедший в ленту получает
 *     историю переписки от того, кто сидит в комнате (`hello` → `state`);
 *   - чужой код не оставляет ленту в вечном «Собираем ленту»: страница говорит,
 *     что случилось, и ведёт дальше.
 *
 * Две вкладки тестовой пары (вход — ~/keys/togetherly-test-pair.txt), страницы
 * — локальная копия pb_public, /api уходит на прод.
 *
 * Запуск: node pocketbase/pb_public/watch/tests/reels-page.test.js
 */
const { chromium } = require('/home/alelx/.hermes/hermes-agent/node_modules/playwright');
const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..');
const PORT = 8798;
const PROD = 'https://togetherly.day';
const PAIR = 'r5269c54ac34919';
const BASE = `http://127.0.0.1:${PORT}`;

function creds() {
  const t = fs.readFileSync(path.join(process.env.HOME, 'keys/togetherly-test-pair.txt'), 'utf8');
  const m = [...t.matchAll(/(claude-test-231[ab]@togetherly\.day) \/ (\S+)/g)];
  return m.map((x) => ({ email: x[1], password: x[2] }));
}

function api(p, body, token) {
  return fetch(PROD + p, {
    method: 'POST',
    headers: Object.assign({ 'Content-Type': 'application/json' }, token ? { Authorization: token } : {}),
    body: JSON.stringify(body),
  }).then((r) => r.json());
}

function serve() {
  return new Promise((resolve) => {
    const srv = http.createServer((req, res) => {
      if (req.url.startsWith('/api/')) {
        const body = [];
        req.on('data', (c) => body.push(c));
        req.on('end', () => {
          const h = { 'content-type': req.headers['content-type'] || 'application/json' };
          if (req.headers.authorization) h.authorization = req.headers.authorization;
          const up = https.request(PROD + req.url, { method: req.method, headers: h },
            (r) => { res.writeHead(r.statusCode, r.headers); r.pipe(res); });
          up.end(Buffer.concat(body));
        });
        return;
      }
      let p = decodeURIComponent(req.url.split('?')[0].split('#')[0]);
      if (p.endsWith('/')) p += 'index.html';
      const file = path.join(ROOT, p);
      if (!file.startsWith(ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
        res.writeHead(404); res.end(); return;
      }
      const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.woff2': 'font/woff2', '.webp': 'image/webp' };
      res.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream' });
      res.end(fs.readFileSync(file));
    });
    srv.listen(PORT, '127.0.0.1', () => resolve(srv));
  });
}

let ok = true;
const check = (n, c, x = '') => { console.log((c ? '  ✓ ' : '  ✗ ') + n, x); if (!c) ok = false; };

(async () => {
  const [a, b] = creds();
  const authA = await api('/api/collections/users/auth-with-password', { identity: a.email, password: a.password });
  const authB = await api('/api/collections/users/auth-with-password', { identity: b.email, password: b.password });
  const room = (await api('/api/watch/room', { groupId: PAIR }, authA.token)).room;
  check('код комнаты пары', !!room, room);

  const srv = await serve();
  const browser = await chromium.launch();
  const errors = [];

  /** Вкладка с сессией пары и заглушкой моста приложения. */
  const tab = async (auth, name, bridge) => {
    const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, locale: 'ru-RU' });
    await ctx.addInitScript(({ token, name, bridge }) => {
      if (token) window.__togetherlyAuth = { token, name };
      if (bridge) window.flutter_inappwebview = { callHandler: async () => [] };
    }, { token: auth ? auth.token : '', name, bridge });
    const page = await ctx.newPage();
    page.on('pageerror', (e) => errors.push(name + ': ' + e.message));
    return page;
  };

  // ── 1. Старый адрес уводит на новую страницу ─────────────────────────────
  const old = await tab(authA, 'Аня', true);
  const done = [];
  const tokens = [];
  old.on('requestfinished', (r) => done.push(new URL(r.url()).pathname));
  old.on('request', (r) => { if (/\/api\/watch\/token/.test(r.url())) tokens.push(r.frame().url()); });
  await old.goto(`${BASE}/watch/room/?reels=1&feed=tiktok&name=${encodeURIComponent('Аня')}#${room}`);
  await old.waitForTimeout(2500);
  const u = new URL(old.url());
  check('старый адрес ведёт на /watch/reels/', u.pathname === '/watch/reels/', u.pathname);
  check('параметры и код комнаты сохранились',
    u.searchParams.get('feed') === 'tiktok' && u.searchParams.get('name') === 'Аня' && u.hash === '#' + room, u.search + u.hash);
  check('скрипт комнаты не загрузился', !done.some((p) => /\/room\/room\.js$/.test(p)), done.filter((p) => /room/.test(p)).join(', '));
  check('в канал входила только лента, один раз', tokens.length === 1 && /\/watch\/reels\//.test(tokens[0]), tokens.join(' | '));
  await old.close();

  // ── 2. Комната и лента пишут друг другу ─────────────────────────────────
  const roomPage = await tab(authA, 'Аня', false);
  await roomPage.goto(`${BASE}/watch/room/?name=${encodeURIComponent('Аня')}#${room}`);
  await roomPage.waitForFunction(() => /Подключено|Connected|готов/i.test(document.querySelector('#status').textContent) || !!document.querySelector('#chat'), null, { timeout: 15000 });
  await roomPage.waitForTimeout(2500);
  // История: Аня написала до прихода Бори.
  await roomPage.fill('#message', 'до тебя');
  await roomPage.click('#send');
  await roomPage.waitForTimeout(800);

  const reels = await tab(authB, 'Боря', true);
  await reels.goto(`${BASE}/watch/reels/?feed=shorts&name=${encodeURIComponent('Боря')}#${room}`);
  await reels.waitForTimeout(5000);

  const roomNodes = await reels.evaluate(() =>
    ['#stage', '#player', '#chat', '#message', '#gate', '.top', '.stage-wrap', '#voice'].filter((s) => document.querySelector(s)));
  check('на странице ленты нет узлов комнаты', roomNodes.length === 0, roomNodes.join(', '));
  check('лента на месте', await reels.evaluate(() => !!document.querySelector('.rl.is-in')));

  const list = () => reels.evaluate(() => Array.from(document.querySelectorAll('.rl-list .rl-msg')).map((m) => m.textContent));
  check('в ленту пришла история из комнаты', (await list()).some((t) => /до тебя/.test(t)), JSON.stringify(await list()));

  await roomPage.fill('#message', 'привет из комнаты');
  await roomPage.click('#send');
  await reels.waitForTimeout(1500);
  check('реплика из комнаты видна в ленте', (await list()).some((t) => /привет из комнаты/.test(t)));
  check('у реплики имя Ани', (await list()).some((t) => /Аня/.test(t) && /привет из комнаты/.test(t)));

  await reels.fill('.rl-input', 'привет из ленты');
  await reels.click('.rl-send');
  await roomPage.waitForTimeout(1500);
  const roomChat = await roomPage.evaluate(() => document.querySelector('#chat').textContent);
  check('реплика из ленты видна в комнате', /привет из ленты/.test(roomChat) && /Боря/.test(roomChat), roomChat.slice(-80));
  check('своя реплика в ленте помечена своей', await reels.evaluate(() =>
    Array.from(document.querySelectorAll('.rl-list .rl-msg.me')).some((m) => /привет из ленты/.test(m.textContent))));

  // ── 3. Звонок: кнопка только после ответа приложения ────────────────────
  check('без ответа приложения кнопки звонка нет', await reels.evaluate(() => document.querySelector('.rl-voice').hidden));
  await reels.evaluate(() => window.watchVoiceState({ state: 'off' }));
  check('ответило приложение — кнопка звонка есть', await reels.evaluate(() =>
    !document.querySelector('.rl-voice').hidden && !document.querySelector('.rl-call').hidden));
  await reels.evaluate(() => window.watchVoiceState({ state: 'connecting' }));
  check('звоним: трубка и «ждём ответа»', await reels.evaluate(() =>
    !document.querySelector('.rl-hang').hidden && document.querySelector('.rl-vtime').textContent.length > 0));
  const said = [];
  await reels.exposeFunction('__said', (x) => said.push(x));
  await reels.evaluate(() => { window.flutter_inappwebview.callHandler = async (h, a) => { if (h === 'watchVoice') window.__said(a.action); return []; }; });
  await reels.click('.rl-hang');
  await reels.waitForTimeout(200);
  check('«положить трубку» уходит в приложение', said.includes('hangup'), said.join(','));

  // ── 4. Чужой код: страница говорит, что случилось ───────────────────────
  const stranger = await tab(null, 'Гость', false);
  await stranger.goto(`${BASE}/watch/reels/?feed=shorts#zzzzzzzz`);
  await stranger.waitForTimeout(4000);
  const wait = await stranger.evaluate(() => {
    const w = document.querySelector('.rl-wait');
    const go = document.querySelector('.rl-go');
    return { shown: !w.hidden, title: w.querySelector('b').textContent, go: go && !go.hidden ? go.getAttribute('href') : '' };
  });
  check('без пропуска — не «Собираем ленту», а причина', wait.shown && !/Собираем/.test(wait.title), wait.title);
  check('и кнопка, куда идти', !!wait.go, wait.go);

  check('страницы без ошибок', errors.length === 0, errors.join(' | '));

  await browser.close();
  srv.close();
  console.log(ok ? 'ВСЁ ПРОШЛО' : 'ЕСТЬ ПРОВАЛЫ');
  process.exit(ok ? 0 : 1);
})().catch((e) => { console.error(e); process.exit(1); });
