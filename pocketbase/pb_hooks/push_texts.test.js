// node pocketbase/pb_hooks/push_texts.test.js
//
// Уведомления хуков на языке получателя (отзыв в App Store 19.08.2026: «The
// notification and widgets are in Russian though the app I have set to English»).
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const T = require('./push_texts.js');

// Каждый текст есть на всех девяти языках, с теми же подстановками.
for (const key of Object.keys(T.TEXTS)) {
  const variants = T.TEXTS[key];
  const marks = (variants.ru.match(/\{[a-z]+\}/g) || []);
  for (const lang of T.LANGS) {
    assert.ok(variants[lang], `${key}: нет ${lang}`);
    for (const m of marks) assert.ok(variants[lang].includes(m), `${key}/${lang}: нет ${m}`);
  }
}

assert.strictEqual(T.t('draw_title', 'en', { name: 'Anna' }), 'Anna invites you to draw');
assert.strictEqual(T.t('plusgift_anon', 'uk'), 'Вам подарували повний доступ');
// Сборка старше поля `users.lang` — русский, как было.
assert.strictEqual(T.t('comment', ''), 'Комментарий к воспоминанию');
assert.strictEqual(T.t('comment', undefined), 'Комментарий к воспоминанию');
assert.strictEqual(T.t('comment', 'ja'), 'Комментарий к воспоминанию');

// В хуках не осталось русских текстов уведомлений мимо таблицы.
for (const [file, old] of [
  ['draw_invite.pb.js', '" зовёт порисовать"'],
  ['partner_reset.pb.js', '" восстанавливает доступ"'],
  ['partner_reset.pb.js', '"Кто-то пытался войти в ваш аккаунт"'],
  ['coins.pb.js', '" подарил(а) вам полный доступ"'],
  ['lava.pb.js', '" подарил(а) вам полный доступ"'],
  ['lava_checkout.pb.js', '" подарил(а) вам полный доступ"'],
  ['gift_push.js', '" тебе подарок 🎁"'],
  ['reels_invite.js', '" зовёт смотреть "'],
]) {
  const src = fs.readFileSync(path.join(__dirname, file), 'utf8');
  assert.ok(!src.includes(old), `${file}: ${old} мимо push_texts.js`);
}

console.log('push_texts: всё прошло');
