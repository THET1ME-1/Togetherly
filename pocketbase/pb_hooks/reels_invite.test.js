// node pocketbase/pb_hooks/reels_invite.test.js
const assert = require('assert');
const r = require('./reels_invite.js');

const now = 1_800_000_000_000;
assert.strictEqual(r.feedOf('TikTok'), 'tiktok');
assert.strictEqual(r.feedOf('youtube'), '');
assert.strictEqual(r.feedOf(''), '');

assert.ok(r.mayInvite(0, now), 'никогда не звал — можно');
assert.ok(!r.mayInvite(now - 60_000, now), 'минуту назад — рано');
assert.ok(r.mayInvite(now - r.GAP_MS, now), 'через десять минут — можно');
assert.ok(r.mayInvite(now + 60_000, now), 'отметка из будущего не запирает');

assert.strictEqual(r.message('Аня', 'tiktok').title, 'Аня зовёт смотреть TikTok');
assert.strictEqual(r.message('', 'vk').title, 'Партнёр зовёт смотреть ВК Клипы');
assert.strictEqual(r.message('Боря', '').title, 'Боря зовёт смотреть ленту');

assert.ok(r.isActive({ at: now - 60_000 }, now));
assert.ok(!r.isActive({ at: now - r.ACTIVE_MS - 1 }, now), 'старый зов истёк');
assert.ok(!r.isActive({ at: now - 60_000, stopped: true }, now), 'вышел из ленты — зова нет');
assert.ok(!r.isActive(null, now));

console.log('reels_invite: всё прошло');
