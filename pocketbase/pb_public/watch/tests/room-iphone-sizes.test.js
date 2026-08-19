/* Комната просмотра на всех размерах iPhone: от SE 320×568 до 17 Pro Max
 * 440×956.
 *
 * Завёлся после жалобы «ссылки для просмотра видео не вставляются»: строка
 * ввода стояла в одном ряду с двумя иконками и кнопкой «Включить», и ей
 * доставалось 42 точки на SE, 77 на mini, 110 на пятнадцатом. В такую строку
 * нельзя ни попасть пальцем, ни увидеть вставленный адрес.
 *
 * Запуск: node pocketbase/pb_public/watch/tests/room-iphone-sizes.test.js
 * Снимки: SHOTS=<папка> перед командой.
 *
 * Исходно — снимки комнаты на всех размерах iPhone.
 *
 * Размеры взяты из таблицы CSS-вьюпортов (yesviz), от SE 320×568 до
 * 16/17 Pro Max 440×956. Смотрим глазами: не выдавливает ли что-нибудь строку
 * ввода ссылки и кнопки под ней.
 */
const { chromium } = require('/home/alelx/.hermes/hermes-agent/node_modules/playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.SHOTS || path.join(require('os').tmpdir(), 'room-shots');

const SIZES = [
  ['SE-1', 320, 568],
  ['13-mini', 360, 780],
  ['SE-2022', 375, 667],
  ['X-11Pro', 375, 812],
  ['12-13-14', 390, 844],
  ['15-16', 393, 852],
  ['16-17-Pro', 402, 874],
  ['XR-11', 414, 896],
  ['17-Air', 420, 912],
  ['12-13-ProMax', 428, 926],
  ['15-16-Plus', 430, 932],
  ['16-17-ProMax', 440, 956],
];

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.webp': 'image/webp',
};

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
  fs.mkdirSync(OUT, { recursive: true });
  const srv = await serve();
  const port = srv.address().port;
  const browser = await chromium.launch();
  const problems = [];

  for (const [name, w, h] of SIZES) {
    const ctx = await browser.newContext({
      viewport: { width: w, height: h },
      deviceScaleFactor: 3,
      isMobile: true,
      hasTouch: true,
      userAgent:
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 '
        + '(KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1',
    });
    const page = await ctx.newPage();
    const errors = [];
    page.on('pageerror', (e) => errors.push(String(e).slice(0, 120)));
    await page.goto(`http://127.0.0.1:${port}/watch/room/#abcdef`, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(900);

    // Что видно человеку: помещается ли строка ссылки и кнопки в экран.
    const facts = await page.evaluate(() => {
      const box = (sel) => {
        const el = document.querySelector(sel);
        if (!el) return null;
        const r = el.getBoundingClientRect();
        const cs = getComputedStyle(el);
        return {
          x: Math.round(r.x), y: Math.round(r.y),
          w: Math.round(r.width), h: Math.round(r.height),
          visible: cs.display !== 'none' && cs.visibility !== 'hidden' && r.width > 0,
        };
      };
      return {
        link: box('#link'),
        apply: box('#apply'),
        pick: box('#pick'),
        chat: box('.composer'),
        docW: document.documentElement.scrollWidth,
        winW: window.innerWidth,
        winH: window.innerHeight,
      };
    });

    if (facts.docW > facts.winW + 1) {
      problems.push(`${name} ${w}×${h}: страница шире экрана (${facts.docW} против ${facts.winW})`);
    }
    for (const key of ['link', 'apply', 'pick']) {
      const b = facts[key];
      if (!b || !b.visible) { problems.push(`${name}: ${key} не виден`); continue; }
      if (b.x < 0 || b.x + b.w > facts.winW + 1) {
        problems.push(`${name} ${w}×${h}: ${key} вылезает за экран (x=${b.x}, w=${b.w})`);
      }
      if (b.y + b.h > facts.winH + 1) {
        problems.push(`${name} ${w}×${h}: ${key} ниже экрана (низ ${b.y + b.h} при высоте ${facts.winH})`);
      }
    }
    if (facts.link && facts.link.w < 90) {
      problems.push(`${name} ${w}×${h}: строка ссылки шириной ${facts.link.w} — вставлять некуда`);
    }
    if (errors.length) problems.push(`${name}: ошибки страницы — ${errors.join(' | ')}`);

    await page.screenshot({ path: path.join(OUT, `${w}x${h}-${name}.png`), fullPage: false });
    console.log(
      `${String(w).padStart(3)}×${String(h).padEnd(4)} ${name.padEnd(14)} `
      + `ссылка ${facts.link ? facts.link.w + 'px' : 'нет'}, `
      + `кнопка «Включить» ${facts.apply ? facts.apply.w + 'px' : 'нет'}, `
      + `док ${facts.docW}px`,
    );
    await ctx.close();
  }

  await browser.close();
  srv.close();
  console.log('\nНАЙДЕНО:', problems.length);
  problems.forEach((p) => console.log('  •', p));
  console.log('снимки:', OUT);
  if (problems.length) {
    console.log('\nПЛОХО');
    process.exit(1);
  }
  console.log('\nВСЁ ХОРОШО');
})();
