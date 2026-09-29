/* Партнёр не смог перемотать — и утащил за собой того, кто перематывал.
 *
 * Обращение 189 (22–25.09.2026): свой файл mp4 на 3,42 ГБ, одна смотрит с
 * телефона в Яндекс Браузере, другая с компьютера в Chrome. «Перестало давать
 * мотать фильм: каждый раз с начала идёт, либо мотается в конец».
 *
 * Телефон с огромным файлом перематывает долго и не всегда туда: кадр встаёт
 * в начало или в конец. Команду комнаты плеер выполняет под флагом
 * `applying`, но флаг жил 1,5 секунды, а `seeked` на таком файле приходит
 * позже. Тогда телефон рассылал своё неверное время как новую команду, и
 * компьютер прыгал вслед: в начало, а через `pause` в конце файла — в конец.
 *
 * Воспроизводим: у второго зрителя перемотка кончается в нуле и сообщает о
 * себе через 2,5 секунды. Первый перематывает на 30-ю секунду и должен там
 * остаться.
 *
 * Запуск: node pocketbase/pb_public/watch/tests/room-seek-failed.test.js
 * Против прода: node …/room-seek-failed.test.js https://togetherly.day
 */
const { chromium } = require('/home/alelx/.hermes/hermes-agent/node_modules/playwright');
const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..');           // pb_public
const ARG = process.argv[2] || '';
const PORT = 8793;
const PROD = 'https://togetherly.day';
const CLIP = 'https://togetherly.day/watch/tests/clip60.mp4';

const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.png': 'image/png', '.woff2': 'font/woff2',
};

/** Своя копия страницы, а `/api/*` уходит на прод: токен комнаты выдаёт сервер. */
function serve() {
  return new Promise((resolve) => {
    const srv = http.createServer((req, res) => {
      if (req.url.startsWith('/api/')) {
        const body = [];
        req.on('data', (c) => body.push(c));
        req.on('end', () => {
          const up = https.request(PROD + req.url, {
            method: req.method,
            headers: { 'content-type': req.headers['content-type'] || 'application/json' },
          }, (r) => { res.writeHead(r.statusCode, r.headers); r.pipe(res); });
          up.end(Buffer.concat(body));
        });
        return;
      }
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
const at = (page) => page.evaluate(() => {
  const v = document.querySelector('#player video');
  return v ? v.currentTime : -1;
});
const start = (page) => page.evaluate(async () => {
  const v = document.querySelector('#player video');
  try { await v.play(); } catch (_) { /* ещё раз ниже */ }
  return !v.paused;
});

/** Перемотка «ползунком»: касание плеера, потом прыжок — как делает человек. */
const seekByHand = (page, t) => page.evaluate((t) => {
  const v = document.querySelector('#player video');
  v.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true }));
  v.currentTime = t;
}, t);

/** Сценарий: у второго зрителя `seeked` опаздывает на `lateMs`. */
async function scenario(browser, host, lateMs, handPause) {
  const room = (await (await fetch(PROD + '/api/watch/new', { method: 'POST' })).json()).room;
  const a = await (await browser.newContext()).newPage();
  const bCtx = await browser.newContext();
  // Второй зритель — телефон с тяжёлым файлом: перемотка встаёт в начало и
  // отчитывается с опозданием.
  await bCtx.addInitScript((late) => {
    const desc = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'currentTime');
    Object.defineProperty(HTMLMediaElement.prototype, 'currentTime', {
      configurable: true,
      get() { return desc.get.call(this); },
      set(value) { desc.set.call(this, value > 5 ? 0 : value); },
    });
    const add = EventTarget.prototype.addEventListener;
    EventTarget.prototype.addEventListener = function (type, fn, opts) {
      if (this instanceof HTMLMediaElement && type === 'seeked' && typeof fn === 'function') {
        return add.call(this, type, (e) => setTimeout(() => fn.call(this, e), late), opts);
      }
      return add.call(this, type, fn, opts);
    };
  }, lateMs);
  const b = await bCtx.newPage();

  await a.goto(host + '/watch/room/?src=' + encodeURIComponent(CLIP) + '#' + room,
    { waitUntil: 'domcontentloaded' });
  await a.waitForTimeout(5000);
  await b.goto(host + '/watch/room/#' + room, { waitUntil: 'domcontentloaded' });
  await b.waitForTimeout(7000);
  check('ролик у обоих', await a.locator('#player video').count() === 1
    && await b.locator('#player video').count() === 1);

  await start(a);
  await start(b);
  await a.waitForTimeout(3000);

  // Первый перематывает на 30-ю секунду, как это делает человек ползунком.
  await seekByHand(a, 30);
  await a.waitForTimeout(lateMs + 6000);

  const ta = await at(a);
  check(`опоздание ${lateMs / 1000} с: перематывавший остался на своём месте`, ta >= 30,
    't1=' + ta.toFixed(1) + ' t2=' + (await at(b)).toFixed(1));

  if (handPause) {
    // Человек на промахнувшемся телефоне жмёт паузу: партнёр замирает там,
    // куда перемотал, а не в начале фильма.
    await b.evaluate(() => {
      const v = document.querySelector('#player video');
      v.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true }));
      v.pause();
    });
    await a.waitForTimeout(3000);
    const t = await at(a);
    const paused = await a.evaluate(() => document.querySelector('#player video').paused);
    check('пауза с телефона остановила партнёра на его месте', paused && t >= 30,
      't1=' + t.toFixed(1) + ' пауза=' + paused);
  }
  await a.context().close();
  await bCtx.close();
}

(async () => {
  const srv = ARG ? null : await serve();
  const host = ARG || `http://127.0.0.1:${PORT}`;
  const browser = await chromium.launch({
    args: ['--autoplay-policy=no-user-gesture-required', '--mute-audio'],
  });

  await scenario(browser, host, 2500, false);
  // Телефон из обращения отчитывался дольше десяти секунд, и прежняя защита
  // к тому времени уже снималась (жалоба 25.09 после первой правки).
  await scenario(browser, host, 14000, true);

  await browser.close();
  if (srv) srv.close();
  console.log(ok ? '\nВСЁ ХОРОШО' : '\nЕСТЬ ПРОВАЛЫ');
  process.exit(ok ? 0 : 1);
})();
