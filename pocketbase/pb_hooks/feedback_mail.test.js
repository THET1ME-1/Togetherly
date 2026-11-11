// node pocketbase/pb_hooks/feedback_mail.test.js
//
// Обращение из приложения (11.11.2026). Google Play отклонил 1.42: в декларации
// о безопасности детей стояло «пользователи могут сообщать о проблемах, не
// выходя из приложения», а поддержка открывала почту и Telegram. Теперь форма
// живёт в приложении, а письмо ложится в ящик поддержки.
const assert = require('assert');
const F = require('./feedback_mail.js');

// Что сервер принимает.
assert.strictEqual(F.problemOf('bug', 'Не открывается лента воспоминаний'), '');
assert.strictEqual(F.problemOf('child_safety', 'В чате прислали недопустимое фото'), '');
assert.strictEqual(F.problemOf('выдумка', 'Достаточно длинный текст'), 'bad_kind');
assert.strictEqual(F.problemOf('', 'Достаточно длинный текст'), 'bad_kind');
assert.strictEqual(F.problemOf('bug', 'коротко'), 'too_short');
assert.strictEqual(F.problemOf('bug', '          '), 'too_short');
assert.strictEqual(F.problemOf('bug', 'я'.repeat(F.MAX + 1)), 'too_long');
assert.strictEqual(F.problemOf('bug', 'я'.repeat(F.MAX)), '');
// Виды обращений — те же, что в приложении (lib/models/feedback.dart).
assert.deepStrictEqual(Object.keys(F.KINDS).sort(),
  ['abuse', 'bug', 'child_safety', 'idea', 'other', 'payment']);

// Тема письма: вид и начало текста, без переносов строк.
assert.strictEqual(
  F.subjectOf('bug', 'Не открывается лента.\nВторой абзац'),
  '[Приложение] Ошибка: Не открывается лента. Второй абзац');
const long = F.subjectOf('idea', 'слово '.repeat(40));
assert.ok(long.length <= 110, 'тема не длиннее строки: ' + long.length);
// Безопасность детей видна в ящике сразу, первой меткой.
assert.ok(F.subjectOf('child_safety', 'Недопустимое фото в чате').startsWith('[БЕЗОПАСНОСТЬ ДЕТЕЙ] '));
assert.ok(F.urgent('child_safety'));
assert.ok(F.urgent('abuse'));
assert.ok(!F.urgent('idea'));

// Тело: текст человека целиком и всё, что нужно для ответа и разбора.
const body = F.bodyOf({
  id: 'r1234567890abcd', uid: 'u123', email: 'person@example.com', name: 'Аня',
  kind: 'payment', text: 'Оплатила Плюс, а он не включился', app: '1.43.0 (270)',
  platform: 'android', lang: 'ru',
});
for (const part of ['Оплатила Плюс, а он не включился', 'person@example.com', 'u123',
  '1.43.0 (270)', 'android', 'r1234567890abcd', 'Оплата']) {
  assert.ok(body.includes(part), 'в письме нет: ' + part);
}

// Письмо для ящика: от человека, с адресом для ответа, непрочитанное.
const mail = F.mailOf({
  id: 'r1', uid: 'u1', email: 'person@example.com', name: 'Аня', kind: 'child_safety',
  text: 'Недопустимое фото в чате', app: '', platform: 'ios', lang: 'en',
}, 'inbox1');
assert.deepStrictEqual(mail.mailboxIds, { inbox1: true });
assert.deepStrictEqual(mail.from, [{ name: 'Аня', email: 'person@example.com' }]);
assert.deepStrictEqual(mail.replyTo, [{ email: 'person@example.com' }]);
assert.deepStrictEqual(mail.keywords, { $flagged: true });
// У аккаунта без почты (вход через Apple со скрытым адресом и без него) письмо
// всё равно ложится, отправителем стоит сам ящик.
const anon = F.mailOf({ id: 'r2', uid: 'u2', email: '', name: '', kind: 'bug',
  text: 'Достаточно длинный текст', app: '', platform: '', lang: '' }, 'inbox1');
assert.deepStrictEqual(anon.from, [{ name: 'Togetherly', email: 'support@togetherly.day' }]);
assert.strictEqual(anon.replyTo, undefined);
assert.deepStrictEqual(anon.keywords, {});

// Дневной предел на человека.
assert.strictEqual(F.dayKey('u1', Date.UTC(2026, 10, 11, 23, 59)), 'fb_u1_2026-11-11');
assert.ok(F.PER_DAY >= 3 && F.PER_DAY <= 10);

console.log('feedback_mail: всё прошло');
