/* Замер ленты: ролик, который так и не пошёл (обращение 407, 21.10.2026).
 *
 * На iPhone ролики TikTok в совместной ленте стояли обложкой и не запускались,
 * а проверить это на устройстве нечем: WebKit на Linux не играет H.264 вовсе.
 * Поэтому страница сама говорит статистике (Umami), что текущий ролик за 8
 * секунд не пошёл, — с площадкой, системой, сборкой и последним сообщением
 * плеера, — а про первый пошедший за заход говорит, через сколько он пошёл.
 *
 * Плеер TikTok здесь поддельный: номер на …1 стоит и отвечает ошибкой
 * воспроизведения, как WebKit, номер на …2 играет. Скрипт Umami подменён
 * сборщиком событий. Вход — тестовая пара (~/keys/togetherly-test-pair.txt),
 * страницы — локальная копия pb_public, /api уходит на прод.
 *
 * Запуск: node pocketbase/pb_public/watch/tests/reels-stuck-probe.test.js
 */
const { chromium } = require('/home/alelx/.hermes/hermes-agent/node_modules/playwright');
const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..');
const PORT = 8802;
const PROD = 'https://togetherly.day';
const PAIR = 'r5269c54ac34919';
const IPHONE = { viewport: { width: 393, height: 852 }, isMobile: true, hasTouch: true, locale: 'ru-RU',
  userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148' };

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
      if (!file.startsWith(ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); res.end(); return; }
      const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.woff2': 'font/woff2', '.webp': 'image/webp' };
      res.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream' });
      res.end(fs.readFileSync(file));
    });
    srv.listen(PORT, '127.0.0.1', () => resolve(srv));
  });
}

/** Поддельный плеер TikTok: …1 стоит и падает, как в WebKit, …2 играет. */
const FAKE_PLAYER = (id) => `<!doctype html><body style="background:#222"><script>
const say = (m) => parent.postMessage(Object.assign({ 'x-tiktok-player': true }, m), '*');
say({ type: 'onPlayerReady' });
if (${JSON.stringify(id)}.endsWith('1')) {
  say({ type: 'onStateChange', value: 3 });
  setTimeout(() => say({ type: 'onPlayerError', value: { errorCode: 3001, errorType: 'PLAYBACK_ERROR' } }), 1500);
} else {
  setTimeout(() => say({ type: 'onStateChange', value: 1 }), 600);
}
</script>`;

let ok = true;
const check = (n, c, x = '') => { console.log((c ? '  ✓ ' : '  ✗ ') + n, x); if (!c) ok = false; };

(async () => {
  const [a] = creds();
  const auth = await api('/api/collections/users/auth-with-password', { identity: a.email, password: a.password });
  const room = (await api('/api/watch/room', { groupId: PAIR }, auth.token)).room;
  const srv = await serve();
  const browser = await chromium.launch();
  const ctx = await browser.newContext(IPHONE);
  const feed = ['tiktok:7000000000000000001', 'tiktok:7000000000000000002', 'tiktok:7000000000000000012', 'tiktok:7000000000000000022'];
  await ctx.addInitScript(({ token, feed }) => {
    window.__togetherlyAuth = { token, name: 'Аня' };
    window.flutter_inappwebview = { callHandler: async (h, arg) => (h === 'reelsFeed' ? feed.splice(0, (arg && arg.need) || 8) : null) };
  }, { token: auth.token, feed });
  await ctx.route('https://www.tiktok.com/player/v1/**', (r) => {
    const id = new URL(r.request().url()).pathname.split('/').pop();
    r.fulfill({ status: 200, contentType: 'text/html', body: FAKE_PLAYER(id) });
  });
  // Проверка связи из замера: TikTok отвечает, YouTube молчит.
  await ctx.route('https://www.tiktok.com/favicon.ico**', (r) => r.fulfill({ status: 200, body: '' }));
  await ctx.route('https://www.youtube.com/favicon.ico**', (r) => r.abort('connectionrefused'));
  await ctx.route('https://analytics.togetherly.day/**', (r) => r.fulfill({
    status: 200, contentType: 'text/javascript',
    body: 'window.umami = { track: (n, d) => { (window.__tracked = window.__tracked || []).push([n, d]); } };',
  }));
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('  [ошибка страницы]', e.message));
  await page.goto(`http://127.0.0.1:${PORT}/watch/reels/?feed=tiktok&name=${encodeURIComponent('Аня')}&b=255#${room}`);

  const tracked = () => page.evaluate(() => window.__tracked || []);
  await page.waitForTimeout(14000);
  let t = await tracked();
  const stuck = t.filter(([n]) => n === 'reels-stuck');
  check('ролик, который не пошёл, отмечен', stuck.length === 1, JSON.stringify(stuck));
  const s = (stuck[0] || [])[1] || {};
  check('в отметке площадка, система и сборка', s.src === 'tiktok' && s.platform === 'ios' && s.os === 17 && s.b === 255, JSON.stringify(s));
  check('в отметке ошибка плеера', String(s.last || '').includes('3001'), s.last);
  // На iPhone 21.10.2026 плееры не загрузились вовсе (ready 0, ни одного
  // сообщения). Отметка различает сеть и браузер: есть ли на странице сам
  // плеер, доехал ли скрипт YouTube, отвечают ли площадки.
  check('в отметке есть ли плеер на странице', s.frame === 1, String(s.frame));
  check('в отметке связь с TikTok', s.tt === 'ok', String(s.tt));
  check('в отметке связь с YouTube', s.yt === 'fail', String(s.yt));
  check('в отметке доехал ли скрипт YouTube', s.ytApi === 0, String(s.ytApi));

  const before = await page.evaluate(() => window.__reelsState().cur && window.__reelsState().cur.id);
  await page.mouse.move(196, 600); await page.mouse.down();
  await page.mouse.move(196, 250, { steps: 8 }); await page.mouse.up();
  await page.waitForTimeout(12000);
  const after = await page.evaluate(() => window.__reelsState().cur && window.__reelsState().cur.id);
  check('свайп перелистнул на играющий ролик', before !== after && String(after).endsWith('2'), before + ' → ' + after);
  t = await tracked();
  const live = t.filter(([n]) => n === 'reels-live');
  check('пошедший ролик отмечен один раз, с задержкой старта', live.length === 1 && live[0][1].ms >= 0, JSON.stringify(live));
  check('пошедший ролик не отмечен как стоящий', t.filter(([n]) => n === 'reels-stuck').length === 1, JSON.stringify(t.map(([n]) => n)));

  await browser.close();
  srv.close();
  console.log(ok ? '\nвсё прошло' : '\nЕСТЬ ПАДЕНИЯ');
  process.exit(ok ? 0 : 1);
})();
