/* Кадр во всю площадь и телефон лёжа.
 *
 * Жалобы из комнаты: «нету чата при просмотре на весь экран», «очень большой
 * чат», «при повороте горизонтально не очень удобно смотреть». Полноэкранный
 * режим самого плеера отдаёт экран площадке целиком, и чат туда не положить —
 * поэтому разворачиваем своими силами: кадр на всю площадь, чат поверх.
 */
const { chromium } = require('/home/alelx/.hermes/hermes-agent/node_modules/playwright');

const base = 'https://togetherly.day/watch/room/';
const ROOM = 'cin9test';

const PORTRAIT = { width: 390, height: 844 };
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

  const box = async (sel) => page.locator(sel).boundingBox();

  console.log('1. вертикаль: чат не съедает кадр');
  const player = await box('#player');
  const side = await box('.side');
  // Кадр держит формат 16:9, выше чата ему не стать — проверяем, что чат не
  // разрастается: жалоба была «очень большой чат».
  check('чат занимает не больше трети экрана',
    side && side.height <= PORTRAIT.height * 0.4,
    side ? `чат=${Math.round(side.height)} из ${PORTRAIT.height}` : 'нет чата');

  console.log('2. кадр во всю площадь: чат поверх видео');
  await page.locator('#cinema').click();
  await page.waitForTimeout(500);
  const bigPlayer = await box('#player');
  const overlayChat = await box('.side');
  const composer = await box('.composer');
  check('кадр занял почти весь экран',
    bigPlayer && bigPlayer.height > PORTRAIT.height * 0.6,
    bigPlayer ? `высота=${Math.round(bigPlayer.height)}` : 'нет кадра');
  check('чат виден поверх кадра',
    overlayChat && bigPlayer &&
      overlayChat.y < bigPlayer.y + bigPlayer.height && overlayChat.height > 40,
    overlayChat ? `чат y=${Math.round(overlayChat.y)} h=${Math.round(overlayChat.height)}` : 'чата нет');
  check('поле сообщения на месте', composer && composer.height > 20);

  await page.locator('#cinema').click();
  await page.waitForTimeout(400);

  console.log('3. телефон лёжа: кадр слева, чат справа');
  await page.setViewportSize(LANDSCAPE);
  await page.waitForTimeout(600);
  const wide = await box('#player');
  const chat = await box('.side');
  check('кадр занимает левую часть', wide && wide.width > LANDSCAPE.width * 0.4,
    wide ? `ширина=${Math.round(wide.width)}` : 'нет кадра');
  check('чат стоит правее кадра', wide && chat && chat.x > wide.x,
    chat && wide ? `чат x=${Math.round(chat.x)} кадр x=${Math.round(wide.x)}` : 'нет данных');
  check('оба помещаются по высоте',
    wide && chat && wide.height <= LANDSCAPE.height && chat.height <= LANDSCAPE.height);

  await browser.close();
  console.log(ok ? '\nВСЁ ХОРОШО' : '\nЕСТЬ ПРОВАЛЫ');
  process.exit(ok ? 0 : 1);
})();
