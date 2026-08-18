// Книга пары — PDF с воспоминаниями за выбранные даты. Отбор решает, что
// вообще попадёт в файл: книгу отправляют в мессенджер и печатают, поэтому
// нераскрытая капсула и секретные записи в неё не имеют права попасть.

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/memory.dart';
import 'package:love_app/models/pair_book.dart';

Memory _memory(
  String id,
  DateTime at, {
  bool secret = false,
  bool sealed = false,
  DateTime? openAt,
}) =>
    Memory(
      id: id,
      groupId: 'g',
      authorUid: 'u',
      authorName: 'Аня',
      authorAvatar: '',
      type: MemoryType.text,
      createdAt: at,
      caption: 'запись $id',
      isSecret: secret,
      sealed: sealed,
      openAt: openAt,
    );

void main() {
  final now = DateTime(2026, 8, 18);

  group('что попадает в книгу', () {
    test('записи вне периода остаются за бортом', () {
      final all = [
        _memory('до', DateTime(2025, 12, 31)),
        _memory('внутри', DateTime(2026, 3, 4)),
        _memory('после', DateTime(2026, 9, 1)),
      ];
      final picked = memoriesForBook(
        all,
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 8, 18),
        secretUnlocked: false,
        now: now,
      );
      expect(picked.map((m) => m.id), ['внутри']);
    });

    test('границы периода входят целиком, включая последний день', () {
      final all = [
        _memory('утро первого', DateTime(2026, 3, 1, 0, 5)),
        _memory('вечер последнего', DateTime(2026, 3, 31, 23, 40)),
      ];
      final picked = memoriesForBook(
        all,
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 31),
        secretUnlocked: false,
        now: now,
      );
      expect(picked, hasLength(2));
    });

    test('запечатанная капсула в книгу не идёт', () {
      final all = [
        _memory('капсула', DateTime(2026, 5, 1),
            sealed: true, openAt: DateTime(2027, 1, 1)),
        _memory('обычная', DateTime(2026, 5, 2)),
      ];
      final picked =
          memoriesForBook(all, secretUnlocked: true, now: now);
      expect(picked.map((m) => m.id), ['обычная']);
    });

    test('раскрывшаяся капсула — обычная запись', () {
      final all = [
        _memory('раскрылась', DateTime(2026, 5, 1),
            sealed: true, openAt: DateTime(2026, 6, 1)),
      ];
      expect(memoriesForBook(all, secretUnlocked: false, now: now),
          hasLength(1));
    });

    test('секретные попадают только при снятом замке', () {
      final all = [_memory('тайна', DateTime(2026, 5, 1), secret: true)];
      expect(memoriesForBook(all, secretUnlocked: false, now: now), isEmpty);
      expect(memoriesForBook(all, secretUnlocked: true, now: now), hasLength(1));
    });

    test('книга читается от старого к новому', () {
      final all = [
        _memory('третья', DateTime(2026, 5, 3)),
        _memory('первая', DateTime(2026, 5, 1)),
        _memory('вторая', DateTime(2026, 5, 2)),
      ];
      expect(memoriesForBook(all, secretUnlocked: false, now: now)
          .map((m) => m.id), ['первая', 'вторая', 'третья']);
    });
  });

  group('периоды', () {
    test('«за всё время» не ставит границ', () {
      final range = bookRangeOf(BookPeriod.allTime, now: now);
      expect(range.from, isNull);
      expect(range.to, isNull);
    });

    test('«этот год» берёт с первого января по сегодня', () {
      final range = bookRangeOf(BookPeriod.thisYear, now: now);
      expect(range.from, DateTime(2026, 1, 1));
      expect(range.to, DateTime(2026, 8, 18));
    });

    test('«этот месяц» берёт с первого числа', () {
      final range = bookRangeOf(BookPeriod.thisMonth, now: now);
      expect(range.from, DateTime(2026, 8, 1));
      expect(range.to, DateTime(2026, 8, 18));
    });
  });

  group('страницы книги', () {
    test('записи одного дня идут одной главой', () {
      final days = bookDays([
        _memory('a', DateTime(2026, 5, 1, 9)),
        _memory('b', DateTime(2026, 5, 1, 22)),
        _memory('c', DateTime(2026, 5, 2, 8)),
      ]);
      expect(days, hasLength(2));
      expect(days.first.day, DateTime(2026, 5, 1));
      expect(days.first.memories, hasLength(2));
      expect(days.last.memories.single.id, 'c');
    });

    test('дни идут по порядку', () {
      final days = bookDays([
        _memory('поздняя', DateTime(2026, 5, 9)),
        _memory('ранняя', DateTime(2026, 5, 2)),
      ]);
      expect(days.map((d) => d.day),
          [DateTime(2026, 5, 2), DateTime(2026, 5, 9)]);
    });

    test('пустой список глав не рождает', () {
      expect(bookDays(const []), isEmpty);
    });
  });
}
