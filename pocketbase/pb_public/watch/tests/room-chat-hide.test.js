/* Чат в комнате можно убрать.
 *
 * Две жалобы подряд, 28 и 29 августа 2026: «при просмотре видео мешает чат,
 * неудобно смотреть» и «не убирается чат во время просмотра видео». Режим
 * «кино» кладёт переписку поверх кадра — видно и её, и фильм, — но убрать её
 * совсем было нечем. Теперь рядом с кнопкой «кино» стоит кнопка чата: она
 * прячет переписку и поле ввода, а выбор запоминается до следующего раза.
 *
 * Запуск: node pocketbase/pb_public/watch/tests/room-chat-hide.test.js
 *         node ... https://togetherly.day   (по проду)
 */
const { chromium } = require('/home/alelx/.hermes/hermes-agent/node_modules/playwright');
const path = require('path');

const arg = process.argv[2];
const base = arg
  ? arg.replace(/\/$/, '') + '/watch/room/'
  : 'file://' + path.resolve(__dirname, '..', 'room') + '/index.html';
const ROOM = 'hide9test';
const PHONE = { width: 390, height: 844 };

(async () => {
  const browser = await chromium.launch();
  let ok = true;
  const check = (name, cond, extra = '') => {
    console.log((cond ? '  ✓ ' : '  ✗ ') + name, extra);
    if (!cond) ok = false;
  };

  const context = await browser.newContext({ viewport: PHONE, isMobile: true });
  const page = await context.newPage();
  await page.goto(base + '#' + ROOM, { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(1200);

  const visible = async (sel) => page.locator(sel).isVisible().catch(() => false);

  console.log('1. кнопка есть и чат по умолчанию на месте');
  check('кнопка чата в разметке', await visible('#chatToggle'));
  check('чат виден', await visible('.side'));
  check('поле ввода видно', await visible('.composer'));

  console.log('2. нажали — чат ушёл');
  await page.locator('#chatToggle').click();
  await page.waitForTimeout(300);
  check('переписки нет', !(await visible('.side')));
  check('поля ввода нет', !(await visible('.composer')));
  check('кнопка помечена нажатой',
    (await page.locator('#chatToggle').getAttribute('aria-pressed')) === 'true');
  check('кнопка осталась на экране — иначе чат не вернуть',
    await visible('#chatToggle'));

  console.log('3. в режиме «кино» тоже убирается');
  await page.locator('#cinema').click();
  await page.waitForTimeout(400);
  check('чат так и скрыт', !(await visible('.side')));
  const player = await page.locator('#player').boundingBox();
  check('кадр занял площадь целиком',
    player && player.height > PHONE.height * 0.6,
    player ? `высота=${Math.round(player.height)}` : 'нет кадра');

  console.log('4. выбор переживает перезагрузку страницы');
  await page.reload({ waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(1200);
  check('чат остался скрытым', !(await visible('.side')));

  console.log('5. вернули обратно');
  await page.locator('#chatToggle').click();
  await page.waitForTimeout(300);
  check('переписка вернулась', await visible('.side'));
  check('поле ввода вернулось', await visible('.composer'));

  await browser.close();
  console.log(ok ? '\nИТОГ: всё сошлось' : '\nИТОГ: есть расхождения');
  process.exit(ok ? 0 : 1);
})();
