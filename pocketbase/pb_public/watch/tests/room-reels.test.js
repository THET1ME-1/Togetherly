/* Ленты вдвоём: очередь по ходам, реакции, пауза и чат у двоих.
 *
 * Два браузера тестовой пары (вход — ~/keys/togetherly-test-pair.txt), у
 * каждого своя «лента»: мост приложения подменён заглушкой, которая отдаёт
 * номера настоящих Shorts. Номера собираются с m.youtube.com тем же
 * перехватом `reel_watch_sequence`, что и в приложении.
 *
 * Запуск: node pocketbase/pb_public/watch/tests/room-reels.test.js
 * Снимки: build/reels/*.png
 */
const { chromium } = require('/home/alelx/.hermes/hermes-agent/node_modules/playwright');
const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..');
const PORT = 8796;
const PROD = 'https://togetherly.day';
const OUT = path.join(__dirname, '..', '..', '..', '..', 'build', 'reels');
const PAIR = 'r5269c54ac34919';

function creds() {
  const t = fs.readFileSync(path.join(process.env.HOME, 'keys/togetherly-test-pair.txt'), 'utf8');
  const m = [...t.matchAll(/(claude-test-231[ab]@togetherly\.day) \/ (\S+)/g)];
  return m.map((x) => ({ email: x[1], password: x[2] }));
}

function api(p, body, token) {
  return fetch(PROD + p, {
    method: 'POST',
    headers: Object.assign({ 'Content-Type': 'application/json' }, token ? { Authorization: token } : {}),
    body: JSON.stringify(body),
  }).then((r) => r.json());
}

function serve() {
  return new Promise((resolve) => {
    const srv = http.createServer((req, res) => {
      if (req.url.startsWith('/api/')) {
        const body = [];
        req.on('data', (c) => body.push(c));
        req.on('end', () => {
          const h = { 'content-type': req.headers['content-type'] || 'application/json' };
          if (req.headers.authorization) h.authorization = req.headers.authorization;
          const up = https.request(PROD + req.url, { method: req.method, headers: h },
            (r) => { res.writeHead(r.statusCode, r.headers); r.pipe(res); });
          up.end(Buffer.concat(body));
        });
        return;
      }
      let p = decodeURIComponent(req.url.split('?')[0].split('#')[0]);
      if (p.endsWith('/')) p += 'index.html';
      const file = path.join(ROOT, p);
      if (!file.startsWith(ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
        res.writeHead(404); res.end(); return;
      }
      const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.woff2': 'font/woff2' };
      res.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream' });
      res.end(fs.readFileSync(file));
    });
    srv.listen(PORT, '127.0.0.1', () => resolve(srv));
  });
}

/** Настоящие номера Shorts — тем же перехватом, что в приложении. */
async function harvest(browser) {
  const ctx = await browser.newContext({ userAgent: 'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Mobile Safari/537.36', viewport: { width: 393, height: 852 } });
  const page = await ctx.newPage();
  const ids = new Set();
  page.on('response', async (r) => {
    if (!/reel_watch_sequence/.test(r.url())) return;
    try { for (const m of (await r.text()).matchAll(/"videoId":"([A-Za-z0-9_-]{11})"/g)) ids.add(m[1]); } catch (_) {}
  });
  await page.goto('https://m.youtube.com/shorts/', { timeout: 60000 }).catch(() => {});
  await page.waitForTimeout(8000);
  await ctx.close();
  return [...ids];
}

let ok = true;
const check = (n, c, x = '') => { console.log((c ? '  ✓ ' : '  ✗ ') + n, x); if (!c) ok = false; };

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const [a, b] = creds();
  const authA = await api('/api/collections/users/auth-with-password', { identity: a.email, password: a.password });
  const authB = await api('/api/collections/users/auth-with-password', { identity: b.email, password: b.password });
  const room = (await api('/api/watch/room', { groupId: PAIR }, authA.token)).room;
  check('код комнаты пары', !!room, room);

  const srv = await serve();
  const browser = await chromium.launch({ args: ['--autoplay-policy=no-user-gesture-required'] });
  const ids = await harvest(browser);
  check('лента Shorts собрана', ids.length >= 6, ids.length + ' номеров');
  const feedA = ids.filter((_, i) => i % 2 === 0);
  const feedB = ids.filter((_, i) => i % 2 === 1);

  const open = async (auth, name, feed) => {
    const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, deviceScaleFactor: 2, hasTouch: true, locale: 'ru-RU' });
    await ctx.addInitScript(({ token, name, feed }) => {
      window.__togetherlyAuth = { token, name };
      window.__feedCalls = [];
      window.flutter_inappwebview = {
        callHandler: async (h, arg) => {
          window.__feedCalls.push([h, arg]);
          if (h === 'reelsFeed') return feed.splice(0, (arg && arg.need) || 8);
          return null;
        },
      };
    }, { token: auth.token, name, feed: feed.slice() });
    const page = await ctx.newPage();
    page.on('pageerror', (e) => console.log('  [ошибка ' + name + ']', e.message));
    await page.goto(`http://127.0.0.1:${PORT}/watch/room/?reels=1&name=${encodeURIComponent(name)}#${room}`);
    return page;
  };

  const pa = await open(authA, 'Аня', feedA);
  await pa.waitForTimeout(4000);
  const pb = await open(authB, 'Боря', feedB);
  await pa.waitForTimeout(6000);

  const cur = (p) => p.evaluate(() => {
    const st = window.__reelsState();
    return Object.assign(st, { id: st.cur && st.cur.id, pill: document.querySelector('.rl-pill b').textContent });
  });
  const playing = (p) => p.evaluate(() => {
    const st = window.__reelsState();
    return st.cur ? st.cur.id : '';
  });

  await pa.screenshot({ path: path.join(OUT, '1-ania.png') });
  await pb.screenshot({ path: path.join(OUT, '1-boria.png') });
  const s1a = await cur(pa), s1b = await cur(pb);
  console.log('   Аня:', s1a, '\n   Боря:', s1b);
  check('у обоих играет ролик', !!(await playing(pa)) && !!(await playing(pb)));
  check('ход виден у обоих по-разному', s1a.pill !== s1b.pill, s1a.pill + ' / ' + s1b.pill);

  // Свайп вверх у Ани.
  const swipe = async (p) => {
    await p.mouse.move(196, 600); await p.mouse.down();
    await p.mouse.move(196, 450, { steps: 4 }); await p.mouse.move(196, 300, { steps: 4 });
    await p.mouse.up();
  };
  const before = await playing(pb);
  // Ход переходит, только если у партнёра есть что показать; иначе листаем
  // свою ленту — это тоже верно, но проверять тогда нечего.
  const partnerHas = (await cur(pa)).theirs > 0 && s1a.pill === 'Твоя лента';
  check('подсказки про свайп нет', await pa.evaluate(() => !document.querySelector('.rl-hint')));
  check('на месте «назад» — обновление рекомендаций', await pa.isVisible('.rl-refresh'));
  // Следующий ролик уже ждёт под экраном — свайп не грузит его с нуля.
  // Закрытый для встраивания ролик под экраном заменяется следующим — даём
  // на это пару секунд.
  const hasNext = await pa.waitForFunction(() => Array.from(document.querySelectorAll('.rl-card')).some((c) => c.getBoundingClientRect().top >= 800), null, { timeout: 6000 }).then(() => true, () => false);
  check('следующий ролик загружен заранее', hasNext);
  // Посреди свайпа видны оба ролика: текущий уехал вверх, следующий выехал.
  await pa.mouse.move(196, 600); await pa.mouse.down();
  await pa.mouse.move(196, 420, { steps: 6 });
  await pa.waitForTimeout(150);
  const mid = await pa.evaluate(() => Array.from(document.querySelectorAll('.rl-card')).map((c) => Math.round(c.getBoundingClientRect().top)));
  await pa.screenshot({ path: path.join(OUT, '2-drag.png') });
  check('ролик едет за пальцем', mid.some((t) => t < -100) && mid.some((t) => t > 300 && t < 852), mid.join(', '));
  await pa.mouse.move(196, 300, { steps: 3 });
  await pa.mouse.up();
  await pa.waitForTimeout(2500);
  const s2a = await cur(pa), s2b = await cur(pb);
  console.log('   после свайпа Аня:', s2a, '\n   Боря:', s2b);
  check('свайп Ани сменил ролик у Бори', (await playing(pb)) !== before);
  if (partnerHas) check('ход перешёл', s2a.pill !== s1a.pill, s1a.pill + ' → ' + s2a.pill);
  else check('ролик из ленты того, кто ещё не показывал', s2a.pill !== s1a.pill || s2a.theirs === 0, s1a.pill + ' → ' + s2a.pill);
  await pa.screenshot({ path: path.join(OUT, '2-ania.png') });

  // Назад: прошлый ролик лежит над экраном и выезжает за пальцем сверху.
  // Следующего может и не быть (очередь партнёра кончилась) — смотрим именно
  // на карточку над экраном.
  check('прошлый ролик ждёт над экраном', await pa.evaluate(() => Array.from(document.querySelectorAll('.rl-card')).some((c) => c.getBoundingClientRect().bottom <= 1)));
  await pa.mouse.move(196, 250); await pa.mouse.down();
  await pa.mouse.move(196, 450, { steps: 6 });
  await pa.waitForTimeout(150);
  const midBack = await pa.evaluate(() => Array.from(document.querySelectorAll('.rl-card')).map((c) => Math.round(c.getBoundingClientRect().top)));
  await pa.screenshot({ path: path.join(OUT, '2-back-drag.png') });
  check('назад тоже едет за пальцем', midBack.some((t) => t < 0 && t > -700) && midBack.some((t) => t > 150 && t < 260), midBack.join(', '));
  await pa.mouse.move(196, 600, { steps: 3 });
  await pa.mouse.up();
  await pa.waitForTimeout(1500);
  check('свайп вниз вернул прошлый ролик', (await cur(pa)).id === s1a.id, (await cur(pa)).id + ' / ' + s1a.id);
  check('у Бори тоже вернулся', (await cur(pb)).id === s1a.id);
  // Снова вперёд, чтобы дальше всё шло как было.
  await swipe(pa);
  await pa.waitForTimeout(2000);

  // Реакция: Аня открывает выбор и ставит 😂, у Бори всплывает.
  await pa.click('.rl-react');
  await pa.waitForTimeout(300);
  check('выбор реакции открылся', await pa.isVisible('.rl-pick'));
  await pa.screenshot({ path: path.join(OUT, '3-pick.png') });
  await pa.click('.rl-pick button:nth-child(2)');
  await pb.waitForTimeout(700);
  check('реакция всплыла у Бори', await pb.isVisible('.rl-pop'));
  await pb.screenshot({ path: path.join(OUT, '3-boria-pop.png') });
  await pb.click('.rl-react');
  await pb.waitForTimeout(250);
  await pb.click('.rl-pick button:nth-child(2)');
  await pb.waitForTimeout(400);
  check('совпадение у Бори', await pb.isVisible('.rl-match'));
  await pb.screenshot({ path: path.join(OUT, '4-match.png') });

  // Чат. Пустое поле — отправка приглушена и не нажимается; с текстом поле
  // красится как своя реплика, кнопка оживает; после отправки — снова пусто.
  check('пустое поле: отправка выключена', await pb.evaluate(() => document.querySelector('.rl-send').disabled));
  await pb.fill('.rl-input', 'ахаха смотри');
  const typing = await pb.evaluate(() => ({
    on: document.querySelector('.rl').classList.contains('is-typing'),
    send: !document.querySelector('.rl-send').disabled,
    bg: getComputedStyle(document.querySelector('.rl-compose')).backgroundColor,
  }));
  check('с текстом поле красится как реплика, отправка включена', typing.on && typing.send && /255, 126, 155/.test(typing.bg), JSON.stringify(typing));
  await pb.waitForTimeout(500);
  await pb.screenshot({ path: path.join(OUT, '4b-typing.png') });
  await pb.click('.rl-send');
  check('после отправки поле пустое, кнопка снова выключена', await pb.evaluate(() =>
    !document.querySelector('.rl-input').value && document.querySelector('.rl-send').disabled && !document.querySelector('.rl').classList.contains('is-typing')));
  await pa.waitForTimeout(900);
  const feedText = await pa.evaluate(() => document.querySelector('.rl-feed').textContent);
  check('реплика Бори видна у Ани над полем', /ахаха/.test(feedText), feedText);
  await pa.click('.rl-chatbtn');
  await pa.waitForTimeout(500);
  await pa.screenshot({ path: path.join(OUT, '5-chat.png') });
  check('чат открылся листом', await pa.evaluate(() => document.querySelector('.rl').classList.contains('chat-open')));
  // Закрыть свайпом вниз за шапку листа.
  const grab = await pa.evaluate(() => { const r = document.querySelector('.rl-grab').getBoundingClientRect(); return [r.left + 60, r.top + 10]; });
  await pa.mouse.move(grab[0], grab[1]); await pa.mouse.down();
  await pa.mouse.move(grab[0], grab[1] + 220, { steps: 8 }); await pa.mouse.up();
  await pa.waitForTimeout(500);
  check('чат закрылся свайпом вниз', await pa.evaluate(() => !document.querySelector('.rl').classList.contains('chat-open')));

  // Пауза касанием.
  await pb.mouse.click(196, 500);
  await pa.waitForTimeout(1200);
  check('пауза Бори встала у Ани', await pa.evaluate(() => document.querySelector('.rl').classList.contains('is-paused')));

  const calls = await pa.evaluate(() => window.__feedCalls.map((c) => c[0]));
  check('страница сообщает приложению, что смотрит', calls.includes('reelsWatching'), calls.join(','));

  // Звонок: приложение ответило мостом — кнопка круглая, 40 на 40.
  await pa.evaluate(() => window.watchVoiceState({ state: 'off' }));
  await pa.waitForTimeout(200);
  const call = await pa.evaluate(() => { const r = document.querySelector('.rl-call').getBoundingClientRect(); return [r.width, r.height]; });
  check('кнопка звонка круглая и тонкая', call[0] === call[1] && call[0] <= 44, call.join('×'));
  // Отправка — нижняя ячейка столбика справа, на одной линии с полем.
  const inRail = await pa.evaluate(() => {
    const f = document.querySelector('.rl-compose').getBoundingClientRect();
    const r = document.querySelector('.rl-rail').getBoundingClientRect();
    const s = document.querySelector('.rl-send').getBoundingClientRect();
    return s.left >= r.left && s.right <= r.right && s.bottom <= r.bottom && s.top >= f.top - 4 && s.left >= f.right;
  });
  check('кнопка «отправить» внизу столбика, рядом с полем', inRail);
  check('реакции — наши рисунки, не эмодзи', await pa.evaluate(() => /reactions\/heart|catalog_items/.test(document.querySelector('.rl-react img').src)));
  await pa.screenshot({ path: path.join(OUT, '7-call.png') });
  await pa.evaluate(() => window.watchVoiceState({ state: 'live', micOn: true }));
  await pa.waitForTimeout(200);
  await pa.screenshot({ path: path.join(OUT, '8-live.png') });
  const gap = await pa.evaluate(() => document.querySelector('.rl-rail').getBoundingClientRect().top - document.querySelector('.rl-voice').getBoundingClientRect().bottom);
  check('в разговоре звонок и действия не налезают', gap >= 8, gap + ' px между ними');

  // Клавиатура: на Android она урезает окно целиком. Плеер при этом не имеет
  // права сужаться — его края с кнопками площадки (лайки и счётчик TikTok)
  // стоят за краем экрана, а сжатие возвращало их в кадр (жалоба 05.10.2026).
  const ширина = () => pa.evaluate(() => document.querySelector('.rl-card.is-cur .rl-frame, .rl-frame').getBoundingClientRect().width);
  const доКлавиатуры = await ширина();
  await pa.setViewportSize({ width: 393, height: 420 });
  await pa.waitForTimeout(800);
  const сКлавиатурой = await ширина();
  check('клавиатура не сужает плеер', Math.abs(сКлавиатурой - доКлавиатуры) < 1 && доКлавиатуры > 393,
    Math.round(доКлавиатуры) + ' → ' + Math.round(сКлавиатурой));
  await pa.setViewportSize({ width: 393, height: 852 });
  await pa.waitForTimeout(400);

  // Узкий экран: ничего не налезает.
  await pa.setViewportSize({ width: 320, height: 640 });
  await pa.waitForTimeout(400);
  await pa.screenshot({ path: path.join(OUT, '6-narrow.png') });

  await browser.close();
  srv.close();
  console.log(ok ? 'ВСЁ ПРОШЛО' : 'ЕСТЬ ПРОВАЛЫ');
  process.exit(ok ? 0 : 1);
})().catch((e) => { console.error(e); process.exit(1); });
