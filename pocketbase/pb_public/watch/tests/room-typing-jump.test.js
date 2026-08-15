/* Нижний ряд не должен прыгать от фокуса.
 *
 * Класс `typing` ужимает кадр, чтобы на iPhone строка ввода не пряталась под
 * клавиатурой. До 15 августа 2026 его вешал сам фокус — и на любом экране, где
 * клавиатура не выезжает (весь десктоп), страница подпрыгивала: кадр ужимался
 * до 28% высоты, нижний ряд уезжал вверх на 166 px, и нажатие приходилось в
 * пустоту. Со стороны это выглядело так, что кнопки мертвы: «ролик не
 * включается», «сообщение не отправляется», «не работает интерфейс во время
 * совместного просмотра» (жалобы 15 августа).
 *
 * Теперь класс ставится по факту сжатия вьюпорта, а не по фокусу.
 *
 * Запуск: node pocketbase/pb_public/watch/tests/room-typing-jump.test.js
 * Против прода: node …/room-typing-jump.test.js https://togetherly.day
 */
const { chromium } = require('/home/alelx/.hermes/hermes-agent/node_modules/playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..');           // pb_public
const ARG = process.argv[2] || '';
const PORT = 8792;
const ROOM = 'jumpprobe';
const VIDEO = 'https://youtu.be/A_rDJ-ckxqA';

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

(async () => {
  const srv = ARG ? null : await serve();
  const base = ARG || `http://127.0.0.1:${PORT}`;
  const browser = await chromium.launch();
  const page = await (await browser.newContext({ viewport: { width: 1440, height: 900 } })).newPage();

  let ok = true;
  const check = (name, cond, extra = '') => {
    console.log((cond ? '  ✓ ' : '  ✗ ') + name, extra);
    if (!cond) ok = false;
  };
  const boxOf = async (sel) => (await page.locator(sel).boundingBox()) || { y: -1 };

  await page.goto(`${base}/watch/room/#${ROOM}`, { waitUntil: 'load' });
  await page.waitForTimeout(1500);

  console.log('1. фокус в поле ссылки не двигает нижний ряд');
  const applyBefore = (await boxOf('#apply')).y;
  await page.click('#link');
  await page.waitForTimeout(600);
  const applyAfter = (await boxOf('#apply')).y;
  check('кнопка «Включить» осталась на месте', Math.abs(applyAfter - applyBefore) < 4,
    `было ${applyBefore}, стало ${applyAfter}`);
  check('класс typing не появился без клавиатуры',
    !(await page.evaluate(() => document.body.classList.contains('typing'))));

  console.log('2. нажатие после ввода доходит до кнопки');
  await page.keyboard.type(VIDEO);
  await page.click('#apply');
  await page.waitForTimeout(2500);
  check('ролик встал в плеер', await page.locator('#player iframe').count() === 1);

  console.log('3. то же в строке сообщения');
  const sendBefore = (await boxOf('#send')).y;
  await page.click('#message');
  await page.waitForTimeout(600);
  const sendAfter = (await boxOf('#send')).y;
  check('кнопка отправки осталась на месте', Math.abs(sendAfter - sendBefore) < 4,
    `было ${sendBefore}, стало ${sendAfter}`);
  await page.keyboard.type('проба');
  await page.click('#send');
  await page.waitForTimeout(1200);
  check('сообщение ушло в чат', await page.locator('#chat .msg').count() >= 1);

  await browser.close();
  if (srv) srv.close();
  console.log(ok ? '\nВСЁ ХОРОШО' : '\nЕСТЬ ОШИБКИ');
  process.exit(ok ? 0 : 1);
})();
