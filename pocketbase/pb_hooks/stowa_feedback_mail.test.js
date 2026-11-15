// node pocketbase/pb_hooks/stowa_feedback_mail.test.js
// Обращение из Stowa (15.11.2026): что принимается и как выглядит письмо в ящике.
const assert = require('assert');
const F = require('./stowa_feedback_mail.js');

assert.strictEqual(F.problemOf({ kind: 'bug', text: 'Не сохраняется фото в заметке' }), '');
assert.strictEqual(F.problemOf({ kind: 'question', text: 'Как перенести заметки?', email: 'a@b.co' }), '');
assert.strictEqual(F.problemOf({ kind: 'payment', text: 'Достаточно длинный текст' }), 'bad_kind');
assert.strictEqual(F.problemOf({ kind: 'bug', text: 'коротко' }), 'too_short');
assert.strictEqual(F.problemOf({ kind: 'bug', text: 'я'.repeat(F.MAX + 1) }), 'too_long');
assert.strictEqual(F.problemOf({ kind: 'bug', text: 'Достаточно длинный текст', email: 'не почта' }), 'bad_email');
// виды — те же, что в Stowa (FeedbackKind в lib/features/settings/feedback_screen.dart)
assert.deepStrictEqual(Object.keys(F.KINDS).sort(), ['bug', 'idea', 'question']);

assert.strictEqual(F.subjectOf({ kind: 'idea', text: 'Виджет\nпоменьше' }), '[Stowa] Идея: Виджет поменьше');

const f = { id: 'r1', kind: 'bug', text: 'Не открывается', email: 'p@x.io', device: 'Stowa 0.1.3 · Xiaomi · Android 16', app: '0.1.3', platform: 'android', lang: 'ru' };
const mail = F.mailOf(f, 'inbox');
assert.deepStrictEqual(mail.from, [{ name: 'p@x.io', email: 'p@x.io' }]);
assert.deepStrictEqual(mail.replyTo, [{ email: 'p@x.io' }]);
assert.ok(mail.bodyValues.b.value.includes('Телефон: Stowa 0.1.3 · Xiaomi · Android 16'));
// без почты письмо от имени Stowa, ответить некуда — так и написано
const quiet = F.mailOf({ ...f, email: '' }, 'inbox');
assert.deepStrictEqual(quiet.from, [{ name: 'Stowa', email: 'support@togetherly.day' }]);
assert.strictEqual(quiet.replyTo, undefined);
assert.ok(quiet.bodyValues.b.value.includes('Ответить: почту не оставили'));
console.log('stowa_feedback_mail: всё сходится');
