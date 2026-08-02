/* Ютуб в комнате: встраиванию нужен реферер, дискам — наоборот.
 *
 * Страница держит `<meta name="referrer" content="no-referrer">` ради
 * Яндекс.Диска: тот отдаёт файл только тому, кто не представился чужим сайтом
 * (с нашим реферером — 403). Но мета действует на всю страницу, и ютуб, для
 * которого реферер обязателен, отвечал ошибкой 153 на КАЖДЫЙ ролик (жалоба
 * 1 августа: «совершенно любое видео с ютуба»).
 *
 * Развязка: у iframe атрибут referrerpolicy поддерживается и перебивает
 * страничную мету — площадки реферер получают. У медиа-элементов такого
 * атрибута НЕТ, поэтому ссылки дисков в теге <video> остаются под метой.
 *
 * Запуск: node pocketbase/pb_public/watch/tests/room-youtube-referrer.test.js
 */
const { chromium } = require('/home/alelx/.hermes/hermes-agent/node_modules/playwright');
const fs = require('fs');
const path = require('path');

const base = 'https://togetherly.day/watch/room/';
const ROOM = 'ytref9';
const LINK = 'https://www.youtube.com/watch?v=jNQXAC9IVRw';

let ok = true;
const check = (n, c, x = '') => { console.log((c ? '  ✓ ' : '  ✗ ') + n, x); if (!c) ok = false; };

(async () => {
  console.log('1. запрос ютуба уходит с реферером комнаты');
  const b = await chromium.launch();
  const c = await b.newContext();
  const p = await c.newPage();

  const embeds = [];
  p.on('request', (r) => {
    if (/^https:\/\/www\.youtube\.com\/embed\//.test(r.url())) {
      embeds.push(r.headers().referer || '');
    }
  });

  await p.goto(base + '?src=' + encodeURIComponent(LINK) + '#' + ROOM,
    { waitUntil: 'domcontentloaded' });
  await p.waitForTimeout(9000);

  check('ролик встроился', embeds.length > 0,
    embeds.length ? '' : '(запроса к youtube/embed не было)');
  check('реферер приложен', embeds.length > 0 && embeds.every((r) => r.startsWith('https://togetherly.')),
    JSON.stringify(embeds));

  await b.close();

  // Обратная половина правила: ссылки дисков по-прежнему уходят без реферера,
  // иначе Яндекс ответит 403. Проверяем по исходнику — сетевой прогон для
  // Яндекса требует живой публичной ссылки и ломался бы вместе с ней.
  console.log('2. дискам реферер по-прежнему не показываем');
  const room = fs.readFileSync(path.join(__dirname, '..', 'room', 'room.js'), 'utf8');
  const html = fs.readFileSync(path.join(__dirname, '..', 'room', 'index.html'), 'utf8');
  check('страничная мета no-referrer на месте',
    /<meta\s+name=["']referrer["'][^>]*no-referrer/i.test(html));
  check('исключение висит на iframe, а не на <video>',
    /frame\.referrerPolicy\s*=/.test(room) && !/\bv\.referrerPolicy\s*=/.test(room));

  console.log(ok ? '\nВСЁ ХОРОШО' : '\nЕСТЬ ПРОБЛЕМЫ');
  process.exit(ok ? 0 : 1);
})();
