import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  chatKey, closedMessage, closedSeenKey, isMarked, isReplyComment, markDelivery,
  noteSeenKey, replyBody, replyMessage, SENT_MARK,
} from '../src/replies.js';

// Ответ человеку пишется комментарием к задаче, первой строкой со знаком «>».
// Всё остальное в задаче — разбор для себя, и наружу оно уходить не должно.

test('комментарий со знаком в начале уходит человеку', () => {
  assert.equal(isReplyComment('> Починили, приедет с обновлением'), true);
  assert.equal(isReplyComment('  > с отступом тоже'), true);
});

test('служебная запись остаётся в Todoist', () => {
  assert.equal(isReplyComment('Причина — гонка в сессии PocketBase'), false);
  assert.equal(isReplyComment('Скриншот к жалобе про геолокацию'), false);
});

test('пустое и не-строка не ломают разбор', () => {
  assert.equal(isReplyComment(''), false);
  assert.equal(isReplyComment(null), false);
  assert.equal(isReplyComment(undefined), false);
});

test('маркер срезается вместе с пробелом после него', () => {
  assert.equal(replyBody('>   Уже чиним'), 'Уже чиним');
  assert.equal(replyBody('>Без пробела'), 'Без пробела');
});

test('цитата Todoist снимается со всех строк, а не только с первой', () => {
  // Todoist оформляет ответ цитатой и ставит маркер в начале КАЖДОЙ строки.
  // Со срезом только первого символа стрелки уезжали человеку в текст.
  const quoted = '> Привет!\n>\n> Второй абзац\n> и его продолжение';
  assert.equal(replyBody(quoted), 'Привет!\n\nВторой абзац\nи его продолжение');
});

test('стрелка в середине строки остаётся на месте', () => {
  assert.equal(replyBody('> Смотри: 5 > 3'), 'Смотри: 5 > 3');
});

test('строки без маркера тоже доезжают', () => {
  assert.equal(replyBody('> Привет!\nВторой абзац'), 'Привет!\nВторой абзац');
});

test('в сообщении видно, что это ответ разработчика', () => {
  const msg = replyMessage('> Починили');
  assert.ok(msg.includes('Ответ от разработчика'));
  assert.ok(msg.endsWith('Починили'));
});

test('пустой ответ не отправляется', () => {
  assert.equal(replyMessage('>'), '');
  assert.equal(replyMessage('>    '), '');
});

test('закрытая задача называет себя', () => {
  assert.ok(closedMessage('Виджеты не обновляются').includes('Виджеты не обновляются'));
});

test('задача без названия всё равно даёт понятное сообщение', () => {
  assert.ok(closedMessage('').length > 10);
  assert.ok(closedMessage(null).length > 10);
});

test('ключи KV не пересекаются между собой', () => {
  const keys = [chatKey('1'), noteSeenKey('1'), closedSeenKey('1')];
  assert.equal(new Set(keys).size, 3);
});

// Написав ответ, человек не должен гадать, дошёл ли он: бот дописывает исход
// в тот же комментарий.

test('доставленный ответ помечается', () => {
  const marked = markDelivery('> Починили', { ok: true });
  assert.ok(marked.startsWith('> Починили'));
  assert.ok(marked.includes(SENT_MARK));
});

test('недоставленный называет причину', () => {
  const marked = markDelivery('> Починили', { ok: false, reason: 'чат неизвестен' });
  assert.ok(marked.includes('чат неизвестен'));
});

test('повторный проход не наращивает хвост', () => {
  const once = markDelivery('> Починили', { ok: true });
  assert.equal(markDelivery(once, { ok: true }), once);
  assert.equal(isMarked(once), true);
});

test('без причины отказ всё равно понятен', () => {
  assert.ok(markDelivery('> текст', { ok: false }).includes('Не отправлено'));
});

test('непомеченный комментарий виден как непомеченный', () => {
  assert.equal(isMarked('> Починили'), false);
});
