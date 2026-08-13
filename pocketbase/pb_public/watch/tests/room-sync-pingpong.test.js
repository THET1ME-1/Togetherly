/* Взаимная перемотка: двое тянут друг друга и ролик дёргается без конца.
 *
 * Жалоба: «видео само отматывается на несколько секунд, и так очень много раз,
 * либо вообще останавливается». Причина в комнате: раз в три секунды своё время
 * шлют ОБА зрителя (комментарий рядом обещал ведущего, а проверки в коде не
 * было), и каждый, увидев расхождение больше полутора секунд, перематывает себя
 * к чужому времени. Перемотка сама добавляет буферизацию, расхождение растёт —
 * и дальше они возят друг друга по кругу.
 *
 * Воспроизводим так же, как это выходит в жизни: один зритель отстаёт (телефон
 * послабее, сеть похуже — здесь это замедленное воспроизведение). Смотрим на
 * того, кто ВЕДЁТ и ничего не трогает: его дёргать не должно вовсе. На прежнем
 * коде отставший каждые три секунды тянул ведущего назад к себе.
 *
 * Запуск: node pocketbase/pb_public/watch/tests/room-sync-pingpong.test.js
 *         node …/room-sync-pingpong.test.js https://togetherly.day
 */
const { chromium } = require('/home/alelx/.hermes/hermes-agent/node_modules/playwright');

const HOST = process.argv[2] || 'https://togetherly.day';
const ROOM = 'pingpong4';
// Свой ролик на минуту: чужие записи пар для этого не годятся, а восьми
// секунд не хватает — ролик кончается прямо посреди наблюдения, и «пауза» в
// конце теста означает всего лишь конец файла.
// Сделан так: ffmpeg -f lavfi -i testsrc=size=320x240:rate=15:duration=60 …
const CLIP = 'https://togetherly.day/watch/tests/clip60.mp4';

const SETTLE = 9000;    // сколько даём на первичную синхронизацию
const WATCH = 24000;    // сколько наблюдаем после расхождения
const SLOW = 0.85;      // насколько медленнее играет отстающий

let ok = true;
const check = (n, c, x = '') => { console.log((c ? '  ✓ ' : '  ✗ ') + n, x); if (!c) ok = false; };

/** Счётчик перемоток самого плеера. */
const countSeeks = (page) => page.evaluate(() => {
  const v = document.querySelector('#player video');
  if (!v || v.__watched) return;
  v.__watched = true;
  window.__seeks = [];
  v.addEventListener('seeked', () => window.__seeks.push(Math.round(v.currentTime * 10) / 10));
});

const seeks = (page) => page.evaluate(() => (window.__seeks || []).slice());
const at = (page) => page.evaluate(() => {
  const v = document.querySelector('#player video');
  return v ? v.currentTime : -1;
});

(async () => {
  const browser = await chromium.launch({
    args: ['--autoplay-policy=no-user-gesture-required', '--mute-audio'],
  });
  const ctxA = await browser.newContext({ viewport: { width: 1200, height: 780 } });
  const ctxB = await browser.newContext({ viewport: { width: 1200, height: 780 } });
  const a = await ctxA.newPage();
  const b = await ctxB.newPage();

  // Ролик включает первый — так его приводит приложение. Второй заходит на
  // голый код комнаты и получает ссылку от того, кто уже внутри: именно он и
  // должен идти ведомым.
  await a.goto(HOST + '/watch/room/?src=' + encodeURIComponent(CLIP) + '#' + ROOM,
    { waitUntil: 'domcontentloaded' });
  await a.waitForTimeout(5000);
  check('ролик встал у первого', await a.locator('#player video').count() === 1);

  await b.goto(HOST + '/watch/room/#' + ROOM, { waitUntil: 'domcontentloaded' });
  await b.waitForTimeout(8000);
  check('ролик доехал до второго', await b.locator('#player video').count() === 1);

  // Смотрят оба: пока один стоит на паузе, он тянет второго в стоп, и это уже
  // другая история. Запуск ждём по-настоящему — промис `play()` умеет
  // отклоняться молча.
  const start = (page) => page.evaluate(async () => {
    const v = document.querySelector('#player video');
    try { await v.play(); } catch (_) { /* попробуем ещё раз */ }
    return !v.paused;
  });
  await start(a);
  await start(b);
  await a.waitForTimeout(SETTLE);
  if (!(await start(a)) || !(await start(b))) await a.waitForTimeout(2000);
  const playingBefore = (await start(a)) && (await start(b));
  check('оба смотрят до расхождения', playingBefore);

  await countSeeks(a);
  await countSeeks(b);

  // Второй отстаёт сам по себе — так ведёт себя телефон послабее.
  await b.evaluate((rate) => {
    document.querySelector('#player video').playbackRate = rate;
  }, SLOW);

  await a.waitForTimeout(WATCH);

  const sa = await seeks(a);
  const sb = await seeks(b);
  const total = sa.length + sb.length;
  console.log('  перемоток за %d с: у первого %d %s, у второго %d %s',
    Math.round(WATCH / 1000), sa.length, JSON.stringify(sa.slice(0, 8)),
    sb.length, JSON.stringify(sb.slice(0, 8)));

  // Главное: ведущего не дёргает. Отставший догоняет сам, это его работа.
  check('ведущего не отматывает', sa.length === 0, '(перемоток у ведущего: ' + sa.length + ')');
  check('и в комнате не идёт качель', total <= 6, '(всего перемоток: ' + total + ')');

  const ta = await at(a);
  const tb = await at(b);
  check('отставший держится рядом', Math.abs(ta - tb) < 3.5,
    't1=' + ta.toFixed(1) + ' t2=' + tb.toFixed(1));

  const playingA = await a.evaluate(() => !document.querySelector('#player video').paused);
  const playingB = await b.evaluate(() => !document.querySelector('#player video').paused);
  check('оба продолжают играть, никто не встал', playingA && playingB,
    'первый=' + playingA + ' второй=' + playingB);

  await browser.close();
  console.log(ok ? '\nВСЁ ХОРОШО' : '\nЕСТЬ ПРОВАЛЫ');
  process.exit(ok ? 0 : 1);
})();
