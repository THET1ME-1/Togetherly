/* Ленты под нагрузкой: быстрые свайпы подряд, утечка карточек, обновление.
 *
 * Один человек, лента Rutube. Двадцать свайпов с паузой 120 мс (быстрее
 * анимации), потом свайпы туда-обратно, потом «обновить рекомендации».
 * Проверяем: карточек в странице не больше трёх (иначе плееры копятся и
 * съедают поток), текущая на месте и на экране, ошибок в странице нет,
 * обновление включает свежий ролик.
 *
 * Запуск: node pocketbase/pb_public/watch/tests/room-reels-stress.test.js
 */
const { chromium } = require('/home/alelx/.hermes/hermes-agent/node_modules/playwright');
const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..');
const PORT = 8801;
const PROD = 'https://togetherly.day';
const PAIR = 'r5269c54ac34919';

function creds() {
  const t = fs.readFileSync(path.join(process.env.HOME, 'keys/togetherly-test-pair.txt'), 'utf8');
  return [...t.matchAll(/(claude-test-231[ab]@togetherly\.day) \/ (\S+)/g)].map((x) => ({ email: x[1], password: x[2] }));
}
const api = (p, body, token) => fetch(PROD + p, { method: 'POST', headers: Object.assign({ 'Content-Type': 'application/json' }, token ? { Authorization: token } : {}), body: JSON.stringify(body) }).then((r) => r.json());

function serve() {
  return new Promise((resolve) => {
    const srv = http.createServer((req, res) => {
      if (req.url.startsWith('/api/')) {
        const body = [];
        req.on('data', (c) => body.push(c));
        req.on('end', () => {
          const h = { 'content-type': req.headers['content-type'] || 'application/json' };
          if (req.headers.authorization) h.authorization = req.headers.authorization;
          https.request(PROD + req.url, { method: req.method, headers: h }, (r) => { res.writeHead(r.statusCode, r.headers); r.pipe(res); }).end(Buffer.concat(body));
        });
        return;
      }
      let p = decodeURIComponent(req.url.split('?')[0].split('#')[0]);
      if (p.endsWith('/')) p += 'index.html';
      const file = path.join(ROOT, p);
      if (!file.startsWith(ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); res.end(); return; }
      const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.woff2': 'font/woff2', '.webp': 'image/webp' };
      res.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream' });
      res.end(fs.readFileSync(file));
    });
    srv.listen(PORT, '127.0.0.1', () => resolve(srv));
  });
}

async function harvest(browser, n) {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, isMobile: true, userAgent: 'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Mobile Safari/537.36' });
  const page = await ctx.newPage();
  const ids = new Set();
  page.on('response', async (r) => {
    if (!/shorts\/lenta/.test(r.url())) return;
    try { for (const m of (await r.text()).matchAll(/"id":"([0-9a-f]{32})"/g)) ids.add(m[1]); } catch (_) {}
  });
  await page.goto('https://rutube.ru/shorts/', { timeout: 60000 }).catch(() => {});
  for (let i = 0; i < 10 && ids.size < n; i++) { await page.waitForTimeout(2500); await page.keyboard.press('ArrowDown').catch(() => {}); }
  await ctx.close();
  return [...ids];
}

let ok = true;
const check = (n, c, x = '') => { console.log((c ? '  ✓ ' : '  ✗ ') + n, x); if (!c) ok = false; };

(async () => {
  const [a] = creds();
  const auth = await api('/api/collections/users/auth-with-password', { identity: a.email, password: a.password });
  const room = (await api('/api/watch/room', { groupId: PAIR }, auth.token)).room;
  const srv = await serve();
  const browser = await chromium.launch({ args: ['--autoplay-policy=no-user-gesture-required'] });
  const ids = await harvest(browser, 30);
  check('лента собрана', ids.length >= 12, ids.length + ' роликов');
  const first = ids.slice(0, ids.length - 4);
  const fresh = ids.slice(ids.length - 4);
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, isMobile: true, hasTouch: true });
  await ctx.addInitScript(({ token, first, fresh }) => {
    window.__togetherlyAuth = { token, name: 'Аня' };
    let feed = first.slice();
    window.flutter_inappwebview = { callHandler: async (h, arg) => {
      if (h === 'reelsFeed') return feed.splice(0, (arg && arg.need) || 8);
      // Обновление: приложение выбрасывает запас, лента приходит свежая.
      if (h === 'reelsRefresh') { feed = fresh.slice(); return null; }
      return null;
    } };
  }, { token: auth.token, first, fresh });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.goto(`http://127.0.0.1:${PORT}/watch/room/?reels=1&feed=rutube&name=A#${room}`);
  await page.waitForTimeout(9000);
  const cdp = await ctx.newCDPSession(page);
  const touch = (type, y) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: type === 'touchEnd' ? [] : [{ x: 196, y }] });
  const swipe = async (up) => {
    const [a, b] = up ? [650, 250] : [250, 650];
    await touch('touchStart', a);
    for (let i = 1; i <= 6; i++) await touch('touchMove', a + (b - a) * i / 6);
    await touch('touchEnd', b);
  };
  const state = () => page.evaluate(() => {
    const cur = document.querySelector('.rl-card.is-cur');
    const r = cur && cur.getBoundingClientRect();
    return { id: window.__reelsState().cur && window.__reelsState().cur.id, cards: document.querySelectorAll('.rl-card').length, curs: document.querySelectorAll('.rl-card.is-cur').length, top: r ? Math.round(r.top) : null, mine: window.__reelsState().mine };
  });

  const s0 = await state();
  for (let i = 0; i < 20; i++) { await swipe(true); await page.waitForTimeout(120); }
  await page.waitForTimeout(1500);
  const s1 = await state();
  check('после 20 быстрых свайпов ролик сменился', s1.id && s1.id !== s0.id, s0.id + ' → ' + s1.id);
  check('карточек не больше трёх', s1.cards <= 3, s1.cards + ' шт.');
  check('текущая одна и на экране', s1.curs === 1 && Math.abs(s1.top) <= 1, 'текущих ' + s1.curs + ', верх ' + s1.top);

  for (let i = 0; i < 8; i++) { await swipe(i % 2 === 0); await page.waitForTimeout(200); }
  await page.waitForTimeout(1500);
  const s2 = await state();
  check('туда-обратно: карточек не больше трёх', s2.cards <= 3, s2.cards + ' шт.');
  check('туда-обратно: текущая на экране', s2.curs === 1 && Math.abs(s2.top) <= 1, 'верх ' + s2.top);

  await page.click('.rl-refresh');
  await page.waitForTimeout(4000);
  const s3 = await state();
  check('обновление включило свежий ролик', s3.id && fresh.includes(s3.id.split(':')[1]), s3.id);
  check('кнопка обновления перестала крутиться', await page.evaluate(() => !document.querySelector('.rl-refresh').classList.contains('is-busy')));
  check('ошибок в странице нет', errors.length === 0, errors.slice(0, 3).join(' | '));

  await browser.close(); srv.close();
  console.log(ok ? 'ВСЁ ПРОШЛО' : 'ЕСТЬ ПРОВАЛЫ');
  process.exit(ok ? 0 : 1);
})().catch((e) => { console.error(e); process.exit(1); });
