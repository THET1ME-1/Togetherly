// Правила сброса пароля через партнёра.
//
// Запуск: node pocketbase/pb_hooks/partner_reset.test.js
//
// Код из шести цифр открывает чужой аккаунт целиком, поэтому проверяем
// границы: срок кода, число попыток, частоту запросов и выбор партнёра.
const r = require('./partner_reset.js');

let ok = true;
const check = (name, cond) => {
  console.log((cond ? '  ✓ ' : '  ✗ ') + name);
  if (!cond) ok = false;
};

const now = 1_793_000_000_000;

console.log('частота запросов');
{
  const first = r.mayRequest([], now);
  check('первый запрос проходит', first.ok === true && first.history.length === 1);
  const soon = r.mayRequest([now - 60 * 1000], now);
  check('повтор через минуту — рано', soon.ok === false && soon.why === 'gap');
  const later = r.mayRequest([now - 3 * 60 * 1000], now);
  check('через три минуты можно', later.ok === true && later.history.length === 2);
  const five = [1, 2, 3, 4, 5].map((h) => now - h * 60 * 60 * 1000);
  check('шестой за сутки — нельзя', r.mayRequest(five, now).why === 'day');
  const old = [1, 2, 3, 4, 25].map((h) => now - h * 60 * 60 * 1000);
  const fresh = r.mayRequest(old, now);
  check('запрос старше суток не считается', fresh.ok === true && fresh.history.length === 5);
  check('мусор в истории не ломает', r.mayRequest(['x', null, NaN], now).ok === true);
}

console.log('проверка кода');
{
  const state = { code: '482913', at: now, tries: 0 };
  check('верный код', r.checkCode(state, '482913', now + 1000).verdict === 'ok');
  check('пробелы и тире в коде не мешают', r.checkCode(state, '482 913', now).verdict === 'ok');
  const wrong = r.checkCode({ ...state }, '111111', now);
  check('неверный код считает попытку', wrong.verdict === 'wrong' && wrong.left === r.MAX_TRIES - 1);
  check('через 10 минут код истёк',
    r.checkCode(state, '482913', now + r.CODE_TTL_MS + 1).verdict === 'expired');
  check('после пяти промахов код заперт',
    r.checkCode({ ...state, tries: r.MAX_TRIES }, '482913', now).verdict === 'locked');
  const last = r.checkCode({ ...state, tries: r.MAX_TRIES - 1 }, '000000', now);
  check('пятый промах запирает код', last.verdict === 'locked' && last.left === 0);
  check('запроса нет', r.checkCode(null, '482913', now).verdict === 'none');
  check('пустой ввод — промах, а не успех', r.checkCode({ ...state }, '', now).verdict === 'wrong');
}

console.log('выбор партнёра');
{
  const groups = [
    { id: 'g1', members: '["me","old"]', disbanded: 1 },
    { id: 'g2', members: '["me"]', disbanded: 0 },
    { id: 'g3', members: ['masha', 'me'], disbanded: 0 },
    { id: 'g4', members: '["me","other"]', disbanded: 0 },
  ];
  const pick = r.pickPartner('me', groups);
  check('берётся первая живая пара из двух', pick && pick.groupId === 'g3' && pick.partner === 'masha');
  check('распущенная и пустая пропущены', r.pickPartner('me', groups.slice(0, 2)) === null);
  check('чужая пара не годится', r.pickPartner('me', [{ id: 'x', members: '["a","b"]', disbanded: 0 }]) === null);
  check('кривой список не ломает', r.pickPartner('me', [{ id: 'x', members: '{', disbanded: 0 }]) === null);
}

console.log('пароль');
{
  check('короче 8 нельзя', r.passwordProblem('1234567') === 'short');
  check('8 символов можно', r.passwordProblem('12345678') === null);
  check('длиннее 71 нельзя', r.passwordProblem('x'.repeat(72)) === 'long');
  check('не строка — нельзя', r.passwordProblem(null) === 'short');
}

console.log(ok ? 'всё верно' : 'ЕСТЬ ОШИБКИ');
process.exit(ok ? 0 : 1);
