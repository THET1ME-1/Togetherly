import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/timer_item.dart';

// TOG-56 (канал, 27.10.2026): «у партнёра время одного и того же события
// смещается на несколько часов». Дата таймера уходила на сервер часами
// автора без пояса (`2026-11-20T19:00:00.000`), и телефон партнёра читал эти
// цифры своими часами: отсчёт до встречи в 19:00 по Киеву в Торонто шёл до
// 19:00 по Торонто, на семь часов позже.
//
// Таймер со временем суток — это момент, его видят оба в своих часах. Таймер
// на дату без времени (годовщина, день рождения) — календарный день, у обоих
// те же цифры. Поле `startDate` осталось часами автора: его читают сборки,
// выпущенные до правки.
void main() {
  test('таймер со временем уносит на сервер сам момент', () {
    final at = DateTime.utc(2026, 11, 20, 17).toLocal();
    final json = TimerItem(id: 't', title: 'Встреча', startDate: at, isCountdown: true).toJson();
    expect(json['startAt'], '2026-11-20T17:00:00.000Z');
    expect(DateTime.parse(json['startDate'] as String).isUtc, isFalse);
  });

  test('партнёр в другом поясе получает тот же момент', () {
    // Автор в Киеве поставил 19:00, это 17:00 UTC.
    final timer = TimerItem.fromJson({
      'id': 't',
      'title': 'Встреча',
      'startDate': '2026-11-20T19:00:00.000',
      'startAt': '2026-11-20T17:00:00.000Z',
      'isCountdown': true,
    });
    expect(timer.startDate.isAtSameMomentAs(DateTime.utc(2026, 11, 20, 17)), isTrue);
    expect(timer.startDate.isUtc, isFalse, reason: 'на экране часы читающего, а не UTC');
  });

  test('дата без времени остаётся календарным днём', () {
    final timer = TimerItem(id: 't', title: 'Годовщина', startDate: DateTime(2026, 2, 17));
    final json = timer.toJson();
    expect(json.containsKey('startAt'), isFalse);
    final back = TimerItem.fromJson(json);
    expect([back.startDate.year, back.startDate.month, back.startDate.day, back.startDate.hour],
        [2026, 2, 17, 0]);
  });

  test('момент из UTC показывается часами телефона', () {
    // Так сервер пишет таймер «вместе» при соединении пары.
    final timer = TimerItem.fromJson({
      'id': 't',
      'title': 'Вместе',
      'startDate': '2026-10-23T06:53:23.118Z',
      'isSystem': true,
    });
    expect(timer.startDate.isUtc, isFalse);
    expect(timer.startDate.isAtSameMomentAs(DateTime.utc(2026, 10, 23, 6, 53, 23, 118)), isTrue);
  });

  test('старая запись без startAt читается как раньше', () {
    final timer = TimerItem.fromJson({'id': 't', 'title': 'Встреча', 'startDate': '2026-11-20T19:00:00.000'});
    expect([timer.startDate.day, timer.startDate.hour], [20, 19]);
  });
}
