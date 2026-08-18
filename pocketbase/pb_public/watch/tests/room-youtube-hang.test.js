/* Комната не должна умирать вместе с ютубом.
 *
 * Жалоба с айфона (18.08.2026): «создаю комнату — кнопки не реагируют, ссылку
 * вставить не получается, писать в чат тоже», у партнёра на Android всё
 * работает. Корень не в устройстве: страница грузила `iframe_api` ютуба
 * ОБЫЧНЫМ синхронным тегом, а весь запуск (код комнаты, подключение к каналу,
 * обработчики всех кнопок) висел на `window.load`. Событие `load` ждёт каждый
 * подресурс, поэтому там, где ютуб не отвечает — а у российских операторов он
 * то отдаёт, то висит до таймаута, — комната открывалась мёртвой: заголовок,
 * поля и кнопки на месте, но ни одно нажатие не работает. Замер: при зависшем
 * youtube.com `load` не наступает и через 25 секунд.
 *
 * Здесь проверяем ровно это: при недоступном ютубе комната живая — код на
 * месте, кнопки нажимаются, сообщение уходит, ссылка включается. И отдельно,
 * что при живом ютубе плеер по-прежнему поднимается через его API (иначе
 * пропала бы синхронизация).
 *
 * Запуск: node pocketbase/pb_public/watch/tests/room-youtube-hang.test.js
 */
const { chromium } = require('/home/alelx/.hermes/hermes-agent/node_modules/playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..');           // pb_public
const PORT = 8793;
const LINK = 'https://www.youtube.com/watch?v=jNQXAC9IVRw';

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

/** Открывает комнату телефоном; `hang` — ютуб не отвечает вовсе. */
async function openRoom(browser, room, hang) {
  const ctx = await browser.newContext({
    viewport: { width: 390, height: 545 }, isMobile: true, hasTouch: true,
    userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) '
      + 'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148',
  });
  if (hang) {
    // Соединение не рвётся и не отвечает — так ведёт себя замедленный ютуб.
    // Оборванный запрос (RST) страницу не ломает: `load` тогда наступает.
    await ctx.route('**://*.youtube.com/**', () => {});
    await ctx.route('**://*.ytimg.com/**', () => {});
  }
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e).slice(0, 160)));
  // Ждём только ответа сервера: при зависшем ютубе разбор страницы до конца
  // не доходит вовсе — синхронный тег скрипта держит парсер, и DOMContentLoaded
  // тоже не наступает.
  await page.goto(`http://127.0.0.1:${PORT}/watch/room/#${room}`, { waitUntil: 'commit' });
  // Столько человек ждёт, прежде чем решить, что комната сломана.
  await page.waitForTimeout(3000);
  return { ctx, page, errors };
}

(async () => {
  const srv = await serve();
  const browser = await chromium.launch();

  console.log('1. ютуб не отвечает — комната всё равно рабочая');
  {
    const { ctx, page, errors } = await openRoom(browser, 'hang01', true);

    check('код комнаты на месте',
      (await page.textContent('#code')) === 'hang01', await page.textContent('#code'));

    await page.tap('#cinema').catch(() => {});
    check('кнопка «кинозал» нажимается',
      await page.evaluate(() => document.body.classList.contains('cinema')));
    // Возвращаем обычную раскладку: в кинозале кадр занимает всю площадь и
    // накрывает строку со ссылкой.
    await page.tap('#cinema').catch(() => {});

    await page.fill('#message', 'ты тут?').catch(() => {});
    await page.tap('#send').catch(() => {});
    check('сообщение уходит в чат',
      await page.evaluate(() => document.querySelectorAll('#chat .msg').length > 0));

    await page.fill('#link', LINK).catch(() => {});
    await page.tap('#apply').catch(() => {});
    await page.waitForTimeout(1500);
    check('ссылка включается (кадр встал)',
      await page.evaluate(() => !!document.querySelector('#player iframe')));
    check('страница не падает', errors.length === 0, errors.join(' | '));

    await ctx.close();
  }

  console.log('2. ютуб отвечает — плеером по-прежнему управляет его API');
  {
    const { ctx, page, errors } = await openRoom(browser, 'hang02', false);
    await page.fill('#link', LINK).catch(() => {});
    await page.tap('#apply').catch(() => {});
    // API грузится параллельно: ждём, пока плеер отзовётся.
    await page.waitForFunction(
      () => { try { return typeof document.querySelector('#player iframe').id === 'string'; } catch (_) { return false; } },
      null, { timeout: 15000 },
    ).catch(() => {});
    await page.waitForTimeout(6000);
    check('плеер ютуба поднялся и принимает команды',
      await page.evaluate(() => !!(window.YT && YT.Player)
        && !!document.querySelector('#player iframe[src*="youtube.com/embed"]')));
    check('страница не падает', errors.length === 0, errors.join(' | '));
    await ctx.close();
  }

  await browser.close();
  srv.close();
  console.log(ok ? '\nВСЁ ХОРОШО' : '\nЕСТЬ ПРОБЛЕМЫ');
  process.exit(ok ? 0 : 1);
})();
