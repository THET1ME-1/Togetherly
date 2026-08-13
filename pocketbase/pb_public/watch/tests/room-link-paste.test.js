/* Ссылка, вставленная поверх прежней.
 *
 * С 12 августа 2026 строка ввода на iPhone наконец принимает нажатия (до этого
 * её выдавливал кадр плеера). Тут же вылезло следующее: поле уже содержит
 * ссылку — приложение кладёт её туда параметром `?src=`, — а вставка идёт в
 * конец, а не вместо. За сутки так испорчено 49 включений из 500: в истории
 * лежат адреса вида `<ссылка> <та же ссылка>`, `<ютуб><ivi>` и `hhttps://…`.
 * Человек при этом видит прежний ролик и решает, что кнопка не работает.
 *
 * Чиним с двух концов: поле выделяет старое значение при фокусе (вставка
 * заменяет), а разбор берёт из строки ПЕРВЫЙ настоящий адрес и прощает лишнюю
 * букву перед схемой.
 *
 * Запуск: node pocketbase/pb_public/watch/tests/room-link-paste.test.js
 * Против прода: node …/room-link-paste.test.js https://togetherly.day
 */
const { chromium } = require('/home/alelx/.hermes/hermes-agent/node_modules/playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..');           // pb_public
const ARG = process.argv[2] || '';
const PORT = 8791;

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

/* Живые примеры из watch_history за 11–13 августа. */
const CASES = [
  {
    name: 'та же ссылка вставлена вторым разом (через пробел)',
    typed: 'https://youtu.be/ZezK8dig-xU?si=F03a0xHRzvIrUi_E https://youtu.be/ZezK8dig-xU?si=F03a0xHRzvIrUi_E',
    embed: /youtube\.com\/embed\/ZezK8dig-xU\b/,
    clean: 'https://youtu.be/ZezK8dig-xU?si=F03a0xHRzvIrUi_E',
  },
  {
    name: 'вторая ссылка прилипла без пробела — берём первую',
    typed: 'https://youtu.be/gyRGNKq5qiw?si=xgn6g_kED5x6SocRhttps://youtu.be/LOmm26EO77U?si=TvvI_Be8QBxUb6ra',
    embed: /youtube\.com\/embed\/gyRGNKq5qiw\b/,
    clean: 'https://youtu.be/gyRGNKq5qiw?si=xgn6g_kED5x6SocR',
  },
  {
    name: 'лишняя буква перед схемой (hhttps://)',
    typed: 'hhttps://rutube.ru/video/cd49dba03b95c4030b446156b638d892/',
    embed: /rutube\.ru\/play\/embed\/cd49dba03b95c4030b446156b638d892/,
    clean: 'https://rutube.ru/video/cd49dba03b95c4030b446156b638d892/',
  },
  {
    name: 'ссылка среди слов',
    typed: 'посмотри https://vkvideo.ru/video-217672812_456239413 давай',
    embed: /vk\.com\/video_ext\.php\?oid=-217672812&id=456239413/,
    clean: 'https://vkvideo.ru/video-217672812_456239413',
  },
];

let ok = true;
const check = (n, c, x = '') => { console.log((c ? '  ✓ ' : '  ✗ ') + n, x); if (!c) ok = false; };

(async () => {
  const srv = ARG ? null : await serve();
  const base = (ARG || `http://127.0.0.1:${PORT}`) + '/watch/room/';
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true });

  console.log('1. мусор в строке разбирается до настоящего адреса');
  for (const c of CASES) {
    const p = await ctx.newPage();
    await p.goto(base + '#paste' + Math.abs(c.name.length), { waitUntil: 'domcontentloaded' });
    // Обработчики вешает init, и он же проставляет код комнаты в шапке: без
    // этого ожидания первая страница на живом сервере успевала получить клик
    // раньше, чем скрипт до неё доходил.
    await p.waitForFunction(() => {
      const el = document.querySelector('#code');
      return !!el && el.textContent.trim().length > 0;
    }, null, { timeout: 15000 });
    // Код в шапке ставится раньше, чем навешивается обработчик кнопки, и на
    // живом сервере первая страница успевала получить клик между этими двумя
    // строками — тест падал, а руками всё работало.
    await p.waitForTimeout(1200);
    await p.fill('#link', c.typed);
    await p.click('#apply');
    await p.waitForTimeout(1200);

    const frame = await p.getAttribute('#frame', 'src').catch(() => null);
    check(c.name, !!frame && c.embed.test(frame), frame ? '' : '(плеер не встал)');

    const inField = await p.inputValue('#link');
    check('   поле показывает чистую ссылку', inField === c.clean, JSON.stringify(inField));
    await p.close();
  }

  console.log('2. вставка заменяет прежнюю ссылку, а не дописывается');
  {
    const p = await ctx.newPage();
    const first = 'https://youtu.be/jNQXAC9IVRw';
    await p.goto(base + '?src=' + encodeURIComponent(first) + '#paste-focus',
      { waitUntil: 'domcontentloaded' });
    await p.waitForTimeout(600);
    check('   приложение положило ссылку в поле', (await p.inputValue('#link')) === first);

    await p.click('#link');
    const selected = await p.evaluate(() => {
      const el = document.querySelector('#link');
      return el.value.slice(el.selectionStart, el.selectionEnd);
    });
    check('   нажатие выделяет её целиком', selected === first, JSON.stringify(selected));

    // так ведёт себя вставка поверх выделения
    await p.evaluate(() => {
      const el = document.querySelector('#link');
      el.setRangeText('https://youtu.be/ZezK8dig-xU', el.selectionStart, el.selectionEnd, 'end');
      el.dispatchEvent(new Event('input', { bubbles: true }));
    });
    check('   в поле осталась одна ссылка',
      (await p.inputValue('#link')) === 'https://youtu.be/ZezK8dig-xU',
      JSON.stringify(await p.inputValue('#link')));
    await p.close();
  }

  await browser.close();
  if (srv) srv.close();
  console.log(ok ? '\nВСЁ ХОРОШО' : '\nЕСТЬ ПРОВАЛЫ');
  process.exit(ok ? 0 : 1);
})();
