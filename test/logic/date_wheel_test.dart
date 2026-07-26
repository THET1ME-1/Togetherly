import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/date_wheel.dart';

/// Барабан даты: 31 марта при переходе на февраль обязано стать 28 или 29.
/// `DateTime(2026, 2, 31)` молча даёт 3 марта — из-за этого дата уезжала бы,
/// пока человек просто крутит месяц.
void main() {
  group('длина месяца', () {
    test('обычные месяцы', () {
      expect(DateWheel.daysInMonth(2026, 1), 31);
      expect(DateWheel.daysInMonth(2026, 4), 30);
      expect(DateWheel.daysInMonth(2026, 12), 31);
    });

    test('февраль в обычный и високосный год', () {
      expect(DateWheel.daysInMonth(2026, 2), 28);
      expect(DateWheel.daysInMonth(2024, 2), 29);
    });

    test('столетия считаются по правилу, а не на глаз', () {
      expect(DateWheel.isLeap(2000), isTrue);
      expect(DateWheel.isLeap(1900), isFalse);
      expect(DateWheel.daysInMonth(1900, 2), 28);
      expect(DateWheel.daysInMonth(2000, 2), 29);
    });
  });

  group('прижатие дня', () {
    test('31 марта → 28 февраля', () {
      expect(DateWheel.clampDay(31, 2026, 2), 28);
    });

    test('31 марта → 29 февраля в високосный', () {
      expect(DateWheel.clampDay(31, 2024, 2), 29);
    });

    test('день, который влезает, не трогаем', () {
      expect(DateWheel.clampDay(15, 2026, 2), 15);
      expect(DateWheel.clampDay(30, 2026, 4), 30);
    });

    test('нулевой и отрицательный день прижимаются к первому', () {
      expect(DateWheel.clampDay(0, 2026, 5), 1);
      expect(DateWheel.clampDay(-3, 2026, 5), 1);
    });
  });

  group('сборка даты', () {
    test('не перескакивает в следующий месяц', () {
      final d = DateWheel.build(year: 2026, month: 2, day: 31);
      expect(d.month, 2);
      expect(d.day, 28);
    });

    test('время переносится как есть', () {
      final d =
          DateWheel.build(year: 2026, month: 7, day: 26, hour: 14, minute: 5);
      expect(d, DateTime(2026, 7, 26, 14, 5));
    });
  });
}
