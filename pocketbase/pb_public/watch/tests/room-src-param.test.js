/* Свой ролик из приложения: комната открывается адресом ?src=<файл>#код.
 *
 * Раньше приложение жало «Включить» в комнате скриптом сразу после загрузки
 * страницы — до того, как поднимался канал, поэтому `source` уходил в никуда и
 * партнёр оставался с пустым экраном. Теперь ссылка ждёт подписки.
 */
const { chromium } = require('/home/alelx/.hermes/hermes-agent/node_modules/playwright');

const VIDEO = 'https://togetherly.day/api/files/watch_videos/' +
  'e8e5yaidogj6r9x/2cd1b6a2ce095ced39d3ec5deaf74b5c_vygwrxdr49.mp4';
const base = 'https://togetherly.day/watch/room/';
const ROOM = 'srcp4k9m';

const open = async (b, url) => {
  const c = await b.newContext();
  const p = await c.newPage();
  await p.goto(url, { waitUntil: 'domcontentloaded' });
  return { c, p };
};

(async () => {
  const b = await chromium.launch();
  let ok = true;
  const check = (name, cond, extra = '') => {
    console.log((cond ? '  ✓ ' : '  ✗ ') + name, extra);
    if (!cond) ok = false;
  };

  console.log('1. партнёр уже в комнате, ролик приходит из приложения');
  const guest = await open(b, base + '#' + ROOM);
  await guest.p.waitForTimeout(3000);

  const app = await open(b, base + '?src=' + encodeURIComponent(VIDEO) + '#' + ROOM);
  await app.p.waitForTimeout(4000);

  const appSrc = await app.p.locator('#player video').getAttribute('src').catch(() => null);
  check('ролик играет у того, кто открыл', appSrc === VIDEO, appSrc || '(нет плеера)');

  await guest.p.waitForTimeout(2000);
  const guestSrc = await guest.p.locator('#player video').getAttribute('src').catch(() => null);
  check('тот же ролик доехал партнёру', guestSrc === VIDEO, guestSrc || '(нет плеера)');

  console.log('2. партнёр заходит позже — ролик отдаёт вкладка, которая внутри');
  const late = await open(b, base + '#' + ROOM);
  await late.p.waitForTimeout(4500);
  const lateSrc = await late.p.locator('#player video').getAttribute('src').catch(() => null);
  check('опоздавший получил ролик', lateSrc === VIDEO, lateSrc || '(нет плеера)');

  console.log('3. пауза и старт доезжают до партнёра');
  await app.p.evaluate(() => document.querySelector('#player video').play());
  await app.p.waitForTimeout(2500);
  const guestPlaying = await guest.p.evaluate(
    () => !document.querySelector('#player video').paused);
  check('партнёр играет вместе с нами', guestPlaying);

  await b.close();
  console.log(ok ? '\nВСЁ ХОРОШО' : '\nЕСТЬ ПРОБЛЕМЫ');
  process.exit(ok ? 0 : 1);
})();
