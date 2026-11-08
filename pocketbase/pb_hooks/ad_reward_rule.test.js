// node pocketbase/pb_hooks/ad_reward_rule.test.js
//
// Отзыв 08.11.2026: «реклама с монетами один раз в день, видимо считает не три
// рекламы с 3 наградами, а 3 монеты». Начисление за ролик звали ВСЕ ролики
// приложения — сундук, проба темы (два ролика), гардероб, подарки, возврат
// серии, — и каждый тратил дневной счётчик «3 ролика за монеты». Кнопка
// «Посмотреть рекламу» в профиле после сундука уже отвечала «лимит».
const assert = require('assert');
const R = require('./ad_reward_rule.js');

// Кнопка за монеты в новых сборках говорит о себе прямо.
assert.strictEqual(R.adRewardForCoins({ purpose: 'coins' }), true);
// Остальные ролики новых сборок монет не дают и счётчик не трогают.
assert.strictEqual(R.adRewardForCoins({ purpose: 'other' }), false);
assert.strictEqual(R.adRewardForCoins({ purpose: 'other', chestOpenId: 'abcdefghijklmno' }), false);
// Старые сборки цели не шлют: ролик за сундук узнаём по номеру открытия.
assert.strictEqual(R.adRewardForCoins({ chestOpenId: 'abcdefghijklmno' }), false);
// Остальное у старых сборок неотличимо от кнопки — как было.
assert.strictEqual(R.adRewardForCoins({}), true);
assert.strictEqual(R.adRewardForCoins({ groupId: 'g1' }), true);
assert.strictEqual(R.adRewardForCoins(null), true);
// Кривой номер открытия — не сундук.
assert.strictEqual(R.adRewardForCoins({ chestOpenId: 'нет' }), true);

console.log('ad_reward_rule: ок');
