// Число в уведомлении пишется в момент планирования, а показывается через
// сутки и позже. Здесь проверяется, что для каждого будущего показа посчитано
// СВОЁ число — иначе iPhone каждый день присылает один и тот же день (жалоба
// от 30 июля: «в приложении меняется, а в уведомлении всегда 1349»).

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/days_together_plan.dart';
import 'package:love_app/utils/couple_days.dart';

void main() {
  group('daysTogetherTicks', () {
    final start = DateTime(2022, 11, 19, 14, 30);

    test('первый показ сегодня, если час ещё не наступил', () {
      final ticks = daysTogetherTicks(
        start: start,
        from: DateTime(2026, 7, 30, 7, 0),
        count: 3,
        hour: 9,
      );
      expect(ticks.first.at, DateTime(2026, 7, 30, 9, 0));
    });

    test('первый показ завтра, если час уже прошёл', () {
      final ticks = daysTogetherTicks(
        start: start,
        from: DateTime(2026, 7, 30, 9, 0, 1),
        count: 3,
        hour: 9,
      );
      expect(ticks.first.at, DateTime(2026, 7, 31, 9, 0));
    });

    test('каждый следующий показ на сутки позже и на день больше', () {
      final ticks = daysTogetherTicks(
        start: start,
        from: DateTime(2026, 7, 30, 12, 0),
        count: 21,
        hour: 9,
      );
      expect(ticks.length, 21);
      for (var i = 1; i < ticks.length; i++) {
        expect(
          ticks[i].at.difference(ticks[i - 1].at).inHours,
          24,
          reason: 'показ $i должен идти ровно через сутки',
        );
        expect(ticks[i].days, ticks[i - 1].days + 1);
      }
    });

    test('число совпадает с тем, что покажет приложение в этот момент', () {
      final ticks = daysTogetherTicks(
        start: start,
        from: DateTime(2026, 7, 30, 12, 0),
        count: 5,
        hour: 9,
      );
      for (final tick in ticks) {
        expect(
          tick.days,
          coupleDaysTogether(timerStart: start, now: tick.at),
          reason: 'формула одна на приложение и уведомление',
        );
      }
    });

    test('месяц вперёд даёт месяц разных чисел', () {
      final ticks = daysTogetherTicks(
        start: start,
        from: DateTime(2026, 7, 30, 12, 0),
        count: 30,
      );
      expect(ticks.map((t) => t.days).toSet().length, 30);
    });

    test('дата начала в будущем даёт нули, а не минус', () {
      final ticks = daysTogetherTicks(
        start: DateTime(2027, 1, 1),
        from: DateTime(2026, 7, 30, 12, 0),
        count: 3,
      );
      expect(ticks.every((t) => t.days == 0), isTrue);
    });

    test('переход через конец месяца не ломает шаг', () {
      final ticks = daysTogetherTicks(
        start: start,
        from: DateTime(2026, 7, 30, 12, 0),
        count: 4,
        hour: 9,
      );
      expect(ticks.map((t) => t.at).toList(), [
        DateTime(2026, 7, 31, 9, 0),
        DateTime(2026, 8, 1, 9, 0),
        DateTime(2026, 8, 2, 9, 0),
        DateTime(2026, 8, 3, 9, 0),
      ]);
    });

    test('пустой план, если показов не просят', () {
      expect(
        daysTogetherTicks(
          start: start,
          from: DateTime(2026, 7, 30, 12, 0),
          count: 0,
        ),
        isEmpty,
      );
    });
  });
}
