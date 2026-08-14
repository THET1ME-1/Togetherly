/* Раскладка при открытой клавиатуре.
 *
 * Жалоба 14.08.2026: «почему совместный просмотр выглядит так, когда я хочу
 * написать сообщение? всё было так красиво, а сейчас будто сижу не с телефона,
 * а с пк». Причина: в портрете клавиатура сжимает окно по высоте, ширина
 * становится больше высоты, и браузер честно переключает `orientation` в
 * landscape — включалась раскладка «телефон лёжа» с двумя колонками. Условие
 * ландшафта теперь требует ещё и ширину от 540 пикселей.
 *
 * Запуск: node pocketbase/pb_public/watch/tests/room-keyboard-layout.test.js
 */
const { chromium } = require('/home/alelx/.hermes/hermes-agent/node_modules/playwright');

const base = 'https://togetherly.day/watch/room/';
const ROOM = 'kbd9test';

const PORTRAIT = { width: 390, height: 844 };
// Столько остаётся от окна, когда снизу открыта клавиатура: ширина прежняя,
// высота меньше ширины — ровно тот случай, что ломал вёрстку.
const PORTRAIT_TYPING = { width: 390, height: 360 };
const LANDSCAPE = { width: 844, height: 390 };

(async () => {
  const browser = await chromium.launch();
  let ok = true;
  const check = (name, cond, extra = '') => {
    console.log((cond ? '  ✓ ' : '  ✗ ') + name, extra);
    if (!cond) ok = false;
  };

  const context = await browser.newContext({ viewport: PORTRAIT, isMobile: true });
  const page = await context.newPage();
  await page.goto(base + '#' + ROOM, { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(1500);

  const columns = () => page.evaluate(() =>
    getComputedStyle(document.querySelector('.stage-wrap'))
      .gridTemplateColumns.trim().split(/\s+/).length);

  console.log('1. портрет: одна колонка');
  check('колонка одна', (await columns()) === 1, 'колонок: ' + (await columns()));

  console.log('2. портрет с клавиатурой: раскладка не разъезжается');
  await page.setViewportSize(PORTRAIT_TYPING);
  await page.waitForTimeout(400);
  const typingCols = await columns();
  check('по-прежнему одна колонка', typingCols === 1, 'колонок: ' + typingCols);

  const player = await page.locator('#player').boundingBox();
  const composer = await page.locator('.composer').boundingBox();
  check('поле ввода на экране',
    composer && composer.y + composer.height <= PORTRAIT_TYPING.height + 1,
    composer ? `низ поля=${Math.round(composer.y + composer.height)}` : 'нет поля');
  check('кадр не выдавил поле',
    player && composer && player.y + player.height <= composer.y + 1,
    player && composer ? `кадр до ${Math.round(player.y + player.height)}, поле с ${Math.round(composer.y)}` : '');

  console.log('3. телефон лёжа: две колонки остались');
  await page.setViewportSize(LANDSCAPE);
  await page.waitForTimeout(400);
  const landCols = await columns();
  check('колонок две', landCols === 2, 'колонок: ' + landCols);

  await browser.close();
  console.log(ok ? '\nВСЁ СОШЛОСЬ' : '\nЕСТЬ РАСХОЖДЕНИЯ');
  process.exit(ok ? 0 : 1);
})();
