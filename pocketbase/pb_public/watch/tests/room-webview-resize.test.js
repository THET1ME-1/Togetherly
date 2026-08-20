/* Комната внутри приложения: окно сжалось, а страница об этом не услышала.
 *
 * Жалоба 20.08.2026, два человека: «опять при совместном кино ничего не
 * нажимается, даже после обновления», «вроде только на айфонах». В браузере с
 * компьютера та же страница работает.
 *
 * Что происходит. Экран комнаты в приложении показывает полосу голоса
 * (`WatchVoiceBar`), и появляется она не сразу, а когда поднимется канал —
 * через секунду-полторы после открытия. Полоса — `bottomNavigationBar`, она
 * отрезает у WebView около 84 точек снизу. Страница к этому времени уже
 * посчитала высоту и прибила её к `--vph` (`position: fixed`, `overflow:
 * hidden`, прокрутки нет). Новую высоту она берёт только из событий
 * `visualViewport`, а их шлёт система — на клавиатуру и поворот. Кадр, который
 * меняет сам Flutter, системным событием не является, и в WKWebView уведомление
 * может не прийти вовсе.
 *
 * Итог: страница остаётся высотой в прежний экран, нижний ряд — поле
 * сообщения, «Отправить», а на низких экранах и «Включить» — оказывается за
 * краем WebView. Нажать нечего, и это выглядит как «ничего не нажимается».
 *
 * Тест глушит ОБА канала уведомлений (visualViewport и window.resize) — так
 * ведёт себя самый глухой WebView. Страница обязана заметить сжатие сама.
 *
 * Запуск: node pocketbase/pb_public/watch/tests/room-webview-resize.test.js
 */
const { chromium } = require('/home/alelx/.hermes/hermes-agent/node_modules/playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.webp': 'image/webp',
  '.woff2': 'font/woff2',
};

/** Полоса голоса: кнопка 44 точки, отступы и домашняя черта. */
const VOICE_BAR = 84;

const PHONES = [
  // Ширина, высота WebView до появления полосы голоса (экран минус шапка
  // приложения и системные поля) — и то, что от неё остаётся после.
  ['iPhone SE', 320, 408],
  ['iPhone 13 mini', 360, 631],
  ['iPhone 15', 393, 703],
  ['iPhone 16 Pro Max', 440, 804],
];

/** Нижний ряд управления: без него в комнате нечего делать. */
const CONTROLS = ['#link', '#pick', '#cinema', '#apply', '#message', '#send'];

function serve() {
  return new Promise((resolve) => {
    const srv = http.createServer((req, res) => {
      const url = decodeURIComponent(req.url.split('?')[0].split('#')[0]);
      let file = path.join(ROOT, url);
      if (fs.existsSync(file) && fs.statSync(file).isDirectory()) {
        file = path.join(file, 'index.html');
      }
      if (!fs.existsSync(file)) {
        res.writeHead(404).end('нет');
        return;
      }
      res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream' });
      fs.createReadStream(file).pipe(res);
    });
    srv.listen(0, '127.0.0.1', () => resolve(srv));
  });
}

(async () => {
  const srv = await serve();
  const port = srv.address().port;
  const browser = await chromium.launch();
  let ok = true;
  const check = (name, cond, extra = '') => {
    console.log((cond ? '  ✓ ' : '  ✗ ') + name + (extra ? '  ' + extra : ''));
    if (!cond) ok = false;
  };

  for (const [name, w, tall] of PHONES) {
    const short = tall - VOICE_BAR;
    console.log(`\n${name} ${w}×${tall} → ${w}×${short} (выехала полоса голоса)`);

    const ctx = await browser.newContext({
      viewport: { width: w, height: tall },
      deviceScaleFactor: 3,
      isMobile: true,
      hasTouch: true,
      userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) '
        + 'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148',
    });
    const page = await ctx.newPage();

    // Самый глухой WebView: ни visualViewport, ни window не рассказывают о
    // новом размере. Заглушку ставим до загрузки страницы, чтобы room.js
    // подписывался уже на неё.
    await page.addInitScript(() => {
      const deaf = () => {};
      if (window.visualViewport) window.visualViewport.addEventListener = deaf;
      const original = window.addEventListener.bind(window);
      window.addEventListener = (type, ...rest) => {
        if (type === 'resize' || type === 'orientationchange') return;
        return original(type, ...rest);
      };
    });
    // Комнату поднимаем без сервера: тут проверяется раскладка, а не канал.
    await page.route('**/api/watch/token', (route) => route.fulfill({
      status: 500, contentType: 'application/json', body: '{"ok":false}',
    }));

    await page.goto(`http://127.0.0.1:${port}/watch/room/#voice1`, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(900);
    await page.setViewportSize({ width: w, height: short });
    // Полторы секунды — столько человек ждёт, пока комната придёт в себя.
    await page.waitForTimeout(1500);

    const facts = await page.evaluate((ids) => {
      const body = document.querySelector('.room-body');
      const out = {
        pageHeight: Math.round(body.getBoundingClientRect().height),
        visible: window.innerHeight,
        offscreen: [],
        covered: [],
      };
      for (const id of ids) {
        const el = document.querySelector(id);
        if (!el) continue;
        const r = el.getBoundingClientRect();
        const cx = r.left + r.width / 2;
        const cy = r.top + r.height / 2;
        if (cy > window.innerHeight || r.bottom > window.innerHeight + 1) {
          out.offscreen.push(id + ' на ' + Math.round(r.bottom - window.innerHeight) + ' px');
          continue;
        }
        const top = document.elementFromPoint(cx, cy);
        if (!(top === el || el.contains(top) || (top && top.contains(el)))) {
          out.covered.push(id + ' ← ' + (top ? top.tagName.toLowerCase() : 'пусто'));
        }
      }
      return out;
    }, CONTROLS);

    check('страница подогналась под окно', facts.pageHeight <= facts.visible + 1,
      `высота ${facts.pageHeight}, видно ${facts.visible}`);
    check('весь нижний ряд на экране', facts.offscreen.length === 0,
      facts.offscreen.join(', '));
    check('кнопки ничем не перекрыты', facts.covered.length === 0,
      facts.covered.join(', '));

    // Последняя проверка — настоящим нажатием, а не замером.
    const typed = await page.evaluate(() => {
      const el = document.querySelector('#message');
      if (!el) return 'нет поля';
      el.value = 'проверка';
      const btn = document.querySelector('#send');
      const r = btn.getBoundingClientRect();
      const hit = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
      return hit === btn || btn.contains(hit) ? 'ok' : 'мимо';
    });
    check('палец попадает в «Отправить»', typed === 'ok', typed);

    await ctx.close();
  }

  await browser.close();
  srv.close();
  console.log(ok ? '\nВСЁ СОШЛОСЬ' : '\nЕСТЬ РАСХОЖДЕНИЯ');
  process.exit(ok ? 0 : 1);
})();
