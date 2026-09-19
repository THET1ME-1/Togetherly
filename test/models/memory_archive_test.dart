// Архив воспоминаний из профиля.
//
// До 19.09.2026 он брал по одному кадру с записи (только `imageUrl`), не брал
// видео вовсе, а текст писал `codeUnits` — русские буквы превращались в мусор,
// потому что ZIP ждёт байты, а не единицы UTF-16.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/memory.dart';
import 'package:love_app/models/memory_archive.dart';

Memory _m(String id, DateTime at,
        {List<String>? urls,
        String? video,
        String? caption,
        bool sealed = false,
        DateTime? openAt}) =>
    Memory(
      id: id,
      groupId: 'g',
      authorUid: 'u',
      authorName: 'Саша',
      type: MemoryType.photo,
      createdAt: at,
      imageUrls: urls,
      imageUrl: urls?.first,
      videoUrl: video,
      caption: caption,
      sealed: sealed,
      openAt: openAt,
    );

void main() {
  final at = DateTime(2026, 9, 5, 13, 5, 7);

  test('в архив идут все кадры и ролик каждой записи', () {
    final entries = archiveEntries([
      _m('a', at,
          urls: ['pb://media/a/1.webp', 'pb://media/a/2.webp'],
          video: 'pb://media/a/v.mp4'),
      _m('b', at.add(const Duration(days: 1)), urls: ['pb://media/b/1.jpg']),
    ], now: DateTime(2026, 9, 19));
    expect(entries, hasLength(4));
    expect(entries.map((e) => e.path), [
      'Media/2026-09/Togetherly_20260905_130507_01.webp',
      'Media/2026-09/Togetherly_20260905_130507_02.webp',
      'Media/2026-09/Togetherly_20260905_130507_03.mp4',
      'Media/2026-09/Togetherly_20260906_130507_01.jpg',
    ]);
  });

  test('одинаковые имена не затирают друг друга', () {
    final entries = archiveEntries([
      _m('a', at, urls: ['pb://media/a/1.webp']),
      _m('b', at, urls: ['pb://media/b/1.webp']),
    ], now: DateTime(2026, 9, 19));
    expect(entries.map((e) => e.path).toSet(), hasLength(2));
  });

  test('запечатанная капсула в архив не идёт', () {
    final entries = archiveEntries([
      _m('a', at,
          urls: ['pb://media/a/1.webp'],
          sealed: true,
          openAt: DateTime(2027, 1, 1)),
    ], now: DateTime(2026, 9, 19));
    expect(entries, isEmpty);
  });

  test('текст записей — UTF-8, русские буквы целы', () {
    final memories = [_m('a', at, urls: ['pb://media/a/1.webp'], caption: 'Лето на Днестре')];
    final entries = archiveEntries(memories, now: DateTime(2026, 9, 19));
    final bytes = archiveText(memoriesText(memories, entries));
    final back = utf8.decode(bytes);
    expect(back, contains('Лето на Днестре'));
    expect(back, contains('Саша'));
    expect(back, contains('Media/2026-09/Togetherly_20260905_130507_01.webp'));
    // Порча прежней записи: единица UTF-16 «Л» (0x41B) усекалась до байта.
    expect(bytes, isNot(contains(0x1B)));
  });
}
