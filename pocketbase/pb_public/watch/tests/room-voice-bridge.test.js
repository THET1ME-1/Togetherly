/* Голос живёт в самой комнате, а звонок поднимает приложение.
 *
 * До 20.08.2026 кнопку звонка рисовал Flutter полосой под WebView: светлая
 * панель Material под тёмной комнатой, чужой радиус, чужой шрифт — стык видно
 * на любом снимке. Вдобавок полоса выезжала через секунду после открытия и
 * отрезала у страницы 84 точки, из-за чего нижний ряд уезжал за край на
 * айфонах.
 *
 * Теперь кнопка стоит в шапке комнаты и красится её токенами, а приложение
 * получает нажатие мостом `flutter_inappwebview` и возвращает состояние
 * вызовом `window.watchVoiceState`. В обычном браузере моста нет — и кнопки
 * тоже: поднимать связь там некому.
 *
 * Запуск: node pocketbase/pb_public/watch/tests/room-voice-bridge.test.js
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

/** Подставляет мост приложения до загрузки страницы и копит вызовы. */
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
  const url = `http://127.0.0.1:${port}/watch/room/#voice1`;
  const browser = await chromium.launch();
  let ok = true;
  const check = (name, cond, extra = '') => {
    console.log((cond ? '  ✓ ' : '  ✗ ') + name + (extra ? '  ' + extra : ''));
    if (!cond) ok = false;
  };

  const open = async ({ withBridge }) => {
    const ctx = await browser.newContext({
      viewport: { width: 393, height: 700 },
      deviceScaleFactor: 3,
      isMobile: true,
      hasTouch: true,
    });
    const page = await ctx.newPage();
    if (withBridge) await page.addInitScript(APP_BRIDGE);
    await page.route('**/api/watch/token', (route) => route.fulfill({
      status: 500, contentType: 'application/json', body: '{"ok":false}',
    }));
    await page.goto(url, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(700);
    return { ctx, page };
  };

  console.log('\n1. Браузер без приложения: звонить нечем');
  {
    const { ctx, page } = await open({ withBridge: false });
    const shown = await page.isVisible('#voice');
    check('кнопки голоса нет', shown === false);
    await ctx.close();
  }

  console.log('\n2. Сборка постарше: мост есть, про звонок из страницы не знает');
  {
    const { ctx, page } = await open({ withBridge: true });
    check('кнопки нет, пока приложение не отозвалось', (await page.isVisible('#voice')) === false);
    await ctx.close();
  }

  console.log('\n3. В приложении: кнопка в шапке, нажатие уходит в мост');
  {
    const { ctx, page } = await open({ withBridge: true });
    // Приложение здоровается состоянием сразу после загрузки страницы.
    await page.evaluate(() => window.watchVoiceState({ state: 'off' }));
    await page.waitForTimeout(150);
    check('кнопка видна', await page.isVisible('#voiceCall'));

    const box = await page.locator('#voiceCall').boundingBox();
    check('палец попадает: не меньше 40 точек',
      box && box.width >= 40 && box.height >= 40,
      box ? `${Math.round(box.width)}×${Math.round(box.height)}` : 'нет кнопки');

    await page.click('#voiceCall');
    const calls = await page.evaluate(() => window.__calls);
    check('приложению ушёл вызов watchVoice',
      calls.length === 1 && calls[0].name === 'watchVoice'
      && calls[0].args[0] && calls[0].args[0].action === 'call',
      JSON.stringify(calls));

    console.log('\n4. Приложение отвечает состоянием — шапка переключается');
    await page.evaluate(() => window.watchVoiceState({ state: 'connecting' }));
    await page.waitForTimeout(150);
    check('ждём ответа: кнопка стала отбоем', await page.isVisible('#voiceHang'));

    await page.evaluate(() => window.watchVoiceState({ state: 'live', micOn: true }));
    await page.waitForTimeout(1200);
    const live = await page.evaluate(() => ({
      time: document.querySelector('#voiceTime').textContent,
      mic: !document.querySelector('#voiceMic').hidden,
      call: !document.querySelector('#voiceCall').hidden,
    }));
    check('идёт счёт времени', /^\d+:\d\d$/.test(live.time), live.time);
    check('появился микрофон', live.mic);
    check('кнопки «позвонить» больше нет', live.call === false);

    await page.click('#voiceMic');
    await page.click('#voiceHang');
    const after = await page.evaluate(() => window.__calls.map((c) => c.args[0].action));
    check('микрофон и отбой доехали до приложения',
      after.join(',') === 'call,mic,hangup', after.join(','));

    await page.evaluate(() => window.watchVoiceState({ state: 'off' }));
    await page.waitForTimeout(150);
    check('после отбоя шапка вернулась в покой',
      (await page.isVisible('#voiceCall')) && !(await page.isVisible('#voiceHang')));

    console.log('\n5. Отказ связи виден человеку');
    await page.evaluate(() => window.watchVoiceState({ state: 'failed' }));
    await page.waitForTimeout(150);
    const failed = await page.textContent('#voiceState');
    check('сказано словами, а не значком', (failed || '').trim().length > 0, failed);

    await ctx.close();
  }

  await browser.close();
  srv.close();
  console.log(ok ? '\nВСЁ СОШЛОСЬ' : '\nЕСТЬ РАСХОЖДЕНИЯ');
  process.exit(ok ? 0 : 1);
})();
