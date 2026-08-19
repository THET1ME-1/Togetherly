// «Умение любить»: как из ответов получаются шесть граней и общее число.
//
// Двадцать утверждений о себе за проход (из банка на восемьдесят), четыре
// градации ответа с весами 0, 33, 67, 100.
// У каждого утверждения своя грань, оценка грани — среднее её ответов, общее
// число — среднее по шести граням. Отвечать надо на всё: пропуски дали бы
// фигуру, которая врёт формой.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/love_test.dart';

void main() {
  group('вопросы', () {
    test('в банке восемьдесят, и у каждого своя грань', () {
      expect(kLoveBank, hasLength(80));
      for (final q in kLoveBank) {
        expect(q.text.trim(), isNotEmpty);
        expect(LoveFacet.values, contains(q.facet));
      }
    });

    test('на каждую грань приходится не меньше трёх утверждений', () {
      for (final facet in LoveFacet.values) {
        final n = kLoveBank.where((q) => q.facet == facet).length;
        expect(n, greaterThanOrEqualTo(3), reason: '${facet.title}: всего $n');
      }
    });

    test('утверждения не повторяются', () {
      final texts = kLoveBank.map((q) => q.text).toSet();
      expect(texts, hasLength(kLoveBank.length));
    });
  });

  group('подсчёт', () {
    // Набор фиксируем зерном: подсчёт не зависит от того, какие именно
    // утверждения вытянулись, — только от их граней.
    final round = pickLoveRound(random: Random(1));
    Map<int, int> answers(int weight) => {
          for (var i = 0; i < round.length; i++) i: weight,
        };

    test('все ответы «почти всегда» — сто по каждой грани', () {
      final r = scoreLoveRound(round, answers(100));
      expect(r, isNotNull);
      expect(r!.total, 100);
      for (final facet in LoveFacet.values) {
        expect(r.of(facet), 100);
      }
    });

    test('все ответы «почти никогда» — ноль', () {
      final r = scoreLoveRound(round, answers(0))!;
      expect(r.total, 0);
      expect(r.of(LoveFacet.trust), 0);
    });

    test('грань считается только по своим утверждениям', () {
      final a = answers(0);
      for (var i = 0; i < round.length; i++) {
        if (round[i].facet == LoveFacet.passion) a[i] = 100;
      }
      final r = scoreLoveRound(round, a)!;
      expect(r.of(LoveFacet.passion), 100);
      expect(r.of(LoveFacet.interest), 0);
      // Одна грань из шести на сотне: общее число — её шестая часть.
      expect(r.total, 17);
    });

    test('незаконченный тест результата не даёт', () {
      final a = answers(67)..remove(3);
      expect(scoreLoveRound(round, a), isNull,
          reason: 'пропуск сделал бы фигуру, которая врёт формой');
    });

    test('чужие веса не принимаются', () {
      final a = answers(67)..[5] = 42;
      expect(scoreLoveRound(round, a), isNull);
    });
  });

  group('разбор результата', () {
    final round = pickLoveRound(random: Random(2));

    test('сильная и слабая грань называются', () {
      final a = {for (var i = 0; i < round.length; i++) i: 67};
      for (var i = 0; i < round.length; i++) {
        if (round[i].facet == LoveFacet.gratitude) a[i] = 100;
        if (round[i].facet == LoveFacet.passion) a[i] = 0;
      }
      final r = scoreLoveRound(round, a)!;
      expect(r.strongest, LoveFacet.gratitude);
      expect(r.weakest, LoveFacet.passion);
    });

    test('запись и чтение туда-обратно', () {
      final r = scoreLoveRound(round, {
        for (var i = 0; i < round.length; i++) i: 100,
      })!;
      final back = LoveTestResult.fromMap(r.toMap());
      expect(back.total, r.total);
      expect(back.of(LoveFacet.trust), r.of(LoveFacet.trust));
      expect(back.takenAt, r.takenAt);
    });

    test('битая запись читается пустой, а не падает', () {
      final back = LoveTestResult.fromMap({'facets': 'мусор', 'total': 'нет'});
      expect(back.total, 0);
      expect(back.of(LoveFacet.trust), 0);
    });
  });

  group('сравнение с партнёром', () {
    test('где сошлись и где разошлись', () {
      final mine = LoveTestResult(
        facets: {
          LoveFacet.interest: 74,
          LoveFacet.trust: 79,
          LoveFacet.gratitude: 88,
          LoveFacet.mutuality: 66,
          LoveFacet.passion: 52,
          LoveFacet.acceptance: 67,
        },
        takenAt: DateTime(2026, 8, 18),
      );
      final theirs = LoveTestResult(
        facets: {
          LoveFacet.interest: 61,
          LoveFacet.trust: 70,
          LoveFacet.gratitude: 72,
          LoveFacet.mutuality: 68,
          LoveFacet.passion: 83,
          LoveFacet.acceptance: 44,
        },
        takenAt: DateTime(2026, 8, 18),
      );
      final pair = comparePair(mine, theirs);
      expect(pair.closest, LoveFacet.mutuality, reason: '66 и 68 — разница два');
      expect(pair.widest, LoveFacet.passion, reason: '52 и 83 — разница 31');
      expect(pair.gapOf(LoveFacet.passion), 31);
    });
  });
}
