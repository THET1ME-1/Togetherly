/* Комната на телефоне говорит, почему ролик не включился.
 *
 * Жалоба с iPhone 17.09.2026 (1.31.6, обращение 217): «не получается вставить
 * ссылку и вообще ничего не работает», «вставляю ссылку, но видео не
 * включается». Страница в приложении была подключена — сервер пропустил все
 * пять её заходов, — а всё, что комната отвечала человеку, писалось в строку
 * статуса. На экране уже 900 точек эта строка скрыта (`.status-line { display:
 * none }`), и «Такую ссылку не открыть» не видел никто: нажатие «Включить»
 * выглядело мёртвым.
 *
 * Теперь важное повторяет плашка `#note` под шапкой. Тест проверяет её на
 * экране iPhone в WebKit: пустое поле, неподходящая ссылка, плашка не
 * закрывает строку ссылки и кнопку и пропускает касания насквозь, уходит
 * сама, а на широком экране молчит — там строка статуса видна сама.
 *
 * Запуск: node pocketbase/pb_public/watch/tests/room-phone-note.test.js
 */
const { webkit, devices } = require('/home/alelx/.hermes/hermes-agent/node_modules/playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..');           // pb_public
const PORT = 8794;

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

/** Видна ли плашка и что в ней. */
const noteState = (p) => p.evaluate(() => {
  const el = document.querySelector('#note');
  if (!el) return { exists: false, visible: false, text: '' };
  const r = el.getBoundingClientRect();
  return {
    exists: true,
    visible: !el.hidden && getComputedStyle(el).display !== 'none' && r.height > 0,
    text: el.textContent,
    box: [r.left, r.top, r.width, r.height].map(Math.round),
  };
});

/** Попадает ли касание в центр элемента в сам элемент, а не в то, что сверху. */
const reachable = (p, sel) => p.evaluate((s) => {
  const el = document.querySelector(s);
  const r = el.getBoundingClientRect();
  const top = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
  return top === el || el.contains(top);
}, sel);

async function open(ctx, room) {
  const p = await ctx.newPage();
  // Встроенный браузер приложения: мост есть, звонок рисует шапка.
  await p.addInitScript(() => {
    window.flutter_inappwebview = { callHandler: () => Promise.resolve() };
  });
  // Пропуска нет — сервер отказал бы, но этому тесту связь не нужна:
  // ссылка включается у себя и без канала.
  await p.route('**/api/watch/token', (r) => r.fulfill({
    status: 200, contentType: 'application/json',
    body: JSON.stringify({ ok: false }),
  }));
  await p.goto(`http://127.0.0.1:${PORT}/watch/room/#${room}`, { waitUntil: 'domcontentloaded' });
  await p.waitForFunction(() => (document.querySelector('#code') || {}).textContent === location.hash.slice(1));
  await p.waitForTimeout(800);
  return p;
}

(async () => {
  const srv = await serve();
  const browser = await webkit.launch();

  console.log('1. iPhone: пустое поле и неподходящая ссылка');
  {
    const ctx = await browser.newContext({ ...devices['iPhone 14'], locale: 'ru-RU' });
    const p = await open(ctx, 'huhf53zu');

    await p.tap('#apply');
    await p.waitForTimeout(300);
    let n = await noteState(p);
    check('«Включить» без ссылки просит её вставить', n.visible && /ссылк/i.test(n.text), JSON.stringify(n));

    await p.fill('#link', 'https://www.kinopoisk.ru/film/326/');
    await p.tap('#apply');
    await p.waitForTimeout(300);
    n = await noteState(p);
    check('неподходящая ссылка называет площадки', n.visible && /YouTube/.test(n.text), JSON.stringify(n));

    check('строка ссылки под плашкой доступна', await reachable(p, '#link'));
    check('«Включить» под плашкой доступна', await reachable(p, '#apply'));
    check('поле сообщения доступно', await reachable(p, '#message'));

    // Плашка прозрачна для пальца: в низком окне она ложится на строку
    // ссылки, и касание должно дойти до того, что под ней.
    const through = await p.evaluate(() => {
      const r = document.querySelector('#note').getBoundingClientRect();
      const top = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
      return !!top && top.id !== 'note';
    });
    check('плашка не ловит касания', through);

    await p.fill('#link', 'https://youtu.be/ZezK8dig-xU');
    await p.tap('#apply');
    await p.waitForTimeout(600);
    const frame = await p.getAttribute('#frame', 'src').catch(() => null);
    check('годная ссылка по-прежнему включает ролик', !!frame && /embed\/ZezK8dig-xU/.test(frame), String(frame));
    await ctx.close();
  }

  console.log('2. плашка уходит сама');
  {
    const ctx = await browser.newContext({ ...devices['iPhone 14'], locale: 'ru-RU' });
    const p = await open(ctx, 'huhf53zu');
    await p.tap('#apply');
    await p.waitForTimeout(6500);
    const n = await noteState(p);
    check('через несколько секунд её нет', !n.visible, JSON.stringify(n));
    await ctx.close();
  }

  console.log('3. широкий экран: строка статуса видна, плашка молчит');
  {
    const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 }, locale: 'ru-RU' });
    const p = await open(ctx, 'huhf53zu');
    await p.fill('#link', 'https://www.kinopoisk.ru/film/326/');
    await p.click('#apply');
    await p.waitForTimeout(300);
    const n = await noteState(p);
    const line = await p.textContent('#status');
    check('отказ в строке статуса', /YouTube/.test(line), JSON.stringify(line));
    check('плашки нет', !n.visible, JSON.stringify(n));
    await ctx.close();
  }

  await browser.close();
  srv.close();
  console.log(ok ? '\nВСЁ ХОРОШО' : '\nЕСТЬ ПРОВАЛЫ');
  process.exit(ok ? 0 : 1);
})().catch((e) => { console.error(e); process.exit(1); });
