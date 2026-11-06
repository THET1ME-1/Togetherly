import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/pair_quiz.dart';

void main() {
  group('вопросы', () {
    test('язык любви: 15 пар, каждый язык ровно 6 раз', () {
      final qs = quizQuestions(QuizKind.lang, 'ru');
      expect(qs, hasLength(15));
      final seen = <String, int>{};
      for (final q in qs) {
        expect(q.options, hasLength(2));
        for (final o in q.options) {
          for (final k in o.score.keys) {
            seen[k] = (seen[k] ?? 0) + 1;
          }
        }
      }
      expect(seen, {for (final t in kQuizTypes[QuizKind.lang]!) t: 6});
    });

    test('животное: 15 вопросов по 4 ответа, каждый зверь 7 или 8 раз', () {
      final qs = quizQuestions(QuizKind.animal, 'ru');
      expect(qs, hasLength(15));
      final seen = <String, int>{};
      for (final q in qs) {
        expect(q.options, hasLength(4));
        for (final o in q.options) {
          seen[o.score.keys.single] = (seen[o.score.keys.single] ?? 0) + 1;
        }
      }
      expect(seen.keys.toSet(), kQuizTypes[QuizKind.animal]!.toSet());
      expect(seen.values.every((n) => n == 7 || n == 8), isTrue, reason: '$seen');
    });

    test('привязанность: 15 утверждений, на каждую ось не меньше семи', () {
      final qs = quizQuestions(QuizKind.attach, 'ru');
      expect(qs, hasLength(15));
      for (final q in qs) {
        expect(q.options, hasLength(5));
      }
      final perAxis = <String, int>{};
      for (final q in qs) {
        perAxis[attachItemAxis(q)] = (perAxis[attachItemAxis(q)] ?? 0) + 1;
      }
      expect(perAxis['anx'], greaterThanOrEqualTo(7));
      expect(perAxis['avo'], greaterThanOrEqualTo(7));
    });

    test('вступление называет то же число вопросов', () {
      expect(quizIntro(QuizKind.lang, 'ru'), startsWith('Пятнадцать'));
      expect(quizIntro(QuizKind.attach, 'ru'), startsWith('Пятнадцать'));
      expect(quizIntro(QuizKind.animal, 'ru'), startsWith('Пятнадцать'));
    });
  });

  group('банк вопросов', () {
    for (final kind in QuizKind.values) {
      test('${kind.name}: в любом наборе баланс прежний, тексты есть', () {
        final base = quizQuestions(kind, 'ru');
        final slots = quizSlotCount(kind);
        expect(slots, base.length);
        // Язык любви: пять вариантов на слот, привязанность и зверь: четыре.
        final least = kind == QuizKind.lang ? 5 : 4;
        for (var s = 0; s < slots; s++) {
          expect(quizVariantCount(kind, s), greaterThanOrEqualTo(least), reason: '$kind слот $s');
        }
        // Каждый вариант каждого слота: те же типы на тех же местах.
        for (var s = 0; s < slots; s++) {
          for (var v = 0; v < quizVariantCount(kind, s); v++) {
            final round = List.filled(slots, 0)..[s] = v;
            for (final lang in ['ru', 'en', 'uk']) {
              final q = quizQuestions(kind, lang, round: round)[s];
              expect(q.text, isNotEmpty);
              expect([for (final o in q.options) o.score], [for (final o in base[s].options) o.score]);
              for (final o in q.options) {
                expect(o.text, isNotEmpty, reason: '$kind $s $v $lang');
              }
            }
          }
        }
      });
    }

    for (final kind in QuizKind.values) {
      test('${kind.name}: в банке нет повторов текста', () {
        final slots = quizSlotCount(kind);
        for (final lang in ['ru', 'en', 'uk']) {
          final seen = <String>{};
          for (var s = 0; s < slots; s++) {
            for (var v = 0; v < quizVariantCount(kind, s); v++) {
              final q = quizQuestions(kind, lang, round: List.filled(slots, 0)..[s] = v)[s];
              // У языка любви вопрос один на всех, повторяться нельзя ответам.
              final texts = kind == QuizKind.lang
                  ? [for (final o in q.options) o.text]
                  : kind == QuizKind.attach
                      ? [q.text]
                      : [q.text, for (final o in q.options) o.text];
              for (final t in texts) {
                expect(seen.add(t), isTrue, reason: '$kind $lang повтор: $t');
              }
            }
          }
        }
      });
    }

    test('новый набор обходит прошлый', () {
      final last = quizRoundKeys(QuizKind.lang, List.filled(quizSlotCount(QuizKind.lang), 0)).toSet();
      final round = pickQuizRound(QuizKind.lang, Random(1), exclude: last);
      expect(quizRoundKeys(QuizKind.lang, round).toSet().intersection(last), isEmpty);
    });

    test('ключи набора различают вопросы', () {
      final keys = quizRoundKeys(QuizKind.animal, List.filled(15, 1));
      expect(keys.toSet(), hasLength(15));
    });
  });

  group('подсчёт', () {
    test('язык любви: побеждает самый частый, все пять в процентах', () {
      final qs = quizQuestions(QuizKind.lang, 'ru');
      // Всегда выбираем вариант с «прикосновениями», где он есть.
      final answers = [
        for (final q in qs)
          q.options.indexWhere((o) => o.score.containsKey('touch')) < 0
              ? 0
              : q.options.indexWhere((o) => o.score.containsKey('touch')),
      ];
      final r = scoreQuiz(QuizKind.lang, answers);
      expect(r.type, 'touch');
      expect(r.scores['touch'], 1.0);
      expect(r.scores.keys.toSet(), kQuizTypes[QuizKind.lang]!.toSet());
    });

    test('привязанность: тревога высокая, избегание низкое — тревожный', () {
      final qs = quizQuestions(QuizKind.attach, 'ru');
      final answers = [
        for (final q in qs)
          // «Точно да» тревоге, «Совсем нет» избеганию — с учётом обратных.
          attachItemAxis(q) == 'anx'
              ? (attachItemReversed(q) ? 0 : 4)
              : (attachItemReversed(q) ? 4 : 0),
      ];
      final r = scoreQuiz(QuizKind.attach, answers);
      expect(r.type, 'anxious');
      expect(r.scores['anx'], 1.0);
      expect(r.scores['avo'], 0.0);
    });

    test('привязанность: всё посередине — надёжный', () {
      final r = scoreQuiz(QuizKind.attach, List.filled(15, 2));
      expect(r.type, 'secure');
    });

    test('привязанность: обе шкалы высокие — смешанный', () {
      final qs = quizQuestions(QuizKind.attach, 'ru');
      final answers = [for (final q in qs) attachItemReversed(q) ? 0 : 4];
      expect(scoreQuiz(QuizKind.attach, answers).type, 'fearful');
    });

    test('животное: больше всего ответов одного зверя', () {
      final qs = quizQuestions(QuizKind.animal, 'ru');
      final answers = [
        for (final q in qs)
          q.options.indexWhere((o) => o.score.containsKey('otter')) < 0
              ? 0
              : q.options.indexWhere((o) => o.score.containsKey('otter')),
      ];
      expect(scoreQuiz(QuizKind.animal, answers).type, 'otter');
    });

    test('животное: побеждает доля, а не штуки', () {
      // Ёж встречается реже кота. Ежу отдаём все его вопросы, кроме одного
      // без кота, коту остальные свои: по штукам ничья, по доле ёж впереди.
      final qs = quizQuestions(QuizKind.animal, 'ru');
      var skipped = false;
      final answers = <int>[];
      for (final q in qs) {
        final hedgehog = q.options.indexWhere((o) => o.score.containsKey('hedgehog'));
        final cat = q.options.indexWhere((o) => o.score.containsKey('cat'));
        if (hedgehog >= 0 && (cat >= 0 || skipped)) {
          answers.add(hedgehog);
        } else if (hedgehog >= 0) {
          skipped = true;
          answers.add(hedgehog == 0 ? 1 : 0);
        } else {
          answers.add(cat >= 0 ? cat : q.options.indexWhere((o) => !o.score.containsKey('hedgehog')));
        }
      }
      final r = scoreQuiz(QuizKind.animal, answers);
      expect(r.scores['hedgehog']! > r.scores['cat']!, isTrue, reason: '${r.scores}');
      expect(r.type, 'hedgehog');
    });

    test('недостающие и кривые ответы не роняют подсчёт', () {
      expect(scoreQuiz(QuizKind.lang, const []).type, isNotEmpty);
      expect(scoreQuiz(QuizKind.animal, const [99, -1]).type, isNotEmpty);
    });
  });

  group('результат', () {
    test('переживает сохранение', () {
      final r = scoreQuiz(QuizKind.lang, List.filled(15, 1));
      final back = QuizResult.fromJson(r.toJson());
      expect(back?.kind, QuizKind.lang);
      expect(back?.type, r.type);
      expect(back?.scores, r.scores);
    });

    test('кривая запись не разбирается', () {
      expect(QuizResult.fromJson(const {}), isNull);
      expect(QuizResult.fromJson(const {'kind': 'nope', 'type': 'x'}), isNull);
      expect(QuizResult.fromJson(const {'kind': 'lang', 'type': 'nope'}), isNull);
    });

    test('id записи один на человека и тест', () {
      expect(pairQuizRecordId('g', 'u', QuizKind.lang), hasLength(15));
      expect(pairQuizRecordId('g', 'u', QuizKind.lang),
          isNot(pairQuizRecordId('g', 'u', QuizKind.animal)));
      expect(pairQuizRecordId('g', 'u', QuizKind.lang), matches(RegExp(r'^[a-z0-9]{15}$')));
    });
  });

  group('тексты', () {
    for (final lang in ['ru', 'en', 'uk', 'de']) {
      test('всё заполнено: $lang', () {
        for (final kind in QuizKind.values) {
          expect(quizTitle(kind, lang), isNotEmpty);
          expect(quizIntro(kind, lang), isNotEmpty);
          for (final q in quizQuestions(kind, lang)) {
            expect(q.text, isNotEmpty);
            for (final o in q.options) {
              expect(o.text, isNotEmpty);
            }
          }
          for (final t in kQuizTypes[kind]!) {
            expect(quizTypeTitle(kind, t, lang), isNotEmpty, reason: '$kind $t');
            expect(quizTypeText(kind, t, lang), isNotEmpty, reason: '$kind $t');
            for (final o in kQuizTypes[kind]!) {
              expect(quizPairText(kind, t, o, lang), isNotEmpty, reason: '$kind $t $o');
            }
          }
        }
      });
    }

    test('русские тексты не на английском', () {
      expect(quizTitle(QuizKind.lang, 'ru'), isNot(quizTitle(QuizKind.lang, 'en')));
      expect(quizTypeTitle(QuizKind.animal, 'cat', 'uk'),
          isNot(quizTypeTitle(QuizKind.animal, 'cat', 'en')));
    });
  });
}
