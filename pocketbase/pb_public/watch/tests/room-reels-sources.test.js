/* Ленты вдвоём на всех площадках: TikTok, Rutube, ВК Клипы, Дзен.
 *
 * Для каждой площадки собираем настоящую ленту теми же правилами разбора,
 * что у скрытого браузера приложения (`ReelsFeed.script`), открываем ленты с
 * `?feed=<площадка>`, подменяя мост приложения, и смотрим, что встал плеер
 * этой площадки, а свайп листает. Под конец пара со смешанными лентами: у Ани
 * TikTok, у Бори Rutube — ролики друг друга у обоих играют своим плеером.
 *
 * Запуск: node pocketbase/pb_public/watch/tests/room-reels-sources.test.js [площадка]
 * Снимки: build/reels/src-*.png
 */
const { chromium } = require('/home/alelx/.hermes/hermes-agent/node_modules/playwright');
const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..');
const PORT = 8799;
const PROD = 'https://togetherly.day';
const OUT = path.join(__dirname, '..', '..', '..', '..', 'build', 'reels');
const PAIR = 'r5269c54ac34919';
const ONLY = process.argv[2] || '';

const MOBILE = { viewport: { width: 393, height: 852 }, isMobile: true, hasTouch: true, locale: 'ru-RU',
  userAgent: 'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Mobile Safari/537.36' };
const DESKTOP = { viewport: { width: 1280, height: 900 }, locale: 'ru-RU',
  userAgent: 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36' };

const all = (t, re, map) => { const out = []; let m; while ((m = re.exec(t))) out.push(map ? map(m) : m[1]); return out; };
/** Те же правила, что в `ReelsFeed.script` (lib/services/reels/reels_feed.dart). */
const SOURCES = {
  tiktok: { home: 'https://www.tiktok.com/foryou', ctx: DESKTOP, url: /api\/(recommend|preload)\/item_list/,
    pick: (t) => { try { return (JSON.parse(t).itemList || []).map((i) => String(i.id)); } catch (_) { return []; } }, host: 'tiktok.com' },
  rutube: { home: 'https://rutube.ru/shorts/', ctx: MOBILE, url: /shorts\/lenta/, pick: (t) => all(t, /"id":"([0-9a-f]{32})"/g), host: 'rutube.ru' },
  vk: { home: 'https://m.vk.com/clips', ctx: MOBILE, url: /shortVideo\.getRecom/, html: true,
    pick: (t) => all(t, /video_ext\.php\?oid=(-?\d+)&(?:amp;)?id=(\d+)&(?:amp;)?hash=([0-9a-f]+)/g, (m) => m[1] + '_' + m[2] + '_' + m[3]), host: 'vk.com' },
  dzen: { home: 'https://dzen.ru/shorts', ctx: MOBILE, url: /video-recommend/, html: true, pick: (t) => all(t, /"videoContentId":"([A-Za-z0-9_-]{6,})"/g), host: 'dzen.ru' },
};

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

async function harvest(browser, s) {
  const ctx = await browser.newContext(s.ctx);
  const page = await ctx.newPage();
  const ids = new Set();
  page.on('response', async (r) => {
    if (!s.url.test(r.url())) return;
    try { s.pick(await r.text()).forEach((i) => ids.add(i)); } catch (_) {}
  });
  await page.goto(s.home, { timeout: 60000 }).catch(() => {});
  await page.waitForTimeout(9000);
  if (s.html) s.pick(await page.content()).forEach((i) => ids.add(i));
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
  const feeds = {};

  const open = async (auth, name, src, feed) => {
    const ctx = await browser.newContext(MOBILE);
    await ctx.addInitScript(({ token, name, feed }) => {
      window.__togetherlyAuth = { token, name };
      window.flutter_inappwebview = { callHandler: async (h, arg) => (h === 'reelsFeed' ? feed.splice(0, (arg && arg.need) || 8) : null) };
    }, { token: auth.token, name, feed: feed.slice() });
    const page = await ctx.newPage();
    page.on('pageerror', (e) => console.log('  [ошибка ' + name + ']', e.message));
    await page.goto(`http://127.0.0.1:${PORT}/watch/reels/?feed=${src}&name=${encodeURIComponent(name)}#${room}`);
    return { page, ctx };
  };
  const curFrame = (page) => page.evaluate(() => {
    const st = window.__reelsState();
    const c = document.querySelector('.rl-card.is-cur iframe');
    return { key: st.cur && st.cur.id, src: c ? c.src : '', chip: document.querySelector('.rl-src').textContent };
  });

  for (const [name, s] of Object.entries(SOURCES)) {
    if (ONLY && ONLY !== name && ONLY !== 'mix') continue;
    console.log('== ' + name);
    feeds[name] = await harvest(browser, s);
    check('лента собрана', feeds[name].length >= 3, feeds[name].length + ' номеров: ' + feeds[name].slice(0, 2).join(', '));
    if (ONLY === 'mix') continue;
    if (feeds[name].length < 2) continue;
    const { page, ctx } = await open(authA, 'Аня', name, feeds[name]);
    await page.waitForTimeout(10000);
    const f1 = await curFrame(page);
    check('играет плеер площадки', f1.src.includes(s.host) && f1.key.startsWith(name + ':'), f1.key + ' ← ' + f1.src.slice(0, 70));
    check('в плашке площадка', f1.chip.length > 0, f1.chip);
    await page.screenshot({ path: path.join(OUT, `src-${name}-1.png`) });
    await page.mouse.move(196, 600); await page.mouse.down();
    await page.mouse.move(196, 250, { steps: 8 }); await page.mouse.up();
    await page.waitForTimeout(6000);
    const f2 = await curFrame(page);
    check('свайп листает', f2.key && f2.key !== f1.key, f1.key + ' → ' + f2.key);
    await page.screenshot({ path: path.join(OUT, `src-${name}-2.png`) });
    await ctx.close();
  }

  // Пара со смешанными лентами: у Ани TikTok, у Бори Rutube.
  if (!ONLY || ONLY === 'mix') {
    console.log('== смешанные ленты');
    if (feeds.tiktok && feeds.rutube && feeds.tiktok.length > 2 && feeds.rutube.length > 2) {
      const A = await open(authA, 'Аня', 'tiktok', feeds.tiktok);
      await A.page.waitForTimeout(4000);
      const B = await open(authB, 'Боря', 'rutube', feeds.rutube);
      await A.page.waitForTimeout(8000);
      const swipe = async (p) => { await p.mouse.move(196, 600); await p.mouse.down(); await p.mouse.move(196, 250, { steps: 8 }); await p.mouse.up(); };
      const keys = [];
      for (let i = 0; i < 2; i++) {
        await swipe(A.page);
        await A.page.waitForTimeout(5000);
        const fa = await curFrame(A.page), fb = await curFrame(B.page);
        keys.push(fa.key);
        check(`свайп ${i + 1}: у обоих один ролик`, fa.key === fb.key, fa.key + ' / ' + fb.key);
        check(`свайп ${i + 1}: у Бори свой плеер под ролик`, fb.src.includes(fa.key.startsWith('tiktok:') ? 'tiktok.com' : 'rutube.ru'), fb.src.slice(0, 60));
        await B.page.screenshot({ path: path.join(OUT, `src-mix-${i + 1}.png`) });
      }
      check('в паре идут ролики обеих лент', keys.some((k) => k.startsWith('tiktok:')) && keys.some((k) => k.startsWith('rutube:')), keys.join(', '));
      await A.ctx.close(); await B.ctx.close();
    }
  }

  await browser.close();
  srv.close();
  console.log(ok ? 'ВСЁ ПРОШЛО' : 'ЕСТЬ ПРОВАЛЫ');
  process.exit(ok ? 0 : 1);
})().catch((e) => { console.error(e); process.exit(1); });
