// Достижений стало тридцать восемь, и список легко сломать вслепую: повторить
// id, поставить порог ниже предыдущего или оставить метрику без ближней цели.
// Эти проверки держат его связным.

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/pair_achievement.dart';

void main() {
  group('Список достижений', () {
    test('идентификаторы не повторяются', () {
      final ids = PairAchievement.all.map((a) => a.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('внутри метрики пороги идут по возрастанию', () {
      for (final metric in AchievementMetric.values) {
        final steps = PairAchievement.all
            .where((a) => a.metric == metric)
            .map((a) => a.threshold)
            .toList();
        final sorted = [...steps]..sort();
        expect(steps, sorted, reason: 'метрика $metric');
        expect(steps.toSet().length, steps.length,
            reason: 'повтор порога в $metric');
      }
    });

    test('уровень не понижается с ростом порога', () {
      for (final metric in AchievementMetric.values) {
        final items =
            PairAchievement.all.where((a) => a.metric == metric).toList();
        for (var i = 1; i < items.length; i++) {
          expect(items[i].tier.index, greaterThanOrEqualTo(items[i - 1].tier.index),
              reason: '${items[i].id} слабее предыдущего');
        }
      }
    });

    test('между ступенями нет разрыва больше чем в десять раз', () {
      // Иначе после лёгкой цели следующая висит недостижимой, и прогресс
      // выглядит замершим.
      for (final metric in AchievementMetric.values) {
        final steps = PairAchievement.all
            .where((a) => a.metric == metric)
            .map((a) => a.threshold)
            .toList();
        for (var i = 1; i < steps.length; i++) {
          expect(steps[i] / steps[i - 1], lessThanOrEqualTo(10),
              reason: 'разрыв в $metric: ${steps[i - 1]} → ${steps[i]}');
        }
      }
    });

    test('у каждой метрики есть и ближняя цель, и дальняя', () {
      for (final metric in AchievementMetric.values) {
        final steps = PairAchievement.all
            .where((a) => a.metric == metric)
            .map((a) => a.threshold)
            .toList();
        expect(steps.length, greaterThanOrEqualTo(4), reason: '$metric');
        expect(steps.first, lessThanOrEqualTo(30), reason: 'ближняя в $metric');
      }
    });

    test('всего достижений тридцать восемь', () {
      expect(PairAchievement.all.length, 38);
    });

    test('каждому уровню отвечает своя фигура', () {
      final shapes =
          AchievementTier.values.map((t) => achievementShapeFor(t)).toSet();
      expect(shapes.length, AchievementTier.values.length);
    });

    test('фигуры строго геометрические: у каждой считаемое число углов', () {
      for (final tier in AchievementTier.values) {
        expect(achievementShapeFor(tier).sides, greaterThanOrEqualTo(4));
      }
    });
  });
}
