// Правило частоты зова «пойдём порисовать».
//
// Запуск: node pocketbase/pb_hooks/draw_invite.test.js
//
// Зов уходит сам при входе в раскраску, поэтому цена ошибки здесь — поток
// пушей партнёру. Проверяем именно границы: первый зов, повтор внутри окна,
// зов после окна и мусор в отметке времени.
const { mayInvite, GAP_MS } = require('./draw_invite.js');

let ok = true;
const check = (name, cond) => {
  console.log((cond ? '  ✓ ' : '  ✗ ') + name);
  if (!cond) ok = false;
};

const now = 1_755_000_000_000; // произвольная фиксированная отметка

console.log('частота зова порисовать');
check('первый зов проходит', mayInvite(0, now, GAP_MS) === true);
check('повтор сразу — молчим', mayInvite(now, now, GAP_MS) === false);
check('через минуту — молчим', mayInvite(now - 60_000, now, GAP_MS) === false);
check(
  'за секунду до конца окна — молчим',
  mayInvite(now - GAP_MS + 1000, now, GAP_MS) === false,
);
check('ровно по окну — зовём', mayInvite(now - GAP_MS, now, GAP_MS) === true);
check('через час — зовём', mayInvite(now - 3_600_000, now, GAP_MS) === true);

console.log('мусор в данных');
check('пустая отметка — зовём', mayInvite(null, now, GAP_MS) === true);
check('строка вместо числа — зовём', mayInvite('никогда', now, GAP_MS) === true);
check('отметка из будущего не запирает', mayInvite(now + 999_999, now, GAP_MS) === true);
check('нет текущего времени — не зовём', mayInvite(0, 0, GAP_MS) === false);
check('окно не задано — берём своё', mayInvite(now - 60_000, now, 0) === false);

console.log(ok ? 'всё сошлось' : 'ЕСТЬ ОШИБКИ');
process.exit(ok ? 0 : 1);
