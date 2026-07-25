// Советы паре. Правило одно: совет говорит, ЧТО сделать, и никогда не
// объясняет, почему партнёр «такой». «Спроси, как она» — можно. «У неё ПМС,
// будь терпелив» — нельзя: это диагноз вместо заботы, и обижает обоих.

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/relationship_tips.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);

TipContext ctx({
  int? daysSinceMiss,
  int? partnerMoodScore,
  int? myMoodScore,
  int? daysToAnniversary,
  int? daysTogether,
  CyclePhaseHint cycle = CyclePhaseHint.unknown,
  bool cycleVisible = false,
  int? daysSinceMemory,
  int? daysSinceChat,
}) =>
    TipContext(
      daysSinceMiss: daysSinceMiss,
      partnerMoodScore: partnerMoodScore,
      myMoodScore: myMoodScore,
      daysToAnniversary: daysToAnniversary,
      daysTogether: daysTogether,
      cycle: cycle,
      cycleVisible: cycleVisible,
      daysSinceMemory: daysSinceMemory,
      daysSinceChat: daysSinceChat,
    );

void main() {
  group('приватность цикла', () {
    test('без разрешения советы по циклу не выдаются', () {
      final tips = RelationshipTips.forToday(
        ctx(cycle: CyclePhaseHint.period, cycleVisible: false),
      );
      expect(tips.any((t) => t.id.startsWith('cycle_')), isFalse);
    });

    test('с разрешением совет по циклу появляется', () {
      final tips = RelationshipTips.forToday(
        ctx(cycle: CyclePhaseHint.period, cycleVisible: true),
      );
      expect(tips.any((t) => t.id.startsWith('cycle_')), isTrue);
    });

    test('неизвестная фаза советов по циклу не даёт', () {
      final tips = RelationshipTips.forToday(
        ctx(cycle: CyclePhaseHint.unknown, cycleVisible: true),
      );
      expect(tips.any((t) => t.id.startsWith('cycle_')), isFalse);
    });
  });

  group('настроение партнёра', () {
    test('низкое настроение даёт совет поддержать', () {
      final tips = RelationshipTips.forToday(ctx(partnerMoodScore: 1));
      expect(tips.any((t) => t.id == 'mood_low'), isTrue);
    });

    test('хорошее настроение не даёт совета «поддержать»', () {
      final tips = RelationshipTips.forToday(ctx(partnerMoodScore: 5));
      expect(tips.any((t) => t.id == 'mood_low'), isFalse);
    });

    test('партнёр не отмечался — совет спросить, а не догадываться', () {
      final tips = RelationshipTips.forToday(ctx(partnerMoodScore: null));
      expect(tips.any((t) => t.id == 'mood_unknown'), isTrue);
    });
  });

  group('внимание друг к другу', () {
    test('давно не писали — совет написать', () {
      final tips = RelationshipTips.forToday(ctx(daysSinceChat: 3));
      expect(tips.any((t) => t.id == 'silence'), isTrue);
    });

    test('написали сегодня — совета о молчании нет', () {
      final tips = RelationshipTips.forToday(ctx(daysSinceChat: 0));
      expect(tips.any((t) => t.id == 'silence'), isFalse);
    });

    test('давно не было воспоминаний — совет добавить', () {
      final tips = RelationshipTips.forToday(ctx(daysSinceMemory: 14));
      expect(tips.any((t) => t.id == 'memory_gap'), isTrue);
    });
  });

  group('даты', () {
    test('годовщина близко — совет подготовиться', () {
      final tips = RelationshipTips.forToday(ctx(daysToAnniversary: 5));
      expect(tips.any((t) => t.id == 'anniversary_soon'), isTrue);
    });

    test('годовщина далеко — совета нет', () {
      final tips = RelationshipTips.forToday(ctx(daysToAnniversary: 90));
      expect(tips.any((t) => t.id == 'anniversary_soon'), isFalse);
    });

    test('круглая дата сегодня — отдельный совет', () {
      final tips = RelationshipTips.forToday(ctx(daysTogether: 100));
      expect(tips.any((t) => t.id == 'round_date'), isTrue);
    });
  });

  group('порядок и объём', () {
    test('советы отсортированы по важности', () {
      final tips = RelationshipTips.forToday(ctx(
        partnerMoodScore: 1,
        daysSinceChat: 1,
        daysToAnniversary: 200,
      ));
      expect(tips.first.id, 'mood_low');
    });

    test('за раз не больше трёх советов: список ради списка не читают', () {
      final tips = RelationshipTips.forToday(ctx(
        partnerMoodScore: 1,
        daysSinceMiss: 9,
        daysSinceChat: 5,
        daysSinceMemory: 30,
        daysToAnniversary: 3,
        cycle: CyclePhaseHint.period,
        cycleVisible: true,
      ));
      expect(tips.length, lessThanOrEqualTo(3));
    });

    test('когда всё хорошо, советов нет — молчание лучше пустого совета', () {
      final tips = RelationshipTips.forToday(ctx(
        partnerMoodScore: 5,
        myMoodScore: 5,
        daysSinceMiss: 0,
        daysSinceChat: 0,
        daysSinceMemory: 1,
        daysToAnniversary: 200,
      ));
      expect(tips, isEmpty);
    });
  });

  group('формулировки', () {
    test('ни один совет не объясняет поведение партнёра циклом', () {
      // Проверяем сам текст: запрещённые слова не должны появиться ни в одном
      // совете, каким бы ни был контекст.
      const forbidden = ['пмс', 'гормон', 'раздражит', 'капризн', 'терпи'];
      for (final phase in CyclePhaseHint.values) {
        final tips = RelationshipTips.forToday(
          ctx(cycle: phase, cycleVisible: true, partnerMoodScore: 1),
        );
        for (final tip in tips) {
          final text = '${tip.title} ${tip.body}'.toLowerCase();
          for (final word in forbidden) {
            expect(text.contains(word), isFalse,
                reason: 'совет ${tip.id} содержит «$word»');
          }
        }
      }
    });
  });
}
