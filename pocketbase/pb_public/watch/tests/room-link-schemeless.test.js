/* Ссылка без «https://» и Rutube Shorts.
 *
 * Жалоба 24.08.2026 (@dorelante): «ссылку вставляем, но видео не включается,
 * даже другие пробовали, и кнопка не нажимается как будто».
 *
 * Два разбора отказывали на живых адресах:
 *  1. Мобильные браузеры давно не показывают схему, и из адресной строки
 *     копируется «youtu.be/xxx». `new URL()` такое не берёт — разбор молча
 *     возвращал null, и человек видел лишь строку статуса под полем.
 *  2. Rutube Shorts (`/shorts/<id>`) — площадка в списке, а путь мимо: ловился
 *     только `/video/<id>`. Rutube даёт 534 включения в неделю, шортсы там на
 *     виду.
 *
 * Запуск: node pocketbase/pb_public/watch/tests/room-link-schemeless.test.js
 * Против прода: node …/room-link-schemeless.test.js https://togetherly.day
 */
const { chromium } = require('/home/alelx/.hermes/hermes-agent/node_modules/playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..');           // pb_public
const ARG = process.argv[2] || '';
const PORT = 8792;

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

const CASES = [
  {
    name: 'youtu.be без схемы',
    typed: 'youtu.be/ZezK8dig-xU',
    embed: /youtube\.com\/embed\/ZezK8dig-xU\b/,
  },
  {
    name: 'www.youtube.com без схемы',
    typed: 'www.youtube.com/watch?v=jNQXAC9IVRw',
    embed: /youtube\.com\/embed\/jNQXAC9IVRw\b/,
  },
  {
    name: 'vkvideo.ru без схемы',
    typed: 'vkvideo.ru/video-217672812_456239413',
    embed: /vk\.com\/video_ext\.php\?oid=-217672812&id=456239413/,
  },
  {
    name: 'Rutube Shorts',
    typed: 'https://rutube.ru/shorts/cd49dba03b95c4030b446156b638d892/',
    embed: /rutube\.ru\/play\/embed\/cd49dba03b95c4030b446156b638d892/,
  },
];

let ok = true;
const check = (n, c, x = '') => { console.log((c ? '  ✓ ' : '  ✗ ') + n, x); if (!c) ok = false; };

(async () => {
  const srv = ARG ? null : await serve();
  const base = (ARG || `http://127.0.0.1:${PORT}`) + '/watch/room/';
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true });

  console.log('1. адрес без схемы и шортсы доходят до плеера');
  for (let i = 0; i < CASES.length; i++) {
    const c = CASES[i];
    const p = await ctx.newPage();
    await p.goto(base + '#bare' + i, { waitUntil: 'domcontentloaded' });
    await p.waitForFunction(() => {
      const el = document.querySelector('#code');
      return !!el && el.textContent.trim().length > 0;
    }, null, { timeout: 15000 });
    await p.waitForTimeout(1200);
    await p.fill('#link', c.typed);
    await p.click('#apply');
    await p.waitForTimeout(1200);

    const frame = await p.getAttribute('#frame', 'src').catch(() => null);
    check(c.name, !!frame && c.embed.test(frame), frame || '(плеер не встал)');
    await p.close();
  }

  console.log('2. отказ объясняет, какие площадки годятся');
  {
    const p = await ctx.newPage();
    await p.goto(base + '#bare-status', { waitUntil: 'domcontentloaded' });
    await p.waitForFunction(() => {
      const el = document.querySelector('#code');
      return !!el && el.textContent.trim().length > 0;
    }, null, { timeout: 15000 });
    await p.waitForTimeout(1200);
    await p.fill('#link', 'https://www.kinopoisk.ru/film/435/');
    await p.click('#apply');
    await p.waitForTimeout(800);

    const status = (await p.textContent('#status')) || '';
    check('   названы площадки', /YouTube/i.test(status) && /Rutube/i.test(status),
      JSON.stringify(status));
    await p.close();
  }

  await browser.close();
  if (srv) srv.close();
  console.log(ok ? '\nВСЁ ХОРОШО' : '\nЕСТЬ ПРОВАЛЫ');
  process.exit(ok ? 0 : 1);
})();
