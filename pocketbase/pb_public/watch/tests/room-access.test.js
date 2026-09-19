/* Кого пускают в комнату и что видит тот, кого не пустили.
 *
 * Вечером 16.09.2026 к паре в `watch:4ejxgjve` пришли двое посторонних: писали
 * в чат, жали паузу, мотали ролик. Сервер выдавал пропуск на любой код, а
 * набранный руками код «создавал» комнату. Теперь сервер отвечает отказом
 * (`not_found`, `auth_required`, `not_member`), и страница обязана показать
 * человеку, что делать дальше, а не «нет связи».
 *
 * Сервер подменяется маршрутами, сокет — заглушкой: проверяется поведение
 * страницы, а не Centrifugo. Живую сторону стережёт
 * `pocketbase/watch_access.test.mjs`.
 *
 * Запуск: node pocketbase/pb_public/watch/tests/room-access.test.js
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
  '.woff2': 'font/woff2',
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

/** Сокет, который «подключается» мгновенно. */
const FAKE_CENTRIFUGE = `
window.__connects = 0;
window.Centrifuge = class {
  constructor() { this._on = {}; window.__connects += 1; }
  on(ev, cb) { (this._on[ev] = this._on[ev] || []).push(cb); return this; }
  connect() { this.state = 'connected'; (this._on.connected || []).forEach((cb) => cb({})); }
  disconnect() {}
  newSubscription() {
    const h = {};
    return {
      on(ev, cb) { (h[ev] = h[ev] || []).push(cb); return this; },
      subscribe() { setTimeout(() => (h.subscribed || []).forEach((cb) => cb({})), 0); },
      unsubscribe() {},
      publish() { return Promise.resolve(); },
      presence() { return Promise.resolve({ clients: {} }); },
    };
  }
};`;

const GRANTED = JSON.stringify({
  ok: true, kind: 'member', userId: 'gaaaaaaaaaaaaaa', channel: 'watch:efgh2345',
  connectionToken: 'т', subscriptionToken: 'т',
});

const deny = (status, error) => ({
  status, contentType: 'application/json', body: JSON.stringify({ ok: false, error }),
});

let ok = true;
function check(name, good, detail) {
  if (!good) ok = false;
  console.log(`  ${good ? '✓' : '✗'} ${name}${good ? '' : ` — ${detail}`}`);
}

async function open(browser, port, { code, init, token }) {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 760 } });
  const page = await ctx.newPage();
  if (init) await page.addInitScript(init);
  await page.addInitScript(() => { try { localStorage.setItem('togetherly.watch.lang', 'ru'); } catch (_) {} });
  await page.route('**/vendor/centrifuge.js', (r) => r.fulfill({
    status: 200, contentType: 'text/javascript; charset=utf-8', body: FAKE_CENTRIFUGE,
  }));
  await page.route('**/analytics.togetherly.day/**', (r) => r.abort());
  const seen = [];
  await page.route('**/api/watch/token', (route) => {
    seen.push(route.request().headers()['authorization'] || '');
    route.fulfill(token(seen));
  });
  await page.goto(`http://127.0.0.1:${port}/watch/room/#${code}`, { waitUntil: 'domcontentloaded' });
  return { ctx, page, seen };
}

const visible = (page, sel) => page.locator(sel).isVisible();

(async () => {
  const srv = await serve();
  const port = srv.address().port;
  const browser = await chromium.launch();

  // 1. Набранный руками код: комнаты нет, есть кнопка завести свою.
  {
    const { ctx, page } = await open(browser, port, {
      code: 'qwerty', token: () => deny(404, 'not_found'),
    });
    await page.waitForSelector('#gate:not([hidden])', { timeout: 4000 }).catch(() => {});
    check('чужой код: экран «комнаты нет»', await visible(page, '#gate'), 'экрана нет');
    const title = (await page.textContent('#gateTitle')) || '';
    check('чужой код: заголовок называет беду', /нет/i.test(title), `«${title}»`);
    check('чужой код: формы входа нет', !(await visible(page, '#gateForm')), 'форма видна');
    check('чужой код: статус не врёт про связь',
      !/Связь|Нет связи/.test((await page.textContent('#status')) || ''), 'статус про связь');

    await page.route('**/api/watch/new', (r) => r.fulfill({
      status: 200, contentType: 'application/json', body: JSON.stringify({ ok: true, room: 'abcdefghjk' }),
    }));
    await Promise.all([
      page.waitForURL(/#abcdefghjk$/, { timeout: 4000 }).catch(() => {}),
      page.click('#gateNew'),
    ]);
    check('чужой код: «создать» ведёт в новую комнату', /#abcdefghjk$/.test(page.url()), page.url());
    await ctx.close();
  }

  // 2. Комната пары без входа: форма и кнопки провайдеров.
  {
    const { ctx, page, seen } = await open(browser, port, {
      code: 'efgh2345', token: () => deny(401, 'auth_required'),
    });
    await page.waitForSelector('#gate:not([hidden])', { timeout: 4000 }).catch(() => {});
    check('пара без входа: экран входа', await visible(page, '#gateForm'), 'формы нет');
    check('пара без входа: есть Google', await visible(page, '[data-provider="google"]'), 'кнопки нет');
    check('пара без входа: сессии не было', seen[0] === '', `ушло «${seen[0]}»`);
    await page.waitForTimeout(2500);
    check('пара без входа: в браузере не долбим сервер', seen.length === 1, `запросов ${seen.length}`);

    // Вход почтой: сессия ложится туда же, куда её кладёт SDK, и уходит серверу.
    await page.unroute('**/api/watch/token');
    await page.route('**/api/watch/token', (route) => {
      const auth = route.request().headers()['authorization'] || '';
      route.fulfill(auth === 'session-1' ? { status: 200, contentType: 'application/json', body: GRANTED } : deny(401, 'auth_required'));
    });
    await page.route('**/api/collections/users/auth-with-password', (r) => r.fulfill({
      status: 200, contentType: 'application/json',
      body: JSON.stringify({ token: 'session-1', record: { id: 'u1', email: 'we@pair.test', collectionName: 'users' } }),
    }));
    await page.fill('#gateEmail', 'we@pair.test');
    await page.fill('#gatePass', 'секрет');
    await page.click('#gateForm button[type="submit"]');
    await page.waitForSelector('#gate', { state: 'hidden', timeout: 5000 }).catch(() => {});
    check('пара: после входа экран уходит', !(await visible(page, '#gate')), 'экран остался');
    await ctx.close();
  }

  // 3. Вошёл, но не в эту пару: говорим, каким аккаунтом он пришёл.
  {
    const stored = JSON.stringify({ token: 'foreign-token', record: { id: 'u9', email: 'other@mail.test' } });
    const { ctx, page, seen } = await open(browser, port, {
      code: 'efgh2345',
      init: `try { localStorage.setItem('pocketbase_auth', ${JSON.stringify(stored)}); } catch (_) {}`,
      token: () => deny(403, 'not_member'),
    });
    await page.waitForSelector('#gate:not([hidden])', { timeout: 4000 }).catch(() => {});
    check('чужая пара: сессия из хранилища ушла серверу', seen[0] === 'foreign-token', `ушло «${seen[0]}»`);
    const text = (await page.textContent('#gateText')) || '';
    check('чужая пара: назван аккаунт', text.includes('other@mail.test'), `«${text}»`);
    check('чужая пара: есть «войти другим»', await visible(page, '#gateOther'), 'кнопки нет');
    await page.click('#gateOther');
    check('чужая пара: «другим» открывает форму', await visible(page, '#gateForm'), 'формы нет');
    const left = await page.evaluate(() => localStorage.getItem('pocketbase_auth'));
    check('чужая пара: прежняя сессия забыта', !left, `осталось ${left}`);
    await ctx.close();
  }

  // 4. Новая сборка приложения кладёт сессию сама — экрана входа нет вовсе.
  {
    const { ctx, page, seen } = await open(browser, port, {
      code: 'efgh2345',
      init: `window.__togetherlyAuth = { token: 'from-app', name: 'Саша' };`,
      token: (s) => (s[s.length - 1] === 'from-app'
        ? { status: 200, contentType: 'application/json', body: GRANTED }
        : deny(401, 'auth_required')),
    });
    await page.waitForTimeout(1200);
    check('приложение: сессия приложения ушла серверу', seen[0] === 'from-app', `ушло «${seen[0]}»`);
    check('приложение: экрана входа нет', !(await visible(page, '#gate')), 'экран виден');
    await ctx.close();
  }

  // 5. Старая сборка: своё подключение приложения поднимается рядом со
  //    страницей, и первые ответы бывают отказом. Страница ждёт, а не пугает.
  {
    const { ctx, page, seen } = await open(browser, port, {
      code: 'efgh2345',
      init: `window.flutter_inappwebview = { callHandler: () => Promise.resolve(null) };`,
      token: (s) => (s.length < 3 ? deny(401, 'auth_required') : { status: 200, contentType: 'application/json', body: GRANTED }),
    });
    await page.waitForTimeout(1000);
    check('старое приложение: пока ждём, экрана входа нет', !(await visible(page, '#gate')), 'экран виден сразу');
    await page.waitForTimeout(5500);
    check('старое приложение: повторил и вошёл', seen.length === 3, `запросов ${seen.length}`);
    check('старое приложение: экрана входа так и нет', !(await visible(page, '#gate')), 'экран виден');
    await ctx.close();
  }

  // 6. Старая сборка, поручиться некому: вход без кнопок провайдеров
  //    (Google во встроенном браузере не пускает).
  {
    const { ctx, page } = await open(browser, port, {
      code: 'efgh2345',
      init: `window.flutter_inappwebview = { callHandler: () => Promise.resolve(null) };`,
      token: () => deny(401, 'auth_required'),
    });
    await page.waitForSelector('#gate:not([hidden])', { timeout: 30000 }).catch(() => {});
    check('старое приложение без места: экран входа', await visible(page, '#gateForm'), 'формы нет');
    check('старое приложение без места: без Google', !(await visible(page, '[data-provider="google"]')), 'кнопка видна');
    await ctx.close();
  }

  // 7. Открытая комната пускает как раньше.
  {
    const { ctx, page } = await open(browser, port, {
      code: 'abcdefghjk',
      token: () => ({ status: 200, contentType: 'application/json', body: GRANTED.replace('member', 'open') }),
    });
    await page.waitForTimeout(1000);
    check('открытая комната: экрана нет', !(await visible(page, '#gate')), 'экран виден');
    const status = (await page.textContent('#status')) || '';
    check('открытая комната: комната готова', /готова/i.test(status), `«${status}»`);
    await ctx.close();
  }

  await browser.close();
  srv.close();
  console.log(ok ? '\nВСЁ СОШЛОСЬ' : '\nЕСТЬ РАСХОЖДЕНИЯ');
  process.exit(ok ? 0 : 1);
})();
