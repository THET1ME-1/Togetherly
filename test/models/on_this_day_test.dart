import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/memory.dart';
import 'package:love_app/models/on_this_day.dart';

Memory _m(String id, DateTime at, {bool secret = false, String? title, String? img}) =>
    Memory(
      id: id,
      groupId: 'g',
      authorUid: 'a',
      authorName: 'a',
      type: MemoryType.photo,
      createdAt: at,
      imageUrl: img,
      title: title,
      isSecret: secret,
    );

void main() {
  final now = DateTime(2026, 9, 28, 15);

  test('месяц назад первым, дальше годы по порядку, пустые пропускаем', () {
    final shelf = onThisDay([
      _m('y1', DateTime(2025, 9, 28, 20)),
      _m('m1', DateTime(2026, 8, 28, 9)),
      _m('y3', DateTime(2023, 9, 28, 12)),
      _m('other', DateTime(2025, 9, 27)),
    ], now: now);
    expect(shelf.map((s) => s.monthsAgo == 1 ? 'm' : '${s.yearsAgo}y'),
        ['m', '1y', '3y']);
    expect(shelf[1].memories.single.id, 'y1');
  });

  test('ничего в эти дни — полки нет', () {
    expect(onThisDay([_m('x', DateTime(2025, 9, 1))], now: now), isEmpty);
    expect(onThisDay(const [], now: now), isEmpty);
  });

  test('секретное и нераскрытая капсула на полку не попадают', () {
    final capsule = _m('c', DateTime(2025, 9, 28))
      ..sealed = true
      ..openAt = DateTime(2027, 1, 1);
    final shelf = onThisDay(
        [_m('s', DateTime(2025, 9, 28), secret: true), capsule], now: now);
    expect(shelf, isEmpty);
  });

  test('несуществующее число берёт последний день месяца', () {
    expect(sameDayMonthsBack(DateTime(2026, 3, 31), 1), DateTime(2026, 2, 28));
    expect(sameDayMonthsBack(DateTime(2028, 2, 29), 12), DateTime(2027, 2, 28));
    expect(sameDayMonthsBack(DateTime(2026, 1, 15), 1), DateTime(2025, 12, 15));
  });

  test('обложка и подпись берутся из первой подходящей записи', () {
    final shelf = onThisDay([
      _m('a', DateTime(2025, 9, 28, 10), title: 'Прогулка у Днестра'),
      _m('b', DateTime(2025, 9, 28, 9), img: 'pb://media/b/x.jpg'),
    ], now: now).single;
    expect(shelf.cover, 'pb://media/b/x.jpg');
    expect(shelf.caption, 'Прогулка у Днестра');
    expect(shelf.memories.first.id, 'a');
  });

  test('форма слова «год»', () {
    expect([2, 3, 4, 5, 11, 12, 21, 22, 25].map(yearsAgoForm).toList(),
        ['few', 'few', 'few', 'many', 'many', 'many', 'one', 'few', 'many']);
  });
}
