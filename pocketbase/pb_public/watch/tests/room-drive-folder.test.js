/* Ссылка на папку Google Диска вместо файла.
 *
 * Обращение 141 (07.09.2026): «Видео, что через гугл диск, что через файлы не
 * запускается». На снимке в поле стоит drive.google.com/drive/folders/… — это
 * папка, плеера у неё нет. Комната отвечала общим «Такую ссылку не открыть» и
 * тут же перечисляла Google Drive среди годных: человек не понимал, что не так.
 *
 * Запуск: node pocketbase/pb_public/watch/tests/room-drive-folder.test.js
 */
const { chromium } = require('/home/alelx/.hermes/hermes-agent/node_modules/playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..');           // pb_public
const ARG = process.argv[2] || '';
const PORT = 8793;

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

async function statusFor(ctx, base, typed, tag) {
  const p = await ctx.newPage();
  await p.goto(base + '#' + tag, { waitUntil: 'domcontentloaded' });
  await p.waitForFunction(() => {
    const el = document.querySelector('#code');
    return !!el && el.textContent.trim().length > 0;
  }, null, { timeout: 15000 });
  await p.waitForTimeout(1200);
  await p.fill('#link', typed);
  await p.click('#apply');
  await p.waitForTimeout(800);
  const status = (await p.textContent('#status')) || '';
  const note = (await p.textContent('#note').catch(() => '')) || '';
  await p.close();
  return { status, note };
}

(async () => {
  const srv = ARG ? null : await serve();
  const base = (ARG || `http://127.0.0.1:${PORT}`) + '/watch/room/';
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true });

  console.log('1. папка Диска: комната говорит, что нужен сам файл');
  for (const [name, typed] of [
    ['папка', 'https://drive.google.com/drive/folders/1AbCdEfGhIjKlMnOp?usp=sharing'],
    ['папка в чужом аккаунте', 'https://drive.google.com/drive/u/1/folders/1AbCdEfGhIjKlMnOp'],
  ]) {
    const { status, note } = await statusFor(ctx, base, typed, 'folder-' + name.length);
    check(name, /папк/i.test(status) && /файл/i.test(status), JSON.stringify(status));
    check('   видно и на телефоне', /папк/i.test(note), JSON.stringify(note));
  }

  console.log('2. ссылка на файл Диска по-прежнему включается');
  {
    const p = await ctx.newPage();
    await p.goto(base + '#drive-file', { waitUntil: 'domcontentloaded' });
    await p.waitForFunction(() => {
      const el = document.querySelector('#code');
      return !!el && el.textContent.trim().length > 0;
    }, null, { timeout: 15000 });
    await p.waitForTimeout(1200);
    await p.fill('#link', 'https://drive.google.com/file/d/1AbCdEfGhIjKlMnOp/view?usp=sharing');
    await p.click('#apply');
    await p.waitForTimeout(1200);
    const frame = await p.getAttribute('#frame', 'src').catch(() => null);
    check('файл', !!frame && /drive\.google\.com\/file\/d\/1AbCdEfGhIjKlMnOp\/preview/.test(frame), frame || '(плеер не встал)');
    await p.close();
  }

  await browser.close();
  if (srv) srv.close();
  console.log(ok ? '\nВСЁ ХОРОШО' : '\nЕСТЬ ПРОВАЛЫ');
  process.exit(ok ? 0 : 1);
})();
