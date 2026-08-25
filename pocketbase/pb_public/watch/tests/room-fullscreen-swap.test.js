/* Полноэкранный режим плеера подменяется своим — иначе чат теряется.
 *
 * Жалоба 24.08.2026: «не получается писать в приложении, когда смотрим видео».
 * В приложении комната открыта во встроенном браузере, и когда площадка уходит
 * в системный полноэкранный режим, кадр накрывает окно целиком: поле ввода
 * недоступно, выйти нечем. На телефоне выходим из системного режима сами и
 * включаем свой «кино»: кадр во всю площадь, чат поверх.
 *
 * Запуск: node pocketbase/pb_public/watch/tests/room-fullscreen-swap.test.js
 * (страницу берём с сервера — тест проверяет ВЫЛОЖЕННУЮ комнату).
 */
const { chromium } = require('/home/alelx/.hermes/hermes-agent/node_modules/playwright');

// BASE=http://127.0.0.1:8000/watch/room/ — прогон по локальным файлам до выкладки.
const base = process.env.BASE || 'https://togetherly.day/watch/room/';
const ROOM = 'fscin1test';

const PHONE = { width: 390, height: 844 };
const DESKTOP = { width: 1440, height: 900 };

(async () => {
  const browser = await chromium.launch();
  let ok = true;
  const check = (name, cond, extra = '') => {
    console.log((cond ? '  ✓ ' : '  ✗ ') + name, extra);
    if (!cond) ok = false;
  };

  // Просим кадр развернуться и смотрим, чем это кончилось.
  const goFullscreen = (page) => page.evaluate(async () => {
    const el = document.querySelector('#player') || document.body;
    try {
      await el.requestFullscreen();
    } catch (_) {
      // Заголовочный браузер иногда отказывает — тогда зовём обработчик так,
      // как его позвал бы сам браузер.
      Object.defineProperty(document, 'fullscreenElement', {
        value: el,
        configurable: true,
      });
      document.dispatchEvent(new Event('fullscreenchange'));
    }
    await new Promise((r) => setTimeout(r, 300));
    return document.body.className;
  });

  console.log('1. телефон: полный экран плеера уводит в свой режим с чатом');
  const phone = await browser.newContext({ viewport: PHONE, isMobile: true, hasTouch: true });
  const p1 = await phone.newPage();
  await p1.goto(base + '#' + ROOM, { waitUntil: 'domcontentloaded' });
  await p1.waitForTimeout(1200);
  const cls = await goFullscreen(p1);
  check('включился свой «кино»-режим', cls.includes('cinema'), 'классы: ' + cls);
  const composer = await p1.locator('.composer').boundingBox();
  check('поле сообщения на экране',
    composer && composer.y + composer.height <= PHONE.height + 1,
    composer ? 'низ поля=' + Math.round(composer.y + composer.height) : 'нет поля');
  await p1.locator('#message').fill('пишу во время просмотра');
  check('в поле пишется', (await p1.locator('#message').inputValue()) === 'пишу во время просмотра');

  console.log('2. широкий экран: не вмешиваемся');
  const desk = await browser.newContext({ viewport: DESKTOP });
  const p2 = await desk.newPage();
  await p2.goto(base + '#' + ROOM, { waitUntil: 'domcontentloaded' });
  await p2.waitForTimeout(1200);
  const cls2 = await goFullscreen(p2);
  check('свой режим не включается', !cls2.includes('cinema'), 'классы: ' + cls2);

  await browser.close();
  console.log(ok ? '\nВСЁ ХОРОШО' : '\nЕСТЬ ОШИБКИ');
  process.exit(ok ? 0 : 1);
})();
