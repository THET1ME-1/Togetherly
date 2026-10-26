/* Режим «кино» и приложение (TOG-43, обращение 488).
 *
 * На Android в режиме «кино» оставались строка состояния и кнопки навигации,
 * по краям лежали поля, а стоя ролик шёл узкой полосой: страница растягивала
 * кадр, но окном распоряжается приложение, и оно ничего не знало. Теперь
 * страница говорит приложению мостом `watchCinema` {on}, а приложение прячет
 * панели, снимает отступы и кладёт телефон набок. «Назад» в режиме сперва
 * выключает режим: приложение зовёт `window.roomExitCinema()`.
 *
 * Запуск: node pocketbase/pb_public/watch/tests/room-cinema-bridge.test.js
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
  '.woff2': 'font/woff2',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
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

const APP_BRIDGE = () => {
  window.__calls = [];
  window.flutter_inappwebview = {
    callHandler: (name, ...args) => {
      window.__calls.push({ name, args });
      return Promise.resolve();
    },
  };
};

(async () => {
  const srv = await serve();
  const port = srv.address().port;
  const url = `http://127.0.0.1:${port}/watch/room/#cinema1`;
  const browser = await chromium.launch();
  let ok = true;
  const check = (name, cond, extra = '') => {
    console.log((cond ? '  ✓ ' : '  ✗ ') + name + (extra ? '  ' + extra : ''));
    if (!cond) ok = false;
  };

  const open = async ({ withBridge }) => {
    const ctx = await browser.newContext({
      viewport: { width: 393, height: 760 },
      deviceScaleFactor: 3,
      isMobile: true,
      hasTouch: true,
    });
    const page = await ctx.newPage();
    const errors = [];
    page.on('pageerror', (e) => errors.push(String(e)));
    if (withBridge) await page.addInitScript(APP_BRIDGE);
    await page.route('**/api/watch/token', (route) => route.fulfill({
      status: 500, contentType: 'application/json', body: '{"ok":false}',
    }));
    await page.goto(url, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(700);
    return { ctx, page, errors };
  };
  const cinemaCalls = (page) => page.evaluate(() =>
    window.__calls.filter((c) => c.name === 'watchCinema').map((c) => c.args[0] && c.args[0].on));
  const pressCinema = (page) => page.evaluate(() => document.querySelector('#cinema').click());

  console.log('\n1. В приложении: вход в «кино» и выход сообщаются мостом');
  {
    const { ctx, page } = await open({ withBridge: true });
    await pressCinema(page);
    await page.waitForTimeout(100);
    check('режим включён на странице', await page.evaluate(() => document.body.classList.contains('cinema')));
    check('приложению ушло «включили»', JSON.stringify(await cinemaCalls(page)) === '[true]',
      JSON.stringify(await cinemaCalls(page)));
    await pressCinema(page);
    await page.waitForTimeout(100);
    check('приложению ушло «выключили»', JSON.stringify(await cinemaCalls(page)) === '[true,false]',
      JSON.stringify(await cinemaCalls(page)));
    await ctx.close();
  }

  console.log('\n2. «Назад» в приложении выключает режим, а не выводит из комнаты');
  {
    const { ctx, page } = await open({ withBridge: true });
    await pressCinema(page);
    const answer = await page.evaluate(() => typeof window.roomExitCinema === 'function' && window.roomExitCinema());
    check('roomExitCinema отвечает, что выключила режим', answer === true);
    check('режим снят', !(await page.evaluate(() => document.body.classList.contains('cinema'))));
    check('приложению ушло «выключили»', JSON.stringify(await cinemaCalls(page)) === '[true,false]',
      JSON.stringify(await cinemaCalls(page)));
    const idle = await page.evaluate(() => window.roomExitCinema());
    check('вне режима отвечает false: «назад» уйдёт дальше', idle === false);
    await ctx.close();
  }

  console.log('\n3. Повторное включение не шлёт лишнего');
  {
    const { ctx, page } = await open({ withBridge: true });
    await page.evaluate(() => { document.querySelector('#cinema').click(); });
    await page.evaluate(() => window.roomExitCinema());
    await page.evaluate(() => window.roomExitCinema());
    check('одно «включили» и одно «выключили»', JSON.stringify(await cinemaCalls(page)) === '[true,false]',
      JSON.stringify(await cinemaCalls(page)));
    await ctx.close();
  }

  console.log('\n4. Обычный браузер: моста нет, режим работает и без него');
  {
    const { ctx, page, errors } = await open({ withBridge: false });
    await pressCinema(page);
    check('режим включился', await page.evaluate(() => document.body.classList.contains('cinema')));
    check('ошибок на странице нет', errors.length === 0, errors.join('; '));
    await ctx.close();
  }

  await browser.close();
  srv.close();
  console.log(ok ? '\nВСЁ ХОРОШО' : '\nЕСТЬ ОШИБКИ');
  process.exit(ok ? 0 : 1);
})();
