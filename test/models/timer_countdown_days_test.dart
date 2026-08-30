import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/timer_item.dart';

TimerItem _countdown(DateTime target) => TimerItem(
      id: 't',
      title: 'До встречи',
      startDate: target,
      isCountdown: true,
    );

TimerItem _countup(DateTime start) => TimerItem(
      id: 't',
      title: 'Вместе',
      startDate: start,
    );

void main() {
  group('обратный отсчёт считает СУТКИ, а не календарные дни', () {
    // Жалоба 28.08.2026: «счётчик дней сменяется в 00:00, а не когда
    // заканчивается отсчёт часов». Крупное число бралось из календаря, а часы
    // рядом — из настоящего остатка, и они расходились на целый день.

    test('осталось 2 дня и 5 часов — показываем 2', () {
      final t = _countdown(DateTime.now().add(const Duration(days: 2, hours: 5)));
      expect(t.daysElapsed, 2);
    });

    test('осталось 23 часа — это ещё не день', () {
      final t = _countdown(DateTime.now().add(const Duration(hours: 23)));
      expect(t.daysElapsed, 0);
    });

    test('день уходит вместе с последними сутками, а не в полночь', () {
      // Событие через 1 день и 1 час. Календарь мог насчитать и два дня — если
      // событие завтра, а час перевалил за полночь.
      final t = _countdown(DateTime.now().add(const Duration(days: 1, hours: 1)));
      expect(t.daysElapsed, 1);
    });

    test('крупное число и часы рядом не расходятся', () {
      final t = _countdown(DateTime.now().add(const Duration(days: 3, hours: 7)));
      expect(t.daysElapsed, t.timeElapsed.inDays);
    });

    test('прошедшая дата не уходит в минус на пустом месте', () {
      final t = _countdown(DateTime.now().subtract(const Duration(hours: 2)));
      expect(t.daysElapsed, 0);
    });
  });

  group('счёт вверх остаётся календарным', () {
    // Это решение проекта: «сколько мы вместе» считается днями календаря, на
    // нём стоят лепестковый круг и дата пары. Менять его тут нельзя.

    test('пара с полуночи сегодня — ноль дней', () {
      final now = DateTime.now();
      final t = _countup(DateTime(now.year, now.month, now.day));
      expect(t.daysElapsed, 0);
    });

    test('вчерашний вечер — уже день, даже если суток не прошло', () {
      final now = DateTime.now();
      final lateYesterday = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(hours: 2));
      final t = _countup(lateYesterday);
      expect(t.daysElapsed, 1);
    });
  });
}
