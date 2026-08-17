/* Комната не зависит от одного адреса сокета.
 *
 * Вечер 15.08.2026: три жалобы подряд — «не работает интерфейс во время
 * совместного просмотра», «нас просто не закидывает в одну комнату», «не
 * получается запустить скачанное видео» (на снимке — комната, чат, «вы один»).
 * Причина одна и не в комнате: перегруженный Caddy не мог открыть соединение
 * к Centrifugo (`dial tcp 127.0.0.1:8443: i/o timeout`), при этом статику
 * отдавал — страница открывалась, а сокет нет. Прямой адрес в это же время
 * отвечал мгновенно.
 *
 * Теперь адресов два, и клиент перебирает их сам. Проверяется это в настоящем
 * браузере: вне его WebSocket на отказ соединения не присылает `close`, и
 * перебор не трогается с места — проверка в node сказала бы неправду.
 *
 * Запуск: node pocketbase/pb_public/watch/tests/room-ws-endpoints.test.js
 */
const { chromium } = require('/home/alelx/.hermes/hermes-agent/node_modules/playwright');
const fs = require('fs');
const http = require('http');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..');           // pb_public
const BASE = process.argv[2] || 'https://togetherly.day';
const PORT = 8792;
const ROOM = 'wsfb' + Math.random().toString(36).slice(2, 8);

/* Локальная статика: нужна только чтобы у страницы был origin и с неё
 * подгрузился тот самый vendor/centrifuge.js, что грузит комната. */
function serve() {
  return new Promise((resolve) => {
    const srv = http.createServer((req, res) => {
      const p = decodeURIComponent(req.url.split('?')[0]);
      if (p === '/') {
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        res.end('<!doctype html><meta charset="utf-8"><title>ws</title>');
        return;
      }
      const file = path.join(ROOT, p);
      if (!file.startsWith(ROOT) || !fs.existsSync(file)) { res.writeHead(404); res.end(); return; }
      res.writeHead(200, { 'Content-Type': 'text/javascript; charset=utf-8' });
      res.end(fs.readFileSync(file));
    });
    srv.listen(PORT, '127.0.0.1', () => resolve(srv));
  });
}

/* Адреса, объявленные самой комнатой: тест обязан проверять их, а не свои. */
function endpointsFromRoomJs() {
  const src = fs.readFileSync(path.join(__dirname, '..', 'room', 'room.js'), 'utf8');
  return [...src.matchAll(/endpoint:\s*'(wss:\/\/[^']+)'/g)].map((m) => m[1]);
}

(async () => {
  let ok = true;
  const check = (name, cond, extra = '') => {
    console.log((cond ? '  ✓ ' : '  ✗ ') + name, extra);
    if (!cond) ok = false;
  };

  const endpoints = endpointsFromRoomJs();

  console.log('1. комната объявляет запасной адрес');
  check('адресов больше одного', endpoints.length > 1, endpoints.join(' , '));
  check('первый — прямой, мимо прокси', /:8443\//.test(endpoints[0]), endpoints[0] || '');
  // Своё имя вместо служебного поддомена динамического DNS (17.08.2026):
  // адрес комнаты человек видит в строке браузера.
  check(
    'никаких чужих поддоменов в адресах',
    endpoints.every((e) => !/duckdns/.test(e)),
    endpoints.filter((e) => /duckdns/.test(e)).join(' , ') || 'чисто'
  );

  console.log('2. токен на комнату');
  const res = await fetch(BASE + '/api/watch/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ room: ROOM, guest: 'test-' + ROOM }),
  });
  const data = await res.json();
  check('сервер выдал токен', !!data.ok, data.error || '');
  if (!data.ok) process.exit(1);

  const srv = await serve();
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.goto(`http://127.0.0.1:${PORT}/`, { waitUntil: 'domcontentloaded' });
  await page.addScriptTag({ url: `http://127.0.0.1:${PORT}/watch/vendor/centrifuge.js` });

  const connect = (list) => page.evaluate(
    ([endpoints, token]) => new Promise((resolve) => {
      const c = new Centrifuge(endpoints, { token });
      const timer = setTimeout(() => { try { c.disconnect(); } catch (e) {} resolve(false); }, 20000);
      c.on('connected', () => { clearTimeout(timer); c.disconnect(); resolve(true); });
      c.on('error', () => {});
      c.connect();
    }),
    [list, data.connectionToken],
  );

  console.log('3. каждый адрес поднимает соединение сам по себе');
  for (const e of endpoints) {
    check(e, await connect([{ transport: 'websocket', endpoint: e }]));
  }

  console.log('4. мёртвый первым — соединение встаёт по запасному');
  const dead = { transport: 'websocket', endpoint: 'wss://127.0.0.1:1/connection/websocket' };
  check(
    'перебор дошёл до живого адреса',
    await connect([dead, ...endpoints.map((e) => ({ transport: 'websocket', endpoint: e }))]),
  );

  await browser.close();
  srv.close();
  console.log(ok ? '\nВСЁ ХОРОШО' : '\nЕСТЬ ОШИБКИ');
  process.exit(ok ? 0 : 1);
})();
