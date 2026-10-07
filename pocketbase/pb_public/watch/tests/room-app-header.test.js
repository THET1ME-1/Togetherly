/* Шапка комнаты в приложении влезает в экран телефона.
 *
 * В приложении у шапки свои «назад» и «поделиться», рядом звонок, тема и
 * «свернуть». На 07.10.2026 ряд просил 429 точек на любом телефоне, и
 * кнопка «свернуть» уезжала за правый край (снимок из приложения, светлая
 * тема). Место освобождалось только во время звонка.
 *
 * Тест расставляет кнопки так, как их включает приложение, и меряет края
 * на 320–412 точках, вне звонка и в разговоре, в обеих темах.
 *
 * Запуск: node pocketbase/pb_public/watch/tests/room-app-header.test.js
 *   BASE=https://togetherly.day — проверить прод вместо локальной копии.
 *   SHOTS=<папка> — снимки шапки.
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
      if (fs.existsSync(file) && fs.statSync(file).isDirectory()) file = path.join(file, 'index.html');
      if (!fs.existsSync(file)) return res.writeHead(404).end('нет');
      res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream' });
      fs.createReadStream(file).pipe(res);
    });
    srv.listen(0, '127.0.0.1', () => resolve(srv));
  });
}

(async () => {
  let srv = null;
  let base = process.env.BASE;
  if (!base) {
    srv = await serve();
    base = `http://127.0.0.1:${srv.address().port}`;
  }
  const shots = process.env.SHOTS;
  const b = await chromium.launch();
  let bad = 0;
  for (const w of [320, 360, 393, 412]) {
    for (const calling of [false, true]) {
      for (const theme of ['light', 'dark']) {
        const ctx = await b.newContext({ viewport: { width: w, height: 800 }, deviceScaleFactor: 2 });
        // Наружу не ходим: шапке сокет не нужен, а чужие скрипты тянут время.
        await ctx.route(/^https?:\/\/(?!127\.0\.0\.1)/, (r) => (base.includes('127.0.0.1') ? r.abort() : r.continue()));
        const p = await ctx.newPage();
        await p.goto(base + '/watch/room/#2x4vhuku');
        await p.waitForTimeout(400);
        const r = await p.evaluate(({ theme, calling }) => {
          document.documentElement.dataset.theme = theme;
          // Так шапку собирает приложение без своей шапки (room.js, app-chrome).
          document.body.classList.add('app-chrome');
          document.querySelector('#back').hidden = false;
          document.querySelector('#share').hidden = false;
          document.querySelector('#voice').hidden = false;
          document.querySelector('#code').textContent = '2x4vhuku';
          if (calling) {
            document.body.classList.add('calling');
            document.querySelector('#voiceCall').hidden = true;
            for (const id of ['voiceState', 'voiceMic', 'voiceHang']) document.getElementById(id).hidden = false;
            document.querySelector('#voiceTime').textContent = '12:34';
          }
          const top = document.querySelector('.top--room');
          const kids = [...top.querySelectorAll('button, .room-code, .voice__state')].filter((e) => {
            const s = getComputedStyle(e);
            return s.display !== 'none' && !e.hidden && e.getBoundingClientRect().width > 0;
          });
          const rects = kids.map((e) => e.getBoundingClientRect());
          const small = kids.filter((e) => e.tagName === 'BUTTON' && e.getBoundingClientRect().height < 40).map((e) => e.id);
          const code = document.querySelector('#code');
          return {
            left: Math.round(Math.min(...rects.map((x) => x.left))),
            right: Math.round(Math.max(...rects.map((x) => x.right))),
            vw: innerWidth,
            small,
            codeCut: code.scrollWidth > code.clientWidth + 1,
            fold: !!document.querySelector('#fold').getBoundingClientRect().width,
          };
        }, { theme, calling });
        const problems = [];
        if (r.left < 0 || r.right > r.vw) problems.push(`края ${r.left}…${r.right} при экране ${r.vw}`);
        if (r.small.length) problems.push(`кнопки ниже 40 точек: ${r.small.join(', ')}`);
        if (r.codeCut) problems.push('код комнаты обрезан');
        if (!r.fold) problems.push('нет кнопки «свернуть»');
        const label = `${w} ${calling ? 'звонок' : 'без звонка'} ${theme}`;
        if (problems.length) {
          bad++;
          console.log(`✗ ${label}: ${problems.join('; ')}`);
        } else {
          console.log(`✓ ${label}: ${r.left}…${r.right} из ${r.vw}`);
        }
        if (shots && theme === 'light') {
          fs.mkdirSync(shots, { recursive: true });
          await p.screenshot({ path: path.join(shots, `top-${w}-${calling ? 'call' : 'idle'}.png`), clip: { x: 0, y: 0, width: w, height: 80 } });
        }
        await ctx.close();
      }
    }
  }
  await b.close();
  if (srv) srv.close();
  console.log(bad ? `Провалов: ${bad}` : 'Шапка влезает везде');
  process.exit(bad ? 1 : 0);
})();
