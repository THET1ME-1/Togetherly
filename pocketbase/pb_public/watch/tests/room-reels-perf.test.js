/* Плавность лент: кадры во время свайпа и долгие задачи.
 *
 * Страница лент на телефонной ширине, процессор замедлен вчетверо (средний
 * Android). Делаем десять свайпов и считаем кадры по requestAnimationFrame:
 * сколько дольше 34 мс (пропуск двух кадров при 60 Гц) и самый долгий.
 * Плюс долгие задачи главного потока (PerformanceObserver longtask).
 *
 * Запуск: node pocketbase/pb_public/watch/tests/room-reels-perf.test.js
 * Порог: не больше 10% тяжёлых кадров и ни одной задачи дольше 250 мс.
 */
const { chromium } = require('/home/alelx/.hermes/hermes-agent/node_modules/playwright');
const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..');
const PORT = 8800;
const PROD = 'https://togetherly.day';
const PAIR = 'r5269c54ac34919';
const THROTTLE = Number(process.env.THROTTLE || 4);

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
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, isMobile: true, userAgent: 'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Mobile Safari/537.36' });
  const page = await ctx.newPage();
  const ids = new Set();
  page.on('response', async (r) => {
    if (!/rutube.ru\/pangolin\/api\/web\/shorts\/lenta/.test(r.url())) return;
    try { for (const m of (await r.text()).matchAll(/"id":"([0-9a-f]{32})"/g)) ids.add(m[1]); } catch (_) {}
  });
  await page.goto('https://rutube.ru/shorts/', { timeout: 60000 }).catch(() => {});
  for (let i = 0; i < 4; i++) { await page.waitForTimeout(3000); await page.keyboard.press('ArrowDown').catch(() => {}); }
  await ctx.close();
  return [...ids];
}

(async () => {
  const [a] = creds();
  const auth = await api('/api/collections/users/auth-with-password', { identity: a.email, password: a.password });
  const room = (await api('/api/watch/room', { groupId: PAIR }, auth.token)).room;
  const srv = await serve();
  const browser = await chromium.launch({ args: ['--autoplay-policy=no-user-gesture-required'] });
  const feed = await harvest(browser);
  console.log('лента Rutube:', feed.length, 'роликов');
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, isMobile: true, hasTouch: true, deviceScaleFactor: 2.75 });
  await ctx.addInitScript(({ token, feed }) => {
    window.__togetherlyAuth = { token, name: 'Аня' };
    window.flutter_inappwebview = { callHandler: async (h, arg) => (h === 'reelsFeed' ? feed.splice(0, (arg && arg.need) || 8) : null) };
    window.__frames = [];
    window.__long = [];
    const tick = (t) => { window.__frames.push(t); requestAnimationFrame(tick); };
    requestAnimationFrame(tick);
    try { new PerformanceObserver((l) => l.getEntries().forEach((e) => window.__long.push(Math.round(e.duration)))).observe({ type: 'longtask', buffered: true }); } catch (_) {}
  }, { token: auth.token, feed });
  const page = await ctx.newPage();
  await page.goto(`http://127.0.0.1:${PORT}/watch/room/?reels=1&feed=rutube&name=A#${room}`);
  await page.waitForTimeout(12000);
  const cdp = await ctx.newCDPSession(page);
  await cdp.send('Emulation.setCPUThrottlingRate', { rate: THROTTLE });
  await page.evaluate(() => { window.__frames = []; window.__long = []; });
  const prof = !!process.env.PROFILE;
  if (prof) { await cdp.send('Profiler.enable'); await cdp.send('Profiler.setSamplingInterval', { interval: 200 }); await cdp.send('Profiler.start'); }
  const touch = async (type, y) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: type === 'touchEnd' ? [] : [{ x: 196, y }] });
  if (process.env.NOBLUR) await page.addStyleTag({ content: '.rl *{-webkit-backdrop-filter:none!important;backdrop-filter:none!important}' });
  for (let i = 0; i < (process.env.IDLE ? 0 : Number(process.env.N || 10)); i++) {
    await page.evaluate(() => (window.__win = window.__win || []).push([performance.now(), 0]));
    await touch('touchStart', 650);
    for (let y = 650; y >= 250; y -= 20) { await touch('touchMove', y); await page.waitForTimeout(8); }
    await page.evaluate(() => (window.__rel = window.__rel || []).push(performance.now()));
    await touch('touchEnd', 250);
    await page.waitForTimeout(400);
    await page.evaluate(() => { const w = window.__win; w[w.length - 1][1] = performance.now(); });
    await page.waitForTimeout(Number(process.env.GAP || 1100));
  }
  if (process.env.IDLE) await page.waitForTimeout(20000);
  if (prof) {
    const { profile } = await cdp.send('Profiler.stop');
    const self = {};
    const dt = profile.timeDeltas; const byId = {}; profile.nodes.forEach((n) => { byId[n.id] = n; });
    profile.samples.forEach((id, i) => { const n = byId[id]; const cf = n.callFrame; const k = (cf.functionName || '(anon)') + ' ' + cf.url.split('/').pop().slice(0, 40) + ':' + cf.lineNumber; self[k] = (self[k] || 0) + (dt[i] || 0) / 1000; });
    Object.entries(self).sort((x, y) => y[1] - x[1]).slice(0, 18).forEach(([k, v]) => console.log('  ' + Math.round(v) + ' мс  ' + k));
  }
  const r = await page.evaluate(() => {
    const f = window.__frames;
    const d = []; for (let i = 1; i < f.length; i++) d.push(f[i] - f[i - 1]);
    d.sort((x, y) => x - y);
    const W = window.__win || []; const inWin = []; for (let i = 1; i < f.length; i++) if (W.some(([a, b]) => f[i] >= a && f[i] <= b)) inWin.push(f[i] - f[i - 1]);
    inWin.sort((x, y) => x - y);
    const REL = window.__rel || []; const rel = []; for (let i = 1; i < f.length; i++) if (REL.some((a) => f[i] >= a && f[i] <= a + 400)) rel.push(f[i] - f[i - 1]);
    return { relFrames: rel.length, relHeavy: rel.filter((x) => x > 34).length, relMax: Math.round(Math.max(0, ...rel)), swipeFrames: inWin.length, swipeHeavy: inWin.filter((x) => x > 34).length, swipeMax: Math.round(inWin[inWin.length - 1] || 0), frames: d.length, heavy: d.filter((x) => x > 34).length, p95: Math.round(d[Math.floor(d.length * 0.95)] || 0), max: Math.round(d[d.length - 1] || 0), long: window.__long, swiped: window.__reelsState().cur && window.__reelsState().cur.id };
  });
  const share = r.frames ? Math.round(100 * r.heavy / r.frames) : 100;
  console.log(`после отпускания (анимация): кадров ${r.relFrames}, тяжёлых ${r.relHeavy} (${r.relFrames ? Math.round(100 * r.relHeavy / r.relFrames) : 0}%), худший ${r.relMax} мс`);
  console.log(`во время свайпа: кадров ${r.swipeFrames}, тяжёлых ${r.swipeHeavy} (${r.swipeFrames ? Math.round(100 * r.swipeHeavy / r.swipeFrames) : 0}%), худший ${r.swipeMax} мс`);
  console.log(`кадров ${r.frames}, тяжёлых ${r.heavy} (${share}%), p95 ${r.p95} мс, худший ${r.max} мс`);
  console.log('долгие задачи, мс:', r.long.length ? r.long.join(', ') : 'нет');
  // Мерило — свайп: что творится в плеерах площадок между свайпами, не наше.
  const ok = r.swipeFrames > 0 && r.swipeHeavy / r.swipeFrames <= 0.1;
  console.log(ok ? 'ПЛАВНО' : 'ЕСТЬ РЫВКИ');
  await browser.close(); srv.close();
  process.exit(ok ? 0 : 1);
})().catch((e) => { console.error(e); process.exit(1); });
