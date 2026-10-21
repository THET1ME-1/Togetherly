// node pocketbase/pb_hooks/gift_push.test.js
const assert = require('assert');
const r = require('./gift_push.js');

const now = 1_800_000_000_000;
const MIN = 60_000;
const gift = (over) => ({
  state: 'sent', sender: 'anya', recipient: 'borya', deliverAt: now, ...over,
});

// TOG-10: подарок дошёл до сервера, а парень о нём не узнал — пуша о
// подарке не было вовсе.
assert.ok(r.pushOnCreate(gift(), now), 'обычный подарок партнёру — пуш сразу');
assert.ok(r.pushOnCreate(gift({ deliverAt: now + 30_000 }), now), 'доставка через полминуты — тоже сразу');
assert.ok(!r.pushOnCreate(gift({ sender: 'chest', recipient: 'anya' }), now), 'оставила себе из сундука — пушить некому');
assert.ok(!r.pushOnCreate(gift({ state: 'reacted' }), now), 'уже открыт — молчим');
assert.ok(!r.pushOnCreate(gift({ recipient: 'anya', sender: 'anya' }), now), 'себе от себя — молчим');
assert.ok(!r.pushOnCreate(gift({ recipient: '' }), now), 'без получателя — молчим');
assert.ok(!r.pushOnCreate(gift({ deliverAt: now + 24 * 60 * MIN }), now), 'письмо идёт сутки — пуш в момент доставки');
assert.ok(!r.pushOnCreate(null, now));

// Отложенный подарок говорит о себе кроном, когда доставка наступила.
const letter = gift({ deliverAt: now - 2 * MIN });
const created = now - 24 * 60 * MIN;
assert.ok(r.dueInWindow(letter, now - 5 * MIN, now, created), 'письмо доставлено в этом окне');
assert.ok(!r.dueInWindow(letter, now - MIN, now, created), 'доставлено до окна — уже сказали');
assert.ok(!r.dueInWindow(gift({ deliverAt: now + MIN }), now - 5 * MIN, now, created), 'ещё летит');
assert.ok(!r.dueInWindow(gift({ deliverAt: now - 2 * MIN }), now - 5 * MIN, now, now - 2 * MIN),
  'пришёл сразу — пуш уже был при создании');
assert.ok(!r.dueInWindow(gift({ deliverAt: now - 2 * MIN, state: 'reacted' }), now - 5 * MIN, now, created),
  'открыт раньше доставки не бывает, но и тогда молчим');

// Окно крона: прошлый проход, а без него — один шаг назад. Окна идут встык.
assert.strictEqual(r.windowFrom(now - 5 * MIN, now), now - 5 * MIN);
assert.strictEqual(r.windowFrom(0, now), now - r.CRON_STEP_MS);
assert.strictEqual(r.windowFrom(now + MIN, now), now - r.CRON_STEP_MS, 'отметка из будущего не запирает');
assert.strictEqual(r.windowFrom(now - 3 * 60 * MIN, now), now - r.CRON_STEP_MS,
  'сервер долго лежал — старые подарки не будим пачкой');

// Текст: имя дарителя в заголовке, глагол по роду.
assert.deepStrictEqual(r.message('Аня', 'female', 'rose'),
  { title: 'Аня', body: 'Прислала тебе подарок 🎁' });
assert.strictEqual(r.message('Боря', 'male', 'rose').body, 'Прислал тебе подарок 🎁');
assert.strictEqual(r.message('Саша', '', 'rose').body, 'Прислал(а) тебе подарок 🎁');
assert.strictEqual(r.message('  ', 'female', 'rose').title, 'Партнёр');
assert.strictEqual(r.message('Аня', 'female', 'frame_cat').body, 'Отдала тебе свою рамку для аватарки');
assert.strictEqual(r.message('Боря', 'male', 'frame_cat').body, 'Отдал тебе свою рамку для аватарки');

console.log('gift_push: всё прошло');
