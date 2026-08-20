/* «Смотрят: 2», хотя человек в комнате один.
 *
 * Жалоба 20.08.2026 со снимком: зашёл один, а комната пишет двоих. Проверено на
 * живом Centrifugo — в канале `watch:2x4vhuku` действительно два клиента:
 * `g7ax98j3u0yoy4p` (страница) и `ufge0IwvR4RehZ9TgKijm5xc9C32` (аккаунт
 * приложения). Второй — не зритель: экран комнаты поднимает своё подключение к
 * тому же каналу ради голосового сигналинга (WebRTC живёт в приложении, а зов
 * партнёра ходит по каналу комнаты), и делает это всегда, даже когда никто не
 * звонит. Страница считала людей по уникальным `user` и записывала служебное
 * подключение в зрители.
 *
 * Подключение приложения помечено в `chan_info` подписки (выдаёт
 * `centrifugo.pb.js`), и метка эта серверная: чинит и уже выпущенные сборки.
 *
 * Присутствие подсовываем заглушкой вместо vendor/centrifuge.js: проверяется
 * счёт людей, а не работа сокета.
 *
 * Запуск: node pocketbase/pb_public/watch/tests/room-viewers-count.test.js
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

/** Клиент страницы: гостю сервер выдаёт имя вида g + 14 знаков. */
const page1 = { client: 'c1', user: 'g7ax98j3u0yoy4p' };
const page2 = { client: 'c2', user: 'gvv31k9zzt8ep2b' };
/** Клиент приложения: сидит в канале ради голоса, зрителем не считается. */
const app1 = { client: 'c3', user: 'ufge0IwvR4RehZ9TgKijm5xc9C32', chan_info: { app: 1 } };
const app2 = { client: 'c4', user: 'w2ddnrlbhllzz40', chan_info: { app: 1 } };

const CASES = [
  ['один человек, комната открыта в приложении', [page1, app1], 'вы один'],
  ['один человек, вкладка в браузере', [page1], 'вы один'],
  ['один человек, старое соединение ещё не отвалилось',
    [page1, { client: 'c9', user: page1.user }], 'вы один'],
  ['двое, оба в приложении', [page1, app1, page2, app2], 'смотрят: 2'],
  ['двое: приложение и браузер', [page1, app1, page2], 'смотрят: 2'],
];

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

/** Centrifuge, который ничего не соединяет, зато отдаёт заданное присутствие. */
const FAKE_CENTRIFUGE = `
window.Centrifuge = class {
  constructor() { this._on = {}; }
  on(ev, cb) { (this._on[ev] = this._on[ev] || []).push(cb); return this; }
  connect() { (this._on.connected || []).forEach((cb) => cb({})); }
  disconnect() {}
  newSubscription() {
    const handlers = {};
    return {
      on(ev, cb) { (handlers[ev] = handlers[ev] || []).push(cb); return this; },
      subscribe() {
        setTimeout(() => (handlers.subscribed || []).forEach((cb) => cb({})), 0);
      },
      unsubscribe() {},
      publish() { return Promise.resolve(); },
      presence() {
        const clients = {};
        (window.__presence || []).forEach((c) => {
          clients[c.client] = Object.assign({}, c);
          if (c.chan_info) clients[c.client].chanInfo = c.chan_info;
        });
        return Promise.resolve({ clients: clients });
      },
    };
  }
};`;

(async () => {
  const srv = await serve();
  const port = srv.address().port;
  const browser = await chromium.launch();
  let ok = true;

  for (const [name, presence, expected] of CASES) {
    const ctx = await browser.newContext({ viewport: { width: 393, height: 703 } });
    const page = await ctx.newPage();

    await page.addInitScript(`window.__presence = ${JSON.stringify(presence)};`);
    await page.route('**/vendor/centrifuge.js', (route) => route.fulfill({
      status: 200, contentType: 'text/javascript; charset=utf-8', body: FAKE_CENTRIFUGE,
    }));
    await page.route('**/api/watch/token', (route) => route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        ok: true,
        userId: page1.user,
        channel: 'watch:viewers1',
        connectionToken: 'т',
        subscriptionToken: 'т',
      }),
    }));

    await page.goto(`http://127.0.0.1:${port}/watch/room/#viewers1`, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(1200);

    const shown = (await page.textContent('#viewers') || '').trim();
    const good = shown === expected;
    if (!good) ok = false;
    console.log(`  ${good ? '✓' : '✗'} ${name}: «${shown}»${good ? '' : `, ждали «${expected}»`}`);

    await ctx.close();
  }

  await browser.close();
  srv.close();
  console.log(ok ? '\nВСЁ СОШЛОСЬ' : '\nЕСТЬ РАСХОЖДЕНИЯ');
  process.exit(ok ? 0 : 1);
})();
