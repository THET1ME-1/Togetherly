/* Чат в «кино» лёжа — строчками на кадре (26.10.2026, вариант Б макета
 * https://claude.ai/artifact/NUxfWeTbk786hSFTzVd8jE).
 *
 * До этого развёрнутый чат лёжа ложился панелью на нижнюю половину кадра:
 * 42% высоты во всю ширину. Теперь видны только три последние реплики, узкие
 * плашки в левом нижнем углу, и узкое поле ввода под ними; правая половина
 * кадра свободна. Стоя всё как было: там под роликом пустое поле.
 *
 * Запуск: node pocketbase/pb_public/watch/tests/room-cinema-lines.test.js
 */
const { chromium } = require('/home/alelx/.hermes/hermes-agent/node_modules/playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.woff2': 'font/woff2', '.png': 'image/png', '.svg': 'image/svg+xml',
};

function serve() {
  return new Promise((resolve) => {
    const srv = http.createServer((req, res) => {
      const url = decodeURIComponent(req.url.split('?')[0].split('#')[0]);
      let file = path.join(ROOT, url);
      if (fs.existsSync(file) && fs.statSync(file).isDirectory()) file = path.join(file, 'index.html');
      if (!fs.existsSync(file)) { res.writeHead(404).end('нет'); return; }
      res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream' });
      fs.createReadStream(file).pipe(res);
    });
    srv.listen(0, '127.0.0.1', () => resolve(srv));
  });
}

/** Шесть реплик тем же видом, что строит room.js, и «кино» с открытым чатом. */
const OPEN_CHAT = (count) => {
  const box = document.querySelector('#chat');
  box.innerHTML = '';
  for (let i = 1; i <= count; i++) {
    const el = document.createElement('div');
    el.className = 'msg' + (i % 2 === 0 ? ' msg--mine' : '');
    el.innerHTML = '<span class="msg__who"></span>';
    el.querySelector('.msg__who').textContent = i % 2 === 0 ? 'Вы' : 'Аня';
    el.appendChild(document.createTextNode('реплика ' + i));
    box.appendChild(el);
  }
  document.querySelector('#cinema').click();
  document.querySelector('#cinChat').click();
};

const LAYOUT = () => {
  const rect = (sel) => {
    const el = document.querySelector(sel);
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return r.width && r.height ? { l: r.left, t: r.top, r: r.right, b: r.bottom, w: r.width, h: r.height } : null;
  };
  const shown = [...document.querySelectorAll('#chat .msg')]
    .filter((m) => m.getBoundingClientRect().height > 0)
    .map((m) => m.textContent.replace(/^(Вы|Аня)/, '').trim());
  const side = document.querySelector('.side');
  const W = innerWidth; const H = innerHeight;
  const hit = document.elementFromPoint(W * 0.75, H * 0.45);
  return {
    W, H, shown, side: rect('.side'), composer: rect('.composer'),
    sideBg: getComputedStyle(side).backgroundColor,
    emptyHint: getComputedStyle(document.querySelector('#chat'), '::before').content,
    rightFree: !(hit && (hit.closest('.side') || hit.closest('.composer'))),
  };
};

(async () => {
  const srv = await serve();
  const port = srv.address().port;
  const browser = await chromium.launch();
  let ok = true;
  const check = (name, cond, extra = '') => {
    console.log((cond ? '  ✓ ' : '  ✗ ') + name + (extra ? '  ' + extra : ''));
    if (!cond) ok = false;
  };
  const open = async (width, height) => {
    const ctx = await browser.newContext({ viewport: { width, height }, isMobile: true, hasTouch: true, locale: 'ru-RU' });
    const page = await ctx.newPage();
    const errors = [];
    page.on('pageerror', (e) => errors.push(String(e)));
    await page.route('**/api/watch/token', (route) => route.fulfill({ status: 500, contentType: 'application/json', body: '{"ok":false}' }));
    await page.goto(`http://127.0.0.1:${port}/watch/room/#lines1`, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(600);
    return { ctx, page, errors };
  };

  for (const [W, H] of [[914, 411], [740, 360], [844, 390]]) {
    console.log(`\nЛёжа ${W}×${H}: «кино», чат открыт, шесть реплик`);
    const { ctx, page, errors } = await open(W, H);
    await page.evaluate(OPEN_CHAT, 6);
    await page.waitForTimeout(200);
    const L = await page.evaluate(LAYOUT);
    check('видны три последние реплики', JSON.stringify(L.shown) === '["реплика 4","реплика 5","реплика 6"]', JSON.stringify(L.shown));
    check('у переписки нет панели', /rgba\(0, 0, 0, 0\)|transparent/.test(L.sideBg), L.sideBg);
    check('переписка у левого края', L.side && L.side.l <= 20, L.side ? `слева ${Math.round(L.side.l)}` : 'нет');
    check('переписка не шире половины кадра', L.side && L.side.r <= W * 0.5, L.side ? `до ${Math.round(L.side.r)} из ${W}` : 'нет');
    check('поле ввода есть и не шире половины кадра', L.composer && L.composer.r <= W * 0.5 && L.composer.h >= 44,
      L.composer ? `${Math.round(L.composer.l)}–${Math.round(L.composer.r)}, высота ${Math.round(L.composer.h)}` : 'нет');
    check('поле ввода внизу экрана', L.composer && L.composer.b <= H && L.composer.b >= H - 24, L.composer ? `низ ${Math.round(L.composer.b)}` : 'нет');
    check('переписка над полем, без наезда', L.side && L.composer && L.side.b <= L.composer.t + 1,
      L.side && L.composer ? `${Math.round(L.side.b)} / ${Math.round(L.composer.t)}` : 'нет');
    check('правая половина кадра свободна', L.rightFree);
    check('ошибок на странице нет', errors.length === 0, errors.join('; '));
    await ctx.close();
  }

  console.log('\nЛёжа, чат пуст: подсказки «здесь пока пусто» на кадре нет');
  {
    const { ctx, page } = await open(914, 411);
    await page.evaluate(OPEN_CHAT, 0);
    await page.waitForTimeout(200);
    const L = await page.evaluate(LAYOUT);
    check('подсказки нет', L.emptyHint === 'none' || L.emptyHint === 'normal', L.emptyHint);
    await ctx.close();
  }

  console.log('\nСтоя 393×760: панель чата как была');
  {
    const { ctx, page } = await open(393, 760);
    await page.evaluate(OPEN_CHAT, 6);
    await page.waitForTimeout(200);
    const L = await page.evaluate(LAYOUT);
    check('у переписки своя панель', !/rgba\(0, 0, 0, 0\)|transparent/.test(L.sideBg), L.sideBg);
    check('видны все шесть реплик', L.shown.length === 6, String(L.shown.length));
    await ctx.close();
  }

  await browser.close();
  srv.close();
  console.log(ok ? '\nВСЁ ХОРОШО' : '\nЕСТЬ ОШИБКИ');
  process.exit(ok ? 0 : 1);
})();
