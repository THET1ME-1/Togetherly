// Кольцо и сетка точек показывают одну и ту же разметку совместного времени.
// Ошибка здесь видна не сразу: виджет обновляется раз в сутки, и «кольцо почти
// замкнулось, а точка не загорелась» всплывает через месяцы после релиза.

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/year_progress.dart';

void main() {
  group('YearProgress', () {
    test('годовщина ещё не наступила — год не засчитан', () {
      final p = YearProgress.between(
        DateTime(2020, 9, 30),
        DateTime(2021, 9, 29),
      );
      expect(p.yearsCompleted, 0);
      expect(p.daysToNextAnniversary, 1);
      expect(p.nextAnniversary, DateTime(2021, 9, 30));
    });

    test('в день годовщины год засчитан, круг обнулился', () {
      final p = YearProgress.between(
        DateTime(2020, 9, 30),
        DateTime(2021, 9, 30),
      );
      expect(p.yearsCompleted, 1);
      expect(p.daysIntoYear, 0);
      expect(p.ringProgress, 0);
      expect(p.monthsCompleted, 12);
    });

    test('пять лет и десять дней — разметка из хендофа', () {
      final p = YearProgress.between(
        DateTime(2020, 9, 30),
        DateTime(2025, 10, 10),
      );
      expect(p.yearsCompleted, 5);
      expect(p.daysIntoYear, 10);
      expect(p.monthsCompleted, 60);
      expect(p.daysToNextAnniversary, 355);
      expect(p.nextAnniversary, DateTime(2026, 9, 30));
    });

    test('доля кольца растёт вместе с днями внутри года', () {
      final start = DateTime(2020, 1, 1);
      final tenth = YearProgress.between(start, DateTime(2020, 1, 11));
      final half = YearProgress.between(start, DateTime(2020, 7, 1));

      expect(tenth.ringProgress, closeTo(10 / 365, 0.0001));
      expect(half.ringProgress, greaterThan(tenth.ringProgress));
      expect(half.ringProgress, lessThan(1));
    });

    test('месяц засчитывается по календарю, а не по тридцати суткам', () {
      final start = DateTime(2024, 1, 31);
      expect(
        YearProgress.between(start, DateTime(2024, 2, 29)).monthsCompleted,
        0,
        reason: 'день короче исходного — месяц ещё не полный',
      );
      expect(
        YearProgress.between(start, DateTime(2024, 3, 31)).monthsCompleted,
        2,
      );
    });

    test('високосный февраль не отматывает прогресс назад', () {
      final start = DateTime(2020, 2, 29);
      final p = YearProgress.between(start, DateTime(2021, 3, 1));
      // 29 февраля в невисокосном году DateTime переносит на 1 марта: пара
      // отмечает годовщину в первый существующий день.
      expect(p.yearsCompleted, 1);
      expect(p.daysIntoYear, 0);
    });

    test('дата начала в будущем не даёт отрицательных дней', () {
      final p = YearProgress.between(
        DateTime(2030, 1, 1),
        DateTime(2026, 7, 27),
      );
      expect(p.daysTotal, 0);
      expect(p.yearsCompleted, 0);
      expect(p.monthsCompleted, 0);
    });

    test('сетка растёт шестилетиями: рядов хватает на текущий месяц', () {
      final p = YearProgress.between(
        DateTime(2010, 1, 1),
        DateTime(2017, 3, 1),
      );
      expect(p.monthsCompleted, 86);
      // Больше 72 месяцев — сетка расширяется до двенадцати рядов.
      expect((p.monthsCompleted ~/ 72 + 1) * 6, 12);
    });
  });
}
