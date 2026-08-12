/* Поле ссылки при открытой клавиатуре.
 *
 * Жалоба с iPhone: «не получается вставить ссылку на видео, строка улетает
 * вверх и не реагирует». Комната растянута на всю высоту и прокрутки не имеет,
 * а размер кадра считался от 100dvh — от ПОЛНОГО экрана, который клавиатура в
 * WKWebView не уменьшает. Плеер оставался во весь экран и выдавливал строку со
 * ссылкой за край.
 *
 * Клавиатуру Playwright не покажет, но её эффект воспроизводится точно: видимая
 * область становится низкой. Проверяем то, что важно человеку — поле и кнопка
 * «Включить» остаются в пределах видимого.
 */
const { chromium } = require('/home/alelx/.hermes/hermes-agent/node_modules/playwright');

const base = 'https://togetherly.day/watch/room/';
const ROOM = 'kbd7test';

// iPhone 14: экран 390×844, при русской клавиатуре видимой остаётся ~380 px.
const FULL = { width: 390, height: 844 };
const WITH_KEYBOARD = { width: 390, height: 380 };

(async () => {
  const browser = await chromium.launch();
  let ok = true;
  const check = (name, cond, extra = '') => {
    console.log((cond ? '  ✓ ' : '  ✗ ') + name, extra);
    if (!cond) ok = false;
  };

  const context = await browser.newContext({ viewport: FULL, isMobile: true });
  const page = await context.newPage();
  await page.goto(base + '#' + ROOM, { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(1500);

  const visible = async (selector) => {
    const box = await page.locator(selector).boundingBox();
    if (!box) return { inside: false, box: null };
    const height = page.viewportSize().height;
    return {
      inside: box.y >= 0 && box.y + box.height <= height + 1,
      box,
    };
  };

  const full = await visible('#link');
  check('на полном экране поле ссылки видно', full.inside,
    full.box ? `y=${Math.round(full.box.y)} h=${Math.round(full.box.height)}` : 'поля нет');

  // Клавиатура: видимая область низкая.
  await page.setViewportSize(WITH_KEYBOARD);
  await page.waitForTimeout(600);

  const cramped = await visible('#link');
  check('под клавиатурой поле ссылки остаётся видно', cramped.inside,
    cramped.box
      ? `y=${Math.round(cramped.box.y)} h=${Math.round(cramped.box.height)} экран=${WITH_KEYBOARD.height}`
      : 'поля нет');

  const apply = await visible('#apply');
  check('кнопка «Включить» тоже видна', apply.inside,
    apply.box ? `y=${Math.round(apply.box.y)}` : 'кнопки нет');

  // Поле должно принимать текст: фокус и ввод не должны терять символы.
  await page.locator('#link').click();
  await page.locator('#link').fill('https://youtu.be/dQw4w9WgXcQ');
  const typed = await page.locator('#link').inputValue();
  check('введённое остаётся в поле', typed === 'https://youtu.be/dQw4w9WgXcQ', typed);

  await browser.close();
  console.log(ok ? '\nВСЁ ХОРОШО' : '\nЕСТЬ ПРОВАЛЫ');
  process.exit(ok ? 0 : 1);
})();
