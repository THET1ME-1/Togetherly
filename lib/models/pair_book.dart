import 'package:flutter/foundation.dart';

import 'memory.dart';

/// Пресеты периода для книги пары.
enum BookPeriod { allTime, thisYear, thisMonth, custom }

/// Границы периода: `null` — без ограничения с этой стороны.
@immutable
class BookRange {
  final DateTime? from;
  final DateTime? to;

  const BookRange({this.from, this.to});
}

BookRange bookRangeOf(BookPeriod period, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final day = DateTime(today.year, today.month, today.day);
  return switch (period) {
    BookPeriod.allTime => const BookRange(),
    BookPeriod.thisYear => BookRange(from: DateTime(day.year, 1, 1), to: day),
    BookPeriod.thisMonth =>
      BookRange(from: DateTime(day.year, day.month, 1), to: day),
    BookPeriod.custom => BookRange(from: null, to: day),
  };
}

/// Что попадёт в книгу.
///
/// Книгу отправляют в мессенджер и печатают, поэтому нераскрытая капсула сюда
/// не идёт никогда (её содержимое не видел даже автор), а секретные записи —
/// только при снятом замке: иначе PDF выдал бы то, что закрыто пином.
///
/// Порядок обратный ленте: там новое сверху, а книга читается с начала.
List<Memory> memoriesForBook(
  List<Memory> all, {
  DateTime? from,
  DateTime? to,
  required bool secretUnlocked,
  DateTime? now,
}) {
  final moment = now ?? DateTime.now();
  // Последний день входит целиком: человек выбрал «по 31 марта», а не «до
  // полуночи 31-го».
  final until = to == null
      ? null
      : DateTime(to.year, to.month, to.day, 23, 59, 59, 999);
  final since = from == null ? null : DateTime(from.year, from.month, from.day);

  final out = all.where((m) {
    if (m.sealedNow(moment)) return false;
    if (m.isSecret && !secretUnlocked) return false;
    if (since != null && m.createdAt.isBefore(since)) return false;
    if (until != null && m.createdAt.isAfter(until)) return false;
    return true;
  }).toList();
  out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return out;
}

/// День книги: заголовок главы и всё, что в этот день произошло.
@immutable
class BookDay {
  final DateTime day;
  final List<Memory> memories;

  const BookDay(this.day, this.memories);
}

/// Разбивка отобранных записей по дням — главы книги.
List<BookDay> bookDays(List<Memory> memories) {
  final byDay = <DateTime, List<Memory>>{};
  for (final m in memories) {
    final day = DateTime(m.createdAt.year, m.createdAt.month, m.createdAt.day);
    byDay.putIfAbsent(day, () => <Memory>[]).add(m);
  }
  final days = byDay.keys.toList()..sort();
  return [for (final d in days) BookDay(d, byDay[d]!)];
}
