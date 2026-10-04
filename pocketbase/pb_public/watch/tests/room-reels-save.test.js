/* Совместная лента: закладка «в воспоминания» и ссылка «Отправить».
 *
 * Пара на ленте Rutube, мост приложения подменён: он записывает вызовы и
 * отвечает, как настоящий. Проверяем: кнопка стоит в столбике и не налезает
 * на звонок, касание отдаёт приложению ключ ролика, закладка загорается у
 * обоих и партнёру приходит плашка, повтор не заводит вторую запись, на
 * следующем ролике закладка пустая, отказ приложения виден, а «Отправить»
 * шлёт ссылку Rutube, а не YouTube.
 *
 * Запуск: node pocketbase/pb_public/watch/tests/room-reels-save.test.js
 * Снимки: build/reels/save-*.png
 */
const { chromium } = require('/home/alelx/.hermes/hermes-agent/node_modules/playwright');
const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..');
const PORT = 8802;
const PROD = 'https://togetherly.day';
const OUT = path.join(__dirname, '..', '..', '..', '..', 'build', 'reels');
const PAIR = 'r5269c54ac34919';
const MOBILE = { viewport: { width: 393, height: 852 }, isMobile: true, hasTouch: true, locale: 'ru-RU',
  userAgent: 'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Mobile Safari/537.36' };

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

async function harvest(browser) {
  const ctx = await browser.newContext(MOBILE);
  const page = await ctx.newPage();
  const ids = new Set();
  page.on('response', async (r) => {
    if (!/shorts\/lenta/.test(r.url())) return;
    try { for (const m of (await r.text()).matchAll(/"id":"([0-9a-f]{32})"/g)) ids.add(m[1]); } catch (_) {}
  });
  await page.goto('https://rutube.ru/shorts/', { timeout: 60000 }).catch(() => {});
  for (let i = 0; i < 6 && ids.size < 16; i++) { await page.waitForTimeout(2500); await page.keyboard.press('ArrowDown').catch(() => {}); }
  await ctx.close();
  return [...ids];
}

let ok = true;
const check = (n, c, x = '') => { console.log((c ? '  ✓ ' : '  ✗ ') + n, x); if (!c) ok = false; };

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const [a, b] = creds();
  const authA = await api('/api/collections/users/auth-with-password', { identity: a.email, password: a.password });
  const authB = await api('/api/collections/users/auth-with-password', { identity: b.email, password: b.password });
  const room = (await api('/api/watch/room', { groupId: PAIR }, authA.token)).room;
  const srv = await serve();
  const browser = await chromium.launch({ args: ['--autoplay-policy=no-user-gesture-required'] });
  const ids = await harvest(browser);
  check('лента собрана', ids.length >= 8, ids.length + ' роликов');
  const errors = [];

  const open = async (auth, name, feed) => {
    const ctx = await browser.newContext(MOBILE);
    await ctx.addInitScript(({ token, name, feed }) => {
      window.__togetherlyAuth = { token, name };
      window.__calls = [];
      window.__saveAnswer = { ok: true };
      window.flutter_inappwebview = { callHandler: async (h, arg) => {
        window.__calls.push([h, arg]);
        if (h === 'reelsFeed') return feed.splice(0, (arg && arg.need) || 8);
        if (h === 'reelsSave') { await new Promise((r) => setTimeout(r, 300)); return window.__saveAnswer; }
        return null;
      } };
    }, { token: auth.token, name, feed });
    const page = await ctx.newPage();
    page.on('pageerror', (e) => errors.push(name + ': ' + e.message));
    await page.goto(`http://127.0.0.1:${PORT}/watch/room/?reels=1&feed=rutube&name=${encodeURIComponent(name)}#${room}`);
    return { page, ctx };
  };
  const half = Math.floor(ids.length / 2);
  const A = await open(authA, 'Аня', ids.slice(0, half));
  await A.page.waitForTimeout(3000);
  const B = await open(authB, 'Боря', ids.slice(half));
  await A.page.waitForTimeout(9000);

  const st = (p) => p.evaluate(() => {
    const s = document.querySelector('.rl-save');
    const t = document.querySelector('.rl-toast');
    return {
      cur: window.__reelsState().cur && window.__reelsState().cur.id,
      on: s.classList.contains('is-on'), label: s.getAttribute('aria-label'),
      toast: t ? t.textContent : '', saves: window.__calls.filter((c) => c[0] === 'reelsSave').map((c) => c[1].key),
      share: window.__calls.filter((c) => c[0] === 'reelsShare').map((c) => c[1].url),
    };
  });
  const box = (p, sel) => p.evaluate((s) => { const r = document.querySelector(s).getBoundingClientRect(); return { top: r.top, bottom: r.bottom, left: r.left, right: r.right, h: r.height }; }, sel);

  const s0 = await st(A.page), b0 = await st(B.page);
  check('у обоих один ролик', s0.cur && s0.cur === b0.cur, s0.cur + ' / ' + b0.cur);
  check('закладка пустая', !s0.on && s0.label === 'Сохранить в воспоминания');
  const rail = await box(A.page, '.rl-rail');
  const voice = await box(A.page, '.rl-voice');
  const compose = await box(A.page, '.rl-compose');
  check('столбик из пяти кнопок на экране', rail.top > 0 && rail.bottom < 852 && rail.h > 230, JSON.stringify(rail));
  check('столбик не налезает на звонок', rail.top >= voice.bottom || voice.top === 0 && voice.bottom === 0, 'верх ' + Math.round(rail.top) + ', низ звонка ' + Math.round(voice.bottom));
  check('столбик над полем сообщения', rail.bottom <= compose.top, Math.round(rail.bottom) + ' / ' + Math.round(compose.top));

  await A.page.click('.rl-save');
  await A.page.waitForTimeout(800);
  const s1 = await st(A.page);
  check('приложению ушёл ключ ролика', s1.saves.length === 1 && s1.saves[0] === s0.cur, s1.saves.join(', '));
  check('закладка загорелась', s1.on && s1.label === 'Ролик в воспоминаниях');
  check('плашка «в воспоминаниях»', s1.toast.includes('Ролик в воспоминаниях'), s1.toast);
  await A.page.screenshot({ path: path.join(OUT, 'save-a.png') });
  await B.page.waitForTimeout(1500);
  const b1 = await st(B.page);
  check('у партнёра закладка горит', b1.on);
  check('партнёру плашка с именем', b1.toast.includes('Аня сохраняет ролик'), b1.toast);
  check('партнёр сам ничего не сохранял', b1.saves.length === 0);
  await B.page.screenshot({ path: path.join(OUT, 'save-b.png') });

  await A.page.waitForTimeout(3000);
  await A.page.click('.rl-save');
  await A.page.waitForTimeout(600);
  const s2 = await st(A.page);
  check('повтор не заводит вторую запись', s2.saves.length === 1, s2.saves.length + ' вызова');

  await A.page.click('.rl-share');
  await A.page.waitForTimeout(300);
  const s3 = await st(A.page);
  const rid = s0.cur.split(':')[1];
  check('«Отправить» шлёт ссылку Rutube', s3.share[0] === 'https://rutube.ru/shorts/' + rid + '/', s3.share[0]);

  await A.page.mouse.move(196, 600); await A.page.mouse.down();
  await A.page.mouse.move(196, 250, { steps: 8 }); await A.page.mouse.up();
  await A.page.waitForTimeout(2500);
  const s4 = await st(A.page);
  check('на следующем ролике закладка пустая', s4.cur !== s0.cur && !s4.on, s4.cur);

  await A.page.evaluate(() => { window.__saveAnswer = { ok: false }; });
  await A.page.click('.rl-save');
  await A.page.waitForTimeout(800);
  const s5 = await st(A.page);
  check('отказ приложения виден', !s5.on && s5.toast.includes('Не сохранилось'), s5.toast);

  await A.page.mouse.move(196, 250); await A.page.mouse.down();
  await A.page.mouse.move(196, 600, { steps: 8 }); await A.page.mouse.up();
  await A.page.waitForTimeout(2500);
  const s6 = await st(A.page);
  check('назад к сохранённому — закладка снова горит', s6.cur === s0.cur && s6.on, s6.cur);

  check('ошибок в странице нет', errors.length === 0, errors.slice(0, 3).join(' | '));
  await browser.close(); srv.close();
  console.log(ok ? 'ВСЁ ПРОШЛО' : 'ЕСТЬ ПРОВАЛЫ');
  process.exit(ok ? 0 : 1);
})().catch((e) => { console.error(e); process.exit(1); });
