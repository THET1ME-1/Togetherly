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
  // ── iPhone: CSS-вьюпорты от первого SE до 17 Pro Max ────────────────────
  ['iPhone SE 1', 320, 568, 3],
  ['iPhone 13 mini', 360, 780, 3],
  ['iPhone SE 2022', 375, 667, 2],
  ['iPhone X · 11 Pro', 375, 812, 3],
  ['iPhone 12 · 13 · 14', 390, 844, 3],
  ['iPhone 15 · 16', 393, 852, 3],
  ['iPhone 16 · 17 Pro', 402, 874, 3],
  ['iPhone XR · 11', 414, 896, 2],
  ['iPhone 17 Air', 420, 912, 3],
  ['iPhone 12 · 13 Pro Max', 428, 926, 3],
  ['iPhone 15 · 16 Plus', 430, 932, 3],
  ['iPhone 16 · 17 Pro Max', 440, 956, 3],

  // ── iPad: обе ориентации. Комнату открывают и с планшета, а на нём
  //    раскладка переключается на двухколоночную (медиазапрос 900px). ─────
  ['iPad mini книжно', 744, 1133, 2],
  ['iPad mini альбомно', 1133, 744, 2],
  ['iPad 10 книжно', 810, 1080, 2],
  ['iPad 10 альбомно', 1080, 810, 2],
  ['iPad Air 11 книжно', 820, 1180, 2],
  ['iPad Air 11 альбомно', 1180, 820, 2],
  ['iPad Pro 11 книжно', 834, 1210, 2],
  ['iPad Pro 11 альбомно', 1210, 834, 2],
  ['iPad Pro 13 книжно', 1024, 1366, 2],
  ['iPad Pro 13 альбомно', 1366, 1024, 2],

  // ── Мониторы: самые ходовые разрешения плюс те же в повороте — портретный
  //    монитор редок, но раскладка на нём не должна разъезжаться. ─────────
  ['ноутбук 1366', 1366, 768, 1],
  ['ноутбук 1366 боком', 768, 1366, 1],
  ['ноутбук 1440', 1440, 900, 1],
  ['ноутбук 1440 боком', 900, 1440, 1],
  ['ноутбук 1536', 1536, 864, 1],
  ['ноутбук 1536 боком', 864, 1536, 1],
  ['Full HD', 1920, 1080, 1],
  ['Full HD боком', 1080, 1920, 1],
  ['2K', 2560, 1440, 1],
  ['2K боком', 1440, 2560, 1],
  ['ультраширокий', 3440, 1440, 1],
  ['4K', 3840, 2160, 1],
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

  for (const [name, w, h, dpr] of SIZES) {
    const touch = dpr > 1; // телефоны и планшеты
    const ctx = await browser.newContext({
      viewport: { width: w, height: h },
      deviceScaleFactor: dpr,
      isMobile: touch,
      hasTouch: touch,
      userAgent: touch
        ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 '
          + '(KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1'
        : 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
          + '(KHTML, like Gecko) Version/18.5 Safari/605.1.15',
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
      const body = document.querySelector('.room-body');
      const stage = document.querySelector('.player');
      const chat = document.querySelector('.side');
      const used = () => {
        const parts = [stage, chat, document.querySelector('.source')]
          .filter(Boolean).map((el) => el.getBoundingClientRect());
        if (!parts.length) return 0;
        const top = Math.min(...parts.map((r) => r.top));
        const bottom = Math.max(...parts.map((r) => r.bottom));
        return Math.round(bottom - top);
      };
      return {
        usedHeight: used(),
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
    // Комната обязана занимать экран, а не полосу посреди пустоты: на
    // портретном мониторе и на 4K содержимое сжималось в треть высоты.
    const fill = facts.usedHeight / facts.winH;
    if (fill < 0.55) {
      problems.push(
        `${name} ${w}×${h}: содержимое занимает ${Math.round(fill * 100)}% высоты`,
      );
    }
    if (facts.link && facts.link.w < 90) {
      problems.push(`${name} ${w}×${h}: строка ссылки шириной ${facts.link.w} — вставлять некуда`);
    }
    if (errors.length) problems.push(`${name}: ошибки страницы — ${errors.join(' | ')}`);

    const file = `${String(w).padStart(4, '0')}x${h}-${name.replace(/[^a-zA-Zа-яА-Я0-9]+/g, '-')}.png`;
    await page.screenshot({ path: path.join(OUT, file), fullPage: false });
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
