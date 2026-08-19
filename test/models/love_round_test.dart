import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/love_test.dart';

/// Набор одного прохождения и сравнение с прошлыми разами.
///
/// Двадцать утверждений на весь тест означали, что второй проход слово в слово
/// повторяет первый — человек отвечает по памяти, а не про себя. Теперь в банке
/// восемьдесят, в проход идут двадцать: раскладка по граням прежняя, состав
/// каждый раз новый.
void main() {
  group('pickLoveRound', () {
    test('в проход идёт двадцать утверждений без повторов', () {
      final round = pickLoveRound(random: Random(1));
      expect(round.length, kLoveRoundSize);
      expect(round.map((q) => q.key).toSet().length, kLoveRoundSize);
    });

    test('раскладка по граням та же, что была у теста из двадцати', () {
      final round = pickLoveRound(random: Random(7));
      final counts = <LoveFacet, int>{};
      for (final q in round) {
        counts[q.facet] = (counts[q.facet] ?? 0) + 1;
      }
      expect(counts, kLoveRoundLayout);
    });

    test('разные попытки дают разный состав', () {
      final a = pickLoveRound(random: Random(1)).map((q) => q.key).toList();
      final b = pickLoveRound(random: Random(2)).map((q) => q.key).toList();
      expect(a, isNot(equals(b)));
    });

    test('прошлый набор не повторяется', () {
      final first = pickLoveRound(random: Random(3));
      final second = pickLoveRound(
        random: Random(4),
        exclude: first.map((q) => q.key).toSet(),
      );
      expect(
        second.map((q) => q.key).toSet().intersection(
              first.map((q) => q.key).toSet(),
            ),
        isEmpty,
      );
    });

    test('если свежих в грани не хватило, добираем из прежних', () {
      // Человек прошёл тест столько раз, что исключить нечего: набор всё равно
      // обязан собраться целиком, иначе тест просто не откроется.
      final all = {for (final q in kLoveBank) q.key};
      final round = pickLoveRound(random: Random(5), exclude: all);
      expect(round.length, kLoveRoundSize);
      final counts = <LoveFacet, int>{};
      for (final q in round) {
        counts[q.facet] = (counts[q.facet] ?? 0) + 1;
      }
      expect(counts, kLoveRoundLayout);
    });
  });

  group('scoreLoveRound', () {
    List<LoveQuestion> round() => pickLoveRound(random: Random(11));

    test('считает по граням набора, а не по номерам банка', () {
      final r = round();
      final answers = {
        for (var i = 0; i < r.length; i++)
          i: r[i].facet == LoveFacet.trust ? 100 : 0,
      };
      final result = scoreLoveRound(r, answers);
      expect(result, isNotNull);
      expect(result!.of(LoveFacet.trust), 100);
      expect(result.of(LoveFacet.passion), 0);
    });

    test('незаконченный набор не считается', () {
      final r = round();
      final answers = {for (var i = 0; i < r.length - 1; i++) i: 100};
      expect(scoreLoveRound(r, answers), isNull);
    });

    test('чужой вес не считается', () {
      final r = round();
      final answers = {for (var i = 0; i < r.length; i++) i: 50};
      expect(scoreLoveRound(r, answers), isNull);
    });
  });

  group('история прохождений', () {
    LoveTestResult res(int score, String at) => LoveTestResult(
          facets: {for (final f in LoveFacet.values) f: score},
          takenAt: DateTime.parse(at),
        );

    test('прошлый результат уезжает в историю вместе со свежим', () {
      final first = res(40, '2026-07-01T10:00:00Z');
      final second = res(60, '2026-08-01T10:00:00Z');

      final payload = loveTestPayload(second, [first]);
      final history = loveHistoryFromMap(payload);

      expect(payload['total'], 60);
      expect(history.length, 1);
      expect(history.first.total, 40);
    });

    test('история не растёт бесконечно', () {
      final old = [
        for (var i = 0; i < 20; i++)
          res(i, '2026-01-01T10:00:00Z'),
      ];
      final payload = loveTestPayload(res(90, '2026-08-19T10:00:00Z'), old);
      expect(loveHistoryFromMap(payload).length, kLoveHistoryKeep);
    });

    test('в истории лежат самые свежие прохождения', () {
      final old = [
        for (var i = 0; i < 20; i++)
          res(i, '2026-01-01T10:00:00Z'),
      ];
      final history = loveHistoryFromMap(loveTestPayload(res(90, '2026-08-19T10:00:00Z'), old));
      expect(history.last.total, 19);
    });

    test('запись прежних сборок читается без истории', () {
      final plain = res(55, '2026-06-01T10:00:00Z').toMap();
      expect(loveHistoryFromMap(plain), isEmpty);
      expect(LoveTestResult.fromMap(plain).total, 55);
    });
  });

  group('loveProgress', () {
    LoveTestResult res(Map<LoveFacet, int> f, String at) =>
        LoveTestResult(facets: f, takenAt: DateTime.parse(at));

    test('показывает, что выросло, а что просело', () {
      final before = res({
        LoveFacet.interest: 40,
        LoveFacet.trust: 80,
        LoveFacet.gratitude: 50,
        LoveFacet.mutuality: 50,
        LoveFacet.passion: 50,
        LoveFacet.acceptance: 50,
      }, '2026-07-01T10:00:00Z');
      final now = res({
        LoveFacet.interest: 70,
        LoveFacet.trust: 60,
        LoveFacet.gratitude: 50,
        LoveFacet.mutuality: 50,
        LoveFacet.passion: 50,
        LoveFacet.acceptance: 50,
      }, '2026-08-19T10:00:00Z');

      final p = loveProgress(now, before)!;
      expect(p.deltaOf(LoveFacet.interest), 30);
      expect(p.deltaOf(LoveFacet.trust), -20);
      expect(p.deltaOf(LoveFacet.gratitude), 0);
      expect(p.totalDelta, now.total - before.total);
      expect(p.grown, LoveFacet.interest);
      expect(p.fallen, LoveFacet.trust);
      expect(p.since, before.takenAt);
    });

    test('первого прохождения не с чем сравнивать', () {
      expect(loveProgress(res({LoveFacet.trust: 50}, '2026-08-19T10:00:00Z'), null),
          isNull);
    });
  });
}
