import { test } from 'node:test';
import assert from 'node:assert/strict';
import { isBlocked } from '../src/blocklist.js';

// Отдельные люди пишут в бота не по делу и после ответов не унимаются. Для
// таких заведён список: их сообщения бот не разбирает, задач не заводит и
// ответов из Todoist им не пересылает.

test('человек из списка заблокирован по числовому id', () => {
  assert.equal(isBlocked({ id: 5259635693, username: 'Dimon9313' }), true);
});

test('id узнаётся и строкой — Telegram шлёт chat_id числом, KV хранит текстом', () => {
  assert.equal(isBlocked({ id: '5259635693' }), true);
});

test('имя узнаётся в любом регистре и со знаком', () => {
  assert.equal(isBlocked({ username: 'dimon9313' }), true);
  assert.equal(isBlocked({ username: '@DIMON9313' }), true);
});

test('человек сменил имя, но id остался — блокировка держится', () => {
  assert.equal(isBlocked({ id: 5259635693, username: 'novoe_imya' }), true);
});

test('остальные пишут как раньше', () => {
  assert.equal(isBlocked({ id: 876423713, username: 'the_time01' }), false);
});

test('пустой отправитель не роняет разбор', () => {
  assert.equal(isBlocked({}), false);
  assert.equal(isBlocked(null), false);
  assert.equal(isBlocked(undefined), false);
});
