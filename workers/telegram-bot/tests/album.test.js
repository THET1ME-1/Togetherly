import { test } from 'node:test';
import assert from 'node:assert/strict';
import { albumDoneKey, albumPartKey, albumPrefix, isCollector, mergeAlbum } from '../src/album.js';

// Альбом из Telegram приходит несколькими апдейтами с одним media_group_id, и
// бот заводил задачу на каждое фото: жалоба kit_fly 21.08.2026 разлетелась на
// три задачи — текст в одной, два скриншота в двух других.

test('ключи части и группы строятся от media_group_id', () => {
  assert.equal(albumPrefix('123'), 'mg:123:');
  assert.equal(albumPartKey('123', 45), 'mg:123:45');
});

test('отметка «собрано» лежит вне префикса частей', () => {
  assert.equal(albumDoneKey('123'), 'done:123');
  assert.ok(!albumDoneKey('123').startsWith(albumPrefix('123')),
      'иначе её сочтут частью альбома');
});

test('собирает альбом тот, чьё сообщение пришло первым', () => {
  assert.equal(isCollector([45, 46, 47], 45), true);
  assert.equal(isCollector([45, 46, 47], 46), false);
  assert.equal(isCollector([47, 45, 46], 45), true, 'порядок в списке не важен');
});

test('одинокая часть тоже собирает сама себя', () => {
  assert.equal(isCollector([45], 45), true);
});

test('пустой список никого не назначает: собирать нечего', () => {
  assert.equal(isCollector([], 45), false);
});

test('подпись берётся из той части, где её написали', () => {
  const merged = mergeAlbum([
    { messageId: 46, fileId: 'b', mime: 'image/jpeg', caption: '' },
    { messageId: 45, fileId: 'a', mime: 'image/jpeg', caption: 'Экран дёргается' },
  ]);
  assert.equal(merged.caption, 'Экран дёргается');
});

test('вложения идут в том порядке, в каком их отправили', () => {
  const merged = mergeAlbum([
    { messageId: 47, fileId: 'c', mime: 'image/jpeg', caption: '' },
    { messageId: 45, fileId: 'a', mime: 'image/jpeg', caption: 'текст' },
    { messageId: 46, fileId: 'b', mime: 'video/mp4', caption: '' },
  ]);
  assert.deepEqual(merged.media.map((m) => m.fileId), ['a', 'b', 'c']);
  assert.equal(merged.media[2].mime, 'image/jpeg');
});

test('две подписи в одном альбоме — берём первую по порядку отправки', () => {
  const merged = mergeAlbum([
    { messageId: 46, fileId: 'b', mime: 'image/jpeg', caption: 'вторая' },
    { messageId: 45, fileId: 'a', mime: 'image/jpeg', caption: 'первая' },
  ]);
  assert.equal(merged.caption, 'первая');
});
