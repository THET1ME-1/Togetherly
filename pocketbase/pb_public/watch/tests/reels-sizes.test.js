/* Совместная лента на любом экране: ширина и высота.
 *
 * Перебирает телефоны от 320×568 до 440×956, низкие окна под клавиатуру
 * (так её видит Android: окно целиком становится ниже), клавиатуру iPhone
 * (видимая область меньше окна, класс `typing`), альбом, раскладушки,
 * планшеты и компьютер. В каждом размере четыре состояния: покой с репликами
 * и плашкой «Листает Аня», текст в поле, открытый чат, клавиатура.
 *
 * Проверяет:
 *   - страница не прокручивается ни вбок, ни вниз;
 *   - каждая видимая кнопка и поле целиком на экране;
 *   - шапка, звонок, плашка ведущего, столбик, реплики, поле и кнопка
 *     отправки не наезжают друг на друга;
 *   - в поле есть где печатать, кнопки не мельче 40 точек;
 *   - в открытом чате список сообщений не схлопнулся.
 *
 * Страницы — локальная копия pb_public, /api уходит на прод, вход — тестовая
 * пара (~/keys/togetherly-test-pair.txt). Ролики — настоящие Shorts, тем же
 * перехватом, что в приложении.
 *
 * Запуск: node pocketbase/pb_public/watch/tests/reels-sizes.test.js
 * Снимки: SHOTS=<папка> перед командой.
 */
const { chromium } = require('/home/alelx/.hermes/hermes-agent/node_modules/playwright');
const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..');
const PORT = 8799;
const PROD = 'https://togetherly.day';
const PAIR = 'r5269c54ac34919';
const BASE = `http://127.0.0.1:${PORT}`;
const SHOTS = process.env.SHOTS || '';

// [название, ширина, высота, вид]: phone — телефон стоя, можно открыть
// клавиатуру; flat — всё остальное.
const SIZES = [
  ['SE 1', 320, 568, 'phone'],
  ['узкий Android', 360, 640, 'phone'],
  ['Galaxy S', 360, 780, 'phone'],
  ['SE 2022', 375, 667, 'phone'],
  ['iPhone 13', 390, 844, 'phone'],
  ['iPhone 15', 393, 852, 'phone'],
  ['Pixel', 412, 915, 'phone'],
  ['iPhone Plus', 430, 932, 'phone'],
  ['iPhone Pro Max', 440, 956, 'phone'],
  ['Fold снаружи', 280, 653, 'phone'],
  ['низкое окно', 393, 480, 'flat'],
  ['совсем низкое', 360, 360, 'flat'],
  ['SE лёжа', 568, 320, 'flat'],
  ['SE 2022 лёжа', 667, 375, 'flat'],
  ['iPhone 15 лёжа', 852, 393, 'flat'],
  ['Pro Max лёжа', 956, 440, 'flat'],
  ['Fold раскрыт', 673, 841, 'flat'],
  ['iPad стоя', 768, 1024, 'flat'],
  ['iPad лёжа', 1024, 768, 'flat'],
  ['ноутбук', 1280, 720, 'flat'],
  ['монитор', 1920, 1080, 'flat'],
];

function creds() {
  const t = fs.readFileSync(path.join(process.env.HOME, 'keys/togetherly-test-pair.txt'), 'utf8');
  return [...t.matchAll(/(claude-test-231[ab]@togetherly\.day) \/ (\S+)/g)].map((x) => ({ email: x[1], password: x[2] }));
}

const api = (p, body, token) => fetch(PROD + p, {
  method: 'POST',
  headers: Object.assign({ 'Content-Type': 'application/json' }, token ? { Authorization: token } : {}),
  body: JSON.stringify(body),
}).then((r) => r.json());

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
      const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.woff2': 'font/woff2', '.webp': 'image/webp' };
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

let fails = 0;
const problems = [];
const bad = (size, state, what) => { fails++; problems.push(`${size} · ${state}: ${what}`); };

/** Раскладка в эту секунду: прямоугольники всего, что видно. */
function measure() {
  const W = window.innerWidth;
  const vv = window.visualViewport;
  const H = vv ? vv.height : window.innerHeight;
  const doc = document.scrollingElement;
  const shown = (e) => {
    if (!e) return null;
    const s = getComputedStyle(e);
    if (s.display === 'none' || s.visibility === 'hidden' || Number(s.opacity) < 0.05) return null;
    for (let p = e; p; p = p.parentElement) if (p.hidden) return null;
    const r = e.getBoundingClientRect();
    if (r.width < 1 || r.height < 1) return null;
    return { l: r.left, t: r.top, r: r.right, b: r.bottom, w: r.width, h: r.height };
  };
  const one = (sel) => shown(document.querySelector(sel));
  const all = (sel) => [...document.querySelectorAll(sel)].map((e) => [sel + (e.className ? '.' + String(e.className).split(' ').join('.') : ''), shown(e)]).filter((x) => x[1]);
  const input = document.querySelector('.rl-input');
  // Шапка — строка во всю ширину, а заняты в ней только кнопки и пилюля:
  // меряем их вместе.
  const union = (sel) => {
    const rs = [...document.querySelectorAll(sel)].map(shown).filter(Boolean);
    if (!rs.length) return null;
    const u = { l: Math.min(...rs.map((r) => r.l)), t: Math.min(...rs.map((r) => r.t)), r: Math.max(...rs.map((r) => r.r)), b: Math.max(...rs.map((r) => r.b)) };
    return Object.assign(u, { w: u.r - u.l, h: u.b - u.t });
  };
  const chat = document.querySelector('.rl').classList.contains('chat-open');
  return {
    W, H,
    scrollX: doc.scrollWidth - doc.clientWidth,
    scrollY: doc.scrollHeight - doc.clientHeight,
    boxes: {
      top: union('.rl-top > *'), voice: one('.rl-voice'), lead: one('.rl-lead'), rail: one('.rl-rail'),
      feed: one('.rl-feed'), compose: one('.rl-compose'), send: one('.rl-send'), sheet: one('.rl-sheet'),
      list: one('.rl-list'), head: one('.rl-head'), wait: one('.rl-wait'),
    },
    taps: [...all('.rl-top button'), ...all('.rl-voice button'), ...all('.rl-rail button'), ...all('.rl-lead button'),
      ...all('.rl-send'), ...(chat ? all('.rl-x') : []), ...all('.rl-input')],
    inputW: input ? input.getBoundingClientRect().width : 0,
    chat,
    typing: document.body.classList.contains('typing'),
  };
}

const overlap = (a, b, gap = 0) => a && b && a.l < b.r - gap && b.l < a.r - gap && a.t < b.b - gap && b.t < a.b - gap;

function judge(size, state, m) {
  if (m.scrollX > 0) bad(size, state, `страница прокручивается вбок на ${m.scrollX}`);
  if (m.scrollY > 0) bad(size, state, `страница прокручивается вниз на ${m.scrollY}`);
  for (const [name, r] of m.taps) {
    if (r.l < -0.5 || r.t < -0.5 || r.r > m.W + 0.5 || r.b > m.H + 0.5) {
      bad(size, state, `${name} за краем экрана (${Math.round(r.l)},${Math.round(r.t)}–${Math.round(r.r)},${Math.round(r.b)} при ${m.W}×${Math.round(m.H)})`);
    }
    if (!/rl-input/.test(name) && (r.w < 39.5 || r.h < 25.5)) bad(size, state, `${name} мелкая: ${Math.round(r.w)}×${Math.round(r.h)}`);
  }
  const B = m.boxes;
  // Пары, которые не имеют права встречаться. Кнопка отправки стоит на нижнем
  // отступе столбика — это задумано, их не сравниваем.
  const pairs = [
    ['top', 'voice'], ['top', 'rail'], ['voice', 'rail'], ['lead', 'rail'], ['lead', 'voice'], ['top', 'lead'],
    ['feed', 'rail'], ['feed', 'compose'], ['feed', 'top'], ['feed', 'lead'],
    ['compose', 'rail'], ['compose', 'send'],
  ];
  if (m.chat) pairs.push(['rail', 'head'], ['rail', 'sheet'], ['top', 'sheet'], ['voice', 'sheet']);
  for (const [a, b] of pairs) {
    if (overlap(B[a], B[b], 1)) bad(size, state, `${a} наезжает на ${b}`);
  }
  if (B.compose && m.inputW < 110) bad(size, state, `в поле ввода ${Math.round(m.inputW)} точек`);
  if (m.chat && B.list && B.list.h < 60) bad(size, state, `список чата схлопнулся: ${Math.round(B.list.h)}`);
  if (m.chat && !B.list) bad(size, state, 'список чата не виден');
}

(async () => {
  const [a] = creds();
  const auth = await api('/api/collections/users/auth-with-password', { identity: a.email, password: a.password });
  const room = (await api('/api/watch/room', { groupId: PAIR }, auth.token)).room;
  if (!room) throw new Error('нет кода комнаты');

  const srv = await serve();
  const browser = await chromium.launch({ args: ['--autoplay-policy=no-user-gesture-required'] });
  const ids = await harvest(browser);
  console.log(`роликов Shorts: ${ids.length}`);
  if (SHOTS) fs.mkdirSync(SHOTS, { recursive: true });
  const errors = [];

  for (const [name, W, H, kind] of SIZES) {
    const ctx = await browser.newContext({ viewport: { width: W, height: H }, locale: 'ru-RU', hasTouch: true, isMobile: W < 700 });
    await ctx.addInitScript(({ token, feed }) => {
      window.__togetherlyAuth = { token, name: 'Боря' };
      window.flutter_inappwebview = {
        callHandler: async (h, arg) => (h === 'reelsFeed' ? feed.splice(0, (arg && arg.need) || 8) : null),
      };
      // Клавиатура iPhone: видимая область меньше окна. Высоту задаёт тест.
      const real = window.visualViewport;
      const fake = {
        get height() { return window.__kbH || (real ? real.height : innerHeight); },
        get width() { return innerWidth; },
        get offsetTop() { return 0; },
        addEventListener() {}, removeEventListener() {},
      };
      Object.defineProperty(window, 'visualViewport', { get: () => fake });
    }, { token: auth.token, feed: ids.slice() });
    const page = await ctx.newPage();
    page.on('pageerror', (e) => errors.push(`${name}: ${e.message}`));
    await page.goto(`${BASE}/watch/reels/?feed=shorts&name=${encodeURIComponent('Боря')}#${room}`);
    await page.waitForFunction(() => document.querySelector('.rl.is-in'), null, { timeout: 20000 }).catch(() => {});
    await page.waitForTimeout(2500);

    // Покой: звонок ответил, ведёт партнёр, над полем две реплики.
    await page.evaluate(() => {
      window.watchVoiceState({ state: 'off' });
      const lead = document.querySelector('.rl-lead');
      lead.hidden = false;
      lead.querySelector('span').textContent = 'Листает Аня';
      const feed = document.querySelector('.rl-feed');
      feed.innerHTML = '<div class="rl-msg"><b>Аня</b> смотри какой котик ахаха, я не могу</div><div class="rl-msg me">ну это шедевр</div>';
      feed.style.opacity = '1';
    });
    await page.waitForTimeout(700);
    const shot = async (state) => { if (SHOTS) await page.screenshot({ path: path.join(SHOTS, `${W}x${H}-${state}.png`) }); };
    let m = await page.evaluate(measure);
    judge(name, 'покой', m);
    await shot('rest');

    // Разговор: капсула звонка растёт вниз (или встаёт строкой).
    await page.evaluate(() => window.watchVoiceState({ state: 'live', micOn: true, speakerOn: true }));
    await page.waitForTimeout(500);
    judge(name, 'разговор', await page.evaluate(measure));
    await shot('call');
    await page.evaluate(() => window.watchVoiceState({ state: 'off' }));
    await page.waitForTimeout(300);

    // Текст в поле: кнопка отправки наливается.
    await page.fill('.rl-input', 'длинная реплика чтобы посмотреть как поле держит текст');
    await page.waitForTimeout(500);
    judge(name, 'текст в поле', await page.evaluate(measure));
    await shot('text');

    // Клавиатура iPhone: видимая область — 55% окна, класс typing.
    await page.evaluate((h) => { window.__kbH = h; }, Math.round(H * 0.55));
    await page.focus('.rl-input');
    await page.waitForTimeout(900);
    m = await page.evaluate(measure);
    if (!m.typing && kind === 'phone') bad(name, 'клавиатура iPhone', 'класс typing не встал');
    judge(name, 'клавиатура iPhone', m);
    await shot('kb-ios');
    await page.evaluate(() => { window.__kbH = 0; document.activeElement.blur(); });
    await page.waitForTimeout(900);

    // Клавиатура Android: окно целиком становится ниже.
    if (kind === 'phone') {
      await page.focus('.rl-input');
      await page.setViewportSize({ width: W, height: Math.round(H * 0.55) });
      await page.waitForTimeout(900);
      if (!(await page.evaluate(() => document.body.classList.contains('rl-kb')))) bad(name, 'клавиатура Android', 'страница не заметила клавиатуру');
      judge(name, 'клавиатура Android', await page.evaluate(measure));
      await shot('kb-android');
      await page.evaluate(() => document.activeElement.blur());
      await page.setViewportSize({ width: W, height: H });
      await page.waitForTimeout(900);
    }

    // Открытый чат.
    await page.click('.rl-chatbtn');
    await page.waitForTimeout(700);
    judge(name, 'чат', await page.evaluate(measure));
    await shot('chat');

    await ctx.close();
  }

  await browser.close();
  srv.close();
  for (const p of problems) console.log('  ✗ ' + p);
  for (const e of errors) console.log('  ✗ ошибка страницы ' + e);
  console.log(fails || errors.length ? `ЕСТЬ ПРОВАЛЫ: ${fails + errors.length}` : `ВСЁ ПРОШЛО: ${SIZES.length} размеров`);
  process.exit(fails || errors.length ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
