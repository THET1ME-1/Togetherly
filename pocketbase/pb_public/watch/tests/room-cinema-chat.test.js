/* Чат в полноэкранном режиме комнаты не лежит на кадре.
 *
 * Жалоба 06.10.2026, повторная: «когда полноэкранный режим открываешь на
 * телефоне, строка для ввода и отправки сообщения залезает на само видео и не
 * убирается». Режим «кино» клал переписку и поле поверх нижней половины кадра
 * насовсем, а кнопка, убиравшая чат, пряталась прозрачной в верхней полосе
 * плеера.
 *
 * Теперь в «кино» кадр чистый: чат свёрнут в круглую кнопку справа внизу,
 * пришедшее сообщение всплывает на пять секунд и считается на кнопке.
 * Кнопка открывает чат, а без касаний и пустом поле он сворачивается сам.
 *
 * Две вкладки тестовой пары (~/keys/togetherly-test-pair.txt), страницы —
 * локальная копия pb_public, /api уходит на прод.
 *
 * Запуск: node pocketbase/pb_public/watch/tests/room-cinema-chat.test.js
 */
const { chromium } = require('/home/alelx/.hermes/hermes-agent/node_modules/playwright');
const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..');
const PORT = 8796;
const PROD = 'https://togetherly.day';
const PAIR = 'r5269c54ac34919';
const BASE = `http://127.0.0.1:${PORT}`;
const SHOTS = process.env.SHOTS || '';

function creds() {
  const t = fs.readFileSync(path.join(process.env.HOME, 'keys/togetherly-test-pair.txt'), 'utf8');
  return [...t.matchAll(/(claude-test-231[ab]@togetherly\.day) \/ (\S+)/g)].map((x) => ({ email: x[1], password: x[2] }));
}

const api = (p, body, token) => fetch(PROD + p, {
  method: 'POST',
  headers: Object.assign({ 'Content-Type': 'application/json' }, token ? { Authorization: token } : {}),
  body: JSON.stringify(body),
}).then((r) => r.json());

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
      const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.woff2': 'font/woff2', '.webp': 'image/webp', '.svg': 'image/svg+xml' };
      res.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream' });
      res.end(fs.readFileSync(file));
    });
    srv.listen(PORT, '127.0.0.1', () => resolve(srv));
  });
}

let ok = true;
const check = (n, c, x = '') => { console.log((c ? '  ✓ ' : '  ✗ ') + n, x); if (!c) ok = false; };

/** Прямоугольник видимого элемента или null. */
function box(sel) {
  const e = document.querySelector(sel);
  if (!e) return null;
  const s = getComputedStyle(e);
  if (s.display === 'none' || s.visibility === 'hidden') return null;
  for (let p = e; p; p = p.parentElement) if (p.hidden) return null;
  const r = e.getBoundingClientRect();
  if (r.width < 1 || r.height < 1) return null;
  return { l: r.left, t: r.top, r: r.right, b: r.bottom, w: r.width, h: r.height, bg: s.backgroundColor };
}

(async () => {
  const [a, b] = creds();
  const authA = await api('/api/collections/users/auth-with-password', { identity: a.email, password: a.password });
  const authB = await api('/api/collections/users/auth-with-password', { identity: b.email, password: b.password });
  const room = (await api('/api/watch/room', { groupId: PAIR }, authA.token)).room;
  check('код комнаты пары', !!room, room);

  const srv = await serve();
  const browser = await chromium.launch({ args: ['--autoplay-policy=no-user-gesture-required'] });
  const errors = [];
  const src = encodeURIComponent('https://youtu.be/dQw4w9WgXcQ');

  const tab = async (auth, name, W, H) => {
    const ctx = await browser.newContext({ viewport: { width: W, height: H }, locale: 'ru-RU', isMobile: W < 1000, hasTouch: true });
    await ctx.addInitScript(({ token, name }) => {
      window.__togetherlyAuth = { token, name };
      window.flutter_inappwebview = { callHandler: async () => [] };
      try { localStorage.removeItem('togetherly.watch.chatOff'); } catch (_) {}
    }, { token: auth.token, name });
    const page = await ctx.newPage();
    page.on('pageerror', (e) => errors.push(name + ': ' + e.message));
    await page.goto(`${BASE}/watch/room/?name=${encodeURIComponent(name)}&src=${src}#${room}`);
    await page.waitForTimeout(6000);
    return page;
  };

  // Партнёр сидит в комнате и пишет.
  const partner = await tab(authB, 'Боря', 393, 852);
  const say = async (text) => {
    await partner.fill('#message', text);
    await partner.click('#send');
  };

  for (const [label, W, H] of [['телефон стоя', 393, 852], ['телефон лёжа', 852, 393]]) {
    console.log(`\n${label} ${W}×${H}`);
    const page = await tab(authA, 'Аня', W, H);
    const shot = async (n) => { if (SHOTS) await page.screenshot({ path: path.join(SHOTS, `${W}x${H}-${n}.png`) }); };

    await page.click('#cinema');
    await page.waitForTimeout(700);
    await shot('cinema');
    check('включился полноэкранный режим', await page.evaluate(() => document.body.classList.contains('cinema')));
    check('строки ввода на кадре нет', !(await page.evaluate(box, '.composer')));
    check('переписки на кадре нет', !(await page.evaluate(box, '.side')));
    const fab = await page.evaluate(box, '#cinChat');
    check('кнопка чата на экране', !!fab && fab.r <= W && fab.b <= H && fab.w >= 44, fab ? `${Math.round(fab.w)} у ${Math.round(fab.l)},${Math.round(fab.t)}` : 'нет');
    const exit = await page.evaluate(box, '#cinema');
    check('кнопка выхода видна на кадре: у неё есть подложка', !!exit && !/rgba\(0, 0, 0, 0\)|transparent/.test(exit.bg), exit ? exit.bg : 'нет');

    // Сообщение партнёра всплывает и считается.
    await say(`привет ${W}`);
    await page.waitForTimeout(1200);
    await shot('toast');
    const toast = await page.evaluate(box, '#cinToast');
    const toastText = await page.evaluate(() => (document.querySelector('#cinToast') || {}).textContent || '');
    check('пришедшее сообщение всплыло', !!toast && toastText.includes(`привет ${W}`), toastText.trim());
    check('на кнопке счётчик 1', (await page.evaluate(() => (document.querySelector('#cinChat .cin-fab__n') || {}).textContent)) === '1');
    check('строка ввода по-прежнему не на кадре', !(await page.evaluate(box, '.composer')));
    await page.waitForTimeout(5500);
    check('всплывшее ушло само', !(await page.evaluate(box, '#cinToast')));

    // Кнопка открывает чат.
    await page.click('#cinChat');
    await page.waitForTimeout(500);
    await shot('open');
    check('чат открылся: строка ввода есть', !!(await page.evaluate(box, '.composer')));
    check('и переписка с новым сообщением', (await page.evaluate(() => document.querySelector('#chat').textContent)).includes(`привет ${W}`));
    check('счётчик сброшен', !(await page.evaluate(box, '#cinChat .cin-fab__n')));

    // Пока печатают, не сворачивается.
    await page.click('#message');
    await page.keyboard.type('пишу');
    await page.waitForTimeout(7500);
    check('пока поле в фокусе и не пусто — чат открыт', !!(await page.evaluate(box, '.composer')));
    await page.click('#send');
    await page.evaluate(() => document.activeElement.blur());

    // Без касаний сворачивается сам.
    await page.waitForTimeout(7500);
    await shot('closed');
    check('без касаний свернулся сам', !(await page.evaluate(box, '.composer')) && !!(await page.evaluate(box, '#cinChat')));

    // Выход из «кино» возвращает обычную комнату.
    await page.click('#cinema');
    await page.waitForTimeout(500);
    check('после выхода строка ввода на месте', !!(await page.evaluate(box, '.composer')));
    check('кнопки чата из «кино» больше нет', !(await page.evaluate(box, '#cinChat')));
    await page.context().close();
  }

  check('страницы без ошибок', errors.length === 0, errors.join(' | '));
  await browser.close();
  srv.close();
  console.log(ok ? '\nВСЁ ПРОШЛО' : '\nЕСТЬ ПРОВАЛЫ');
  process.exit(ok ? 0 : 1);
})().catch((e) => { console.error(e); process.exit(1); });
