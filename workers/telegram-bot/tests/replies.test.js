import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  chatKey, closedMessage, closedSeenKey, isReplyComment, noteSeenKey,
  replyBody, replyMessage,
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
