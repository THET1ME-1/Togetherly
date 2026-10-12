// Достижений стало тридцать восемь, и список легко сломать вслепую: повторить
// id, поставить порог ниже предыдущего или оставить метрику без ближней цели.
// Эти проверки держат его связным.

import 'dart:io';

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

    test('семья идёт по возрастанию порога и собирает всю метрику', () {
      for (final metric in AchievementMetric.values) {
        final family = PairAchievement.family(metric);
        expect(family, isNotEmpty, reason: '$metric');
        expect(family.every((a) => a.metric == metric), isTrue);
        final steps = family.map((a) => a.threshold).toList();
        expect(steps, [...steps]..sort(), reason: '$metric');
      }
      final total = AchievementMetric.values
          .fold<int>(0, (n, m) => n + PairAchievement.family(m).length);
      expect(total, PairAchievement.all.length);
    });

    test('ближайшая цель — первое неполученное в семье', () {
      const stats = AchievementStats(streakDays: 7, messages: 130);
      expect(
        PairAchievement.nextGoal(AchievementMetric.streakDays, stats)?.id,
        'streak_14',
      );
      expect(
        PairAchievement.nextGoal(AchievementMetric.messages, stats)?.id,
        'messages_500',
      );
      expect(
        PairAchievement.nextGoal(AchievementMetric.drawings, stats)?.id,
        'drawings_1',
      );
    });

    test('у собранной семьи ближайшей цели нет', () {
      const stats = AchievementStats(streakDays: 400);
      expect(
        PairAchievement.nextGoal(AchievementMetric.streakDays, stats),
        isNull,
      );
    });

    test('снимок счётчиков отдаёт значение по метрике', () {
      const stats = AchievementStats(
        daysTogether: 1,
        memories: 2,
        messages: 3,
        drawings: 4,
        streakDays: 5,
      );
      expect(
        [for (final m in AchievementMetric.values) stats.valueOf(m)],
        [1, 2, 3, 4, 5],
      );
    });
  });

  group('Рисунки достижений', () {
    test('ключ каталога считается из id', () {
      expect(PairAchievement.byId('streak_7')!.artKey, 'ach_streak_7');
    });

    test('у каждого достижения в сборке лежит неподвижный кадр', () {
      // Без кадра достижение без сети показывает пустое место: каталог может
      // не прийти, а рисунок обязан быть виден.
      for (final a in PairAchievement.all) {
        expect(File(a.stillAsset).existsSync(), isTrue, reason: a.stillAsset);
      }
    });

    test('папка кадров объявлена в pubspec', () {
      expect(
        File('pubspec.yaml').readAsStringSync(),
        contains('- assets/images/achievements/'),
      );
    });

    test('эмодзи и металлические цвета из модели убраны', () {
      final src = File('lib/models/pair_achievement.dart').readAsStringSync();
      expect(src.contains('emoji'), isFalse);
      expect(src.contains('tierColor'), isFalse);
      expect(src.contains('tierGradient'), isFalse);
    });
  });
}
