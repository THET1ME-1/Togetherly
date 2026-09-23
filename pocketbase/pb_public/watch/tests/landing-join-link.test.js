/* Ссылка на комнату в поле «Код комнаты» на странице /watch/.
 *
 * 23.09.2026: люди вставляют в поле всю ссылку (https://togetherly.day/watch/
 * room/#efvevkve) и получают «Такой комнаты нет» — в журнале 13 отказов с кодом
 * `httpstoge`. Поле обрезало вставку до 12 знаков (maxlength), а разбор брал из
 * остатка все буквы и цифры подряд. Код комнаты живёт после «#».
 *
 * Запуск: node pocketbase/pb_public/watch/tests/landing-join-link.test.js
 */
const { chromium } = require('/home/alelx/.hermes/hermes-agent/node_modules/playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..');           // pb_public
const PORT = 8794;
const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.png': 'image/png', '.woff2': 'font/woff2',
  '.svg': 'image/svg+xml', '.json': 'application/json',
};

function serve() {
  return new Promise((resolve) => {
    const srv = http.createServer((req, res) => {
      let p = decodeURIComponent(req.url.split('?')[0].split('#')[0]);
      if (p.endsWith('/')) p += 'index.html';
      const file = path.join(ROOT, p);
      if (!file.startsWith(ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
        res.writeHead(404); res.end(''); return;
      }
      res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream' });
      res.end(fs.readFileSync(file));
    });
    srv.listen(PORT, '127.0.0.1', () => resolve(srv));
  });
}

let ok = true;
const check = (n, c, x = '') => { console.log((c ? '  ✓ ' : '  ✗ ') + n, x); if (!c) ok = false; };

async function joinWith(browser, pasted) {
  const p = await browser.newPage();
  await p.route('**/room/**', (r) => r.fulfill({ status: 200, body: 'room' }));
  await p.goto(`http://127.0.0.1:${PORT}/watch/`, { waitUntil: 'domcontentloaded' });
  await p.click('#joinCode');
  await p.keyboard.insertText(pasted);           // так вставляет буфер обмена
  await p.click('#join');
  await p.waitForTimeout(600);
  const url = p.url();
  await p.close();
  return url;
}

(async () => {
  const srv = await serve();
  const browser = await chromium.launch();
  try {
    const cases = [
      ['вся ссылка', 'https://togetherly.day/watch/room/#efvevkve', 'efvevkve'],
      ['ссылка с роликом', 'https://togetherly.day/watch/room/?src=https%3A%2F%2Fyoutu.be%2Fx#k2m9pqrs', 'k2m9pqrs'],
      ['ссылка с пробелами', '  togetherly.day/watch/room/#AbCd2345 ', 'abcd2345'],
      ['голый код', 'efvevkve', 'efvevkve'],
      ['код с решёткой', '#efvevkve', 'efvevkve'],
    ];
    for (const [name, pasted, code] of cases) {
      const url = await joinWith(browser, pasted);
      check(name, url.endsWith('/watch/room/#' + code), url);
    }
  } finally {
    await browser.close();
    srv.close();
  }
  console.log(ok ? 'ВСЁ ЗЕЛЁНОЕ' : 'ЕСТЬ ПРОВАЛЫ');
  process.exit(ok ? 0 : 1);
})();
