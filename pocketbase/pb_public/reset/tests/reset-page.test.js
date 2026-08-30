/* Страница смены пароля по ссылке из письма.
 *
 * До 30 августа 2026 письмо «Забыли пароль» вело в админку PocketBase, и
 * человек упирался в форму «Superuser login» — сбросить пароль было нельзя
 * НИКАК, ни через сайт, ни через приложение. За сутки в этот тупик приходило
 * около шестисот человек.
 *
 * Тест проходит тот же путь, что человек: открывает ссылку с токеном, вводит
 * новый пароль, получает ответ. Настоящий токен подписывается на сервере
 * (см. tools/make_reset_token.py) и передаётся аргументом.
 *
 * Запуск:
 *   node reset-page.test.js                        — по локальным файлам, без токена
 *   node reset-page.test.js https://togetherly.day <токен> <почта> <новый пароль>
 */
const { chromium } = require('/home/alelx/.hermes/hermes-agent/node_modules/playwright');
const path = require('path');

const base = process.argv[2];
const token = process.argv[3] || 'FAKETOKEN';
const email = process.argv[4] || '';
const newPass = process.argv[5] || '';
const url = base
  ? base.replace(/\/$/, '') + '/reset/#' + token
  : 'file://' + path.resolve(__dirname, '..') + '/index.html#' + token;

(async () => {
  const browser = await chromium.launch();
  let ok = true;
  const check = (name, cond, extra = '') => {
    console.log((cond ? '  ✓ ' : '  ✗ ') + name, extra);
    if (!cond) ok = false;
  };

  const page = await browser.newPage({ viewport: { width: 420, height: 800 } });
  const errors = [];
  page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));
  await page.goto(url, { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(600);

  console.log('0. без токена — форма запроса письма');
  const bare = await browser.newPage({ viewport: { width: 420, height: 800 } });
  await bare.goto(base ? base.replace(/\/$/, '') + '/reset/'
                       : 'file://' + path.resolve(__dirname, '..') + '/index.html',
                  { waitUntil: 'domcontentloaded' });
  await bare.waitForTimeout(500);
  const bareText = await bare.locator('body').innerText();
  check('просит почту, а не пароль', /почт/i.test(bareText), bareText.slice(0, 70));
  check('поле почты есть', (await bare.locator('#mail').count()) === 1);
  check('поля нового пароля скрыты', !(await bare.locator('#p1').isVisible()));
  await bare.locator('#mail').fill('не-почта');
  await bare.locator('#send').click();
  await bare.waitForTimeout(400);
  check('кривую почту не принимает',
    /почт/i.test(await bare.locator('#msg').innerText()));
  await bare.close();

  console.log('1. страница открывается и говорит по-русски');
  const text = await page.locator('body').innerText();
  check('это не админка PocketBase', !/superuser/i.test(text), text.slice(0, 60));
  check('заголовок про пароль', /парол/i.test(text));
  check('есть два поля', (await page.locator('input[type=password]').count()) === 2);
  check('есть кнопка', (await page.locator('button#save').count()) === 1);

  console.log('2. короткий пароль не принимается');
  await page.locator('#p1').fill('123');
  await page.locator('#p2').fill('123');
  await page.locator('#save').click();
  await page.waitForTimeout(400);
  check('сказали про длину', /8/.test(await page.locator('#msg').innerText()));

  console.log('3. разные пароли не принимаются');
  await page.locator('#p1').fill('parolparol1');
  await page.locator('#p2').fill('parolparol2');
  await page.locator('#save').click();
  await page.waitForTimeout(400);
  check('сказали про несовпадение',
    /совпад/i.test(await page.locator('#msg').innerText()));

  if (base && newPass) {
    console.log('4. настоящая смена пароля');
    await page.locator('#p1').fill(newPass);
    await page.locator('#p2').fill(newPass);
    await page.locator('#save').click();
    await page.waitForTimeout(2500);
    const msg = await page.locator('#msg').innerText();
    check('пароль сменился', /готово|получилось|смен/i.test(msg), msg.slice(0, 90));

    console.log('5. новым паролем пускает');
    const res = await page.evaluate(async ([b, e, p]) => {
      const r = await fetch(b + '/api/collections/users/auth-with-password', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ identity: e, password: p }),
      });
      return r.status;
    }, [base.replace(/\/$/, ''), email, newPass]);
    check('вход с новым паролем', res === 200, 'код ' + res);
  } else {
    console.log('4-5. живая смена пропущена (нет токена и почты)');
  }

  check('в консоли страницы нет ошибок', errors.length === 0, errors.join(' | ').slice(0, 120));
  await browser.close();
  console.log(ok ? '\nИТОГ: всё сошлось' : '\nИТОГ: есть расхождения');
  process.exit(ok ? 0 : 1);
})();
