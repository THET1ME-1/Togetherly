/* Комната в нативном окне приложения (iPhone, адрес с `nb=1`).
 *
 * Встроенный браузер на iPhone терял касания у каждого четвёртого, поэтому
 * доле людей приложение открывает комнату своим нативным окном во весь экран.
 * Странице от этого нужно три вещи:
 *   1. отступить от выреза экрана: окно идёт под строку состояния, а раньше
 *      место под неё оставлял экран приложения;
 *   2. уметь показать сообщение приложения (`window.roomNote`): плашку Flutter
 *      под нативным окном не видно;
 *   3. передать в замер касаний сборку и вид окна — иначе новое окно не
 *      сравнить со старым.
 *
 * Запуск: node pocketbase/pb_public/watch/tests/room-native-window.test.js
 */
const { chromium } = require('/home/alelx/.hermes/hermes-agent/node_modules/playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..');           // pb_public
const PORT = 8811;

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

// Страница во встроенном браузере приложения, которое убрало свою шапку.
const STUB = `
  window.flutter_inappwebview = { callHandler: () => Promise.resolve(null) };
  window.__togetherlyChrome = 1;
  window.__events = [];
  Object.defineProperty(window, 'umami', { value: { track: (n, d) => window.__events.push([n, d]) }, writable: false });
`;

async function open(ctx, query, tag) {
  const p = await ctx.newPage();
  await p.addInitScript(STUB);
  await p.goto(`http://127.0.0.1:${PORT}/watch/room/${query}#${tag}`, { waitUntil: 'domcontentloaded' });
  await p.waitForFunction(() => {
    const el = document.querySelector('#code');
    return !!el && el.textContent.trim().length > 0;
  }, null, { timeout: 15000 });
  return p;
}

(async () => {
  const srv = await serve();
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, isMobile: true, hasTouch: true });
  try {
    console.log('1. нативное окно: шапка отступает от выреза экрана');
    {
      const p = await open(ctx, '?nb=1&b=250&name=Test', 'nw-inset');
      // Отступы приложение сообщает само — тем же скриптом, что ленте.
      await p.evaluate(() => document.documentElement.style.setProperty('--app-top', '59px'));
      const m = await p.evaluate(() => ({
        cls: document.documentElement.classList.contains('native-window'),
        pad: getComputedStyle(document.body).paddingTop,
        back: document.querySelector('#back').getBoundingClientRect().top,
        bodyH: document.body.getBoundingClientRect().height,
        composer: document.querySelector('#message').getBoundingClientRect().bottom,
      }));
      check('страница знает, что она в нативном окне', m.cls);
      check('отступ сверху равен вырезу', m.pad === '59px', m.pad);
      check('кнопка «назад» ниже выреза', m.back >= 59, String(m.back));
      check('комната по-прежнему во весь экран, поле ввода внутри него', m.bodyH <= 852.5 && m.composer <= 852.5,
        `${m.bodyH} / ${m.composer}`);
      await p.close();
    }
    console.log('2. экран у двери в нативном окне тоже ниже выреза');
    {
      const p = await open(ctx, '?nb=1', 'nw-gate');
      await p.evaluate(() => {
        document.documentElement.style.setProperty('--app-top', '59px');
        document.querySelector('#gate').hidden = false;
      });
      const pad = await p.evaluate(() => parseFloat(getComputedStyle(document.querySelector('#gate')).paddingTop));
      check('у двери отступ не меньше выреза', pad >= 59, String(pad));
      await p.close();
    }
    console.log('3. встроенное окно: отступа нет, как раньше');
    {
      const p = await open(ctx, '?name=Test', 'nw-embedded');
      const m = await p.evaluate(() => ({
        cls: document.documentElement.classList.contains('native-window'),
        pad: getComputedStyle(document.body).paddingTop,
      }));
      check('метки окна нет', !m.cls);
      check('отступа сверху нет', m.pad === '0px', m.pad);
      await p.close();
    }
    console.log('4. сообщение приложения показывает сама страница');
    {
      const p = await open(ctx, '?nb=1', 'nw-note');
      const has = await p.evaluate(() => typeof window.roomNote === 'function');
      check('window.roomNote есть', has);
      if (has) {
        await p.evaluate(() => window.roomNote('Нажмите ещё раз, чтобы выйти'));
        const note = await p.evaluate(() => {
          const el = document.querySelector('#note');
          return { hidden: el.hidden, text: el.textContent };
        });
        check('плашка видна и с тем же текстом', !note.hidden && note.text === 'Нажмите ещё раз, чтобы выйти',
          JSON.stringify(note));
      }
      await p.close();
    }
    console.log('5. замер касаний несёт сборку и вид окна');
    {
      const p = await open(ctx, '?nb=1&b=250', 'nw-probe');
      await p.tap('#link');
      await p.waitForTimeout(600);
      const ev = await p.evaluate(() => window.__events.filter((e) => e[0] === 'room-touch'));
      const d = (ev[0] || [])[1] || {};
      check('сборка в замере', d.b === 250, JSON.stringify(d));
      check('вид окна в замере', d.nb === 1, JSON.stringify(d));
      await p.close();
    }
    console.log('6. сборка постарше: меток нет, в замере нули');
    {
      const p = await open(ctx, '', 'nw-old');
      await p.tap('#link');
      await p.waitForTimeout(600);
      const ev = await p.evaluate(() => window.__events.filter((e) => e[0] === 'room-touch'));
      const d = (ev[0] || [])[1] || {};
      check('сборка неизвестна — ноль', d.b === 0, JSON.stringify(d));
      check('окно встроенное — ноль', d.nb === 0, JSON.stringify(d));
      await p.close();
    }
  } finally {
    await browser.close();
    srv.close();
  }
  console.log(ok ? 'ВСЁ ХОРОШО' : 'ЕСТЬ ПРОВАЛЫ');
  process.exit(ok ? 0 : 1);
})();
