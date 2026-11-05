// Звания за часы в приложении (план 2026-11-05-ranks-by-hours, задача 3):
// звание по секундам, прогресс до следующего и разбор порогов с сервера.
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/rank.dart';

void main() {
  const h = 3600;

  group('звание по часам', () {
    test('ноль секунд — Искра', () {
      expect(rankFor(0, kRankHours), 0);
    });

    test('ровно порог — уже новое звание, секундой меньше — прежнее', () {
      expect(rankFor(15 * h, kRankHours), 5);
      expect(rankFor(15 * h - 1, kRankHours), 4);
    });

    test('после последнего порога — Навсегда', () {
      expect(rankFor(10000 * h, kRankHours), kRankHours.length - 1);
    });

    test('порогов четырнадцать, по возрастанию, первый ноль', () {
      expect(kRankHours.length, 14);
      expect(kRankHours.first, 0);
      for (var i = 1; i < kRankHours.length; i++) {
        expect(kRankHours[i], greaterThan(kRankHours[i - 1]));
      }
    });
  });

  group('прогресс', () {
    test('середина ступени', () {
      final p = progressOf(2 * h, kRankHours); // между 1 ч и 3 ч
      expect(p.rank, 1);
      expect(p.next, 2);
      expect(p.fraction, closeTo(0.5, 1e-9));
      expect(p.leftSeconds, 1 * h);
    });

    test('на последнем звании полоска полная и следующего нет', () {
      final p = progressOf(400 * h, kRankHours);
      expect(p.rank, 13);
      expect(p.next, isNull);
      expect(p.fraction, 1);
      expect(p.leftSeconds, 0);
    });
  });

  group('пороги с сервера', () {
    test('правильный список принимается', () {
      final list = List<num>.generate(14, (i) => i * 2);
      expect(parseRankHours(list), list);
    });

    test('мусор — запасные пороги', () {
      for (final bad in [
        null,
        'x',
        <num>[],
        [0, 5, 3],
        [1, 2, 3],
        List<num>.filled(14, 1),
        [0, 'a'],
      ]) {
        expect(parseRankHours(bad), kRankHours, reason: '$bad');
      }
    });

    test(
      'другое число ступеней — запасные пороги: эмблем ровно четырнадцать',
      () {
        expect(parseRankHours([0, 1, 2]), kRankHours);
      },
    );
  });
}
