/* Замер «касания не доходят» в комнате (обращения 164, 178, 183, 190).
 *
 * Во встроенном браузере приложения страница шлёт в статистику room-touch при
 * первом касании или room-no-touch, если за 45 секунд касаний не было. В
 * обычном браузере — ничего.
 *
 * Запуск: node pocketbase/pb_public/watch/tests/room-touch-probe.test.js
 */
const { chromium } = require('/home/alelx/.hermes/hermes-agent/node_modules/playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..');           // pb_public
const ARG = process.argv[2] || '';
const PORT = 8795;

const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.png': 'image/png', '.jpg': 'image/jpeg',
  '.woff2': 'font/woff2', '.svg': 'image/svg+xml', '.json': 'application/json',
};

function serve() {
  return new Promise((resolve) => {
    const srv = http.createServer((req, res) => {
      let p = decodeURIComponent(req.url.split('?')[0].split('#')[0]);
      if (p.endsWith('/')) p += 'index.html';
      const file = path.join(ROOT, p);
      if (!file.startsWith(ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
        res.writeHead(404); res.end('нет файла'); return;
      }
      res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream' });
      res.end(fs.readFileSync(file));
    });
    srv.listen(PORT, '127.0.0.1', () => resolve(srv));
  });
}

let ok = true;
const check = (n, c, x = '') => { console.log((c ? '  ✓ ' : '  ✗ ') + n, x); if (!c) ok = false; };


// Страница думает, что она во встроенном браузере приложения, а статистика —
// заглушка, которая копит события. Таймер 45 с ускоряется подменой setTimeout.
const STUB = `
  window.flutter_inappwebview = { callHandler: () => Promise.resolve(null) };
  window.__events = [];
  Object.defineProperty(window, 'umami', { value: { track: (n, d) => window.__events.push([n, d]) }, writable: false });
  const realTimeout = window.setTimeout;
  window.setTimeout = (fn, ms, ...a) => realTimeout(fn, ms === 45000 ? 300 : ms, ...a);
`;

async function open(ctx, tag) {
  const p = await ctx.newPage();
  await p.addInitScript(STUB);
  await p.goto(`http://127.0.0.1:${PORT}/watch/room/#${tag}`, { waitUntil: 'domcontentloaded' });
  await p.waitForFunction(() => {
    const el = document.querySelector('#code');
    return !!el && el.textContent.trim().length > 0;
  }, null, { timeout: 15000 });
  return p;
}

(async () => {
  const srv = await serve();
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
  try {
    console.log('1. касание дошло — одно событие room-touch');
    {
      const p = await open(ctx, 'probe-touch');
      await p.tap('#link');
      await p.waitForTimeout(700);
      const ev = await p.evaluate(() => window.__events);
      const names = ev.map((e) => e[0]).filter((n) => n.startsWith('room-'));
      check('room-touch ровно один', names.length === 1 && names[0] === 'room-touch', JSON.stringify(ev));
      await p.close();
    }
    console.log('2. касаний нет — room-no-touch');
    {
      const p = await open(ctx, 'probe-silent');
      await p.waitForTimeout(900);
      const ev = await p.evaluate(() => window.__events);
      const names = ev.map((e) => e[0]).filter((n) => n.startsWith('room-'));
      check('room-no-touch ровно один', names.length === 1 && names[0] === 'room-no-touch', JSON.stringify(ev));
      await p.close();
    }
    console.log('3. в обычном браузере замера нет');
    {
      const p = await ctx.newPage();
      await p.addInitScript(`window.__events = []; window.umami = { track: (n, d) => window.__events.push([n, d]) };`);
      await p.goto(`http://127.0.0.1:${PORT}/watch/room/#probe-web`, { waitUntil: 'domcontentloaded' });
      await p.waitForTimeout(1500);
      await p.tap('body').catch(() => {});
      await p.waitForTimeout(500);
      const ev = await p.evaluate(() => window.__events.filter((e) => e[0].startsWith('room-')));
      check('событий нет', ev.length === 0, JSON.stringify(ev));
      await p.close();
    }
  } finally {
    await browser.close();
    srv.close();
  }
  console.log(ok ? 'ВСЁ ХОРОШО' : 'ЕСТЬ ПРОВАЛЫ');
  process.exit(ok ? 0 : 1);
})();
