import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/miss_you_state.dart';

void main() {
  group('MissYouEntry.fromRow', () {
    test('читает счётчик, последний импульс и время', () {
      final e = MissYouEntry.fromRow({
        'user_uid': 'me',
        'count': 402,
        'last_vibe': 'want_hug',
        'last_vibe_text': '',
        'updated_at': '2026-08-11T09:22:00.000Z',
        'by_weekday': '{"1":3,"7":5}',
      });
      expect(e.uid, 'me');
      expect(e.count, 402);
      expect(e.lastVibe, 'want_hug');
      expect(e.updatedAt, isNotNull);
      expect(e.byWeekday[7], 5);
    });

    test('кривая карта дней не роняет разбор', () {
      for (final raw in ['', 'не json', '[]', 'null']) {
        final e = MissYouEntry.fromRow({'user_uid': 'u', 'by_weekday': raw});
        expect(e.byWeekday, isEmpty, reason: raw);
      }
    });

    test('дни вне 1..7 и нечисловые значения отбрасываются', () {
      final e = MissYouEntry.fromRow({
        'user_uid': 'u',
        'by_weekday': '{"0":4,"8":9,"3":"два","4":6}',
      });
      expect(e.byWeekday, {4: 6});
    });

    test('читает разбивку по импульсам', () {
      final e = MissYouEntry.fromRow({
        'user_uid': 'me',
        'count': 90,
        'by_vibe': '{"miss_you":50,"want_hug":"12","thinking_of_you":28}',
      });
      expect(e.byVibe['miss_you'], 50);
      expect(e.byVibe['want_hug'], 12);
      expect(e.byVibe['thinking_of_you'], 28);
    });

    test('старая запись без by_vibe отдаёт весь счёт «скучаю»', () {
      // Карту завели 13 августа 2026, у всех прежних импульсов её нет вовсе.
      // Показать нули у каждой строки было бы враньём: до этого дня любой
      // импульс шёл в общий счётчик.
      final e = MissYouEntry.fromRow({'user_uid': 'me', 'count': 402});
      expect(e.byVibe, {'miss_you': 402});
    });

    test('кривая карта импульсов не роняет разбор', () {
      for (final raw in ['', 'не json', '[]', 'null']) {
        final e =
            MissYouEntry.fromRow({'user_uid': 'u', 'count': 5, 'by_vibe': raw});
        expect(e.byVibe, {'miss_you': 5}, reason: raw);
      }
    });

    test('пустое время остаётся пустым, а не сегодняшним днём', () {
      final e = MissYouEntry.fromRow({'user_uid': 'u', 'updated_at': ''});
      expect(e.updatedAt, isNull);
    });
  });

  group('MissYouState.fromRows', () {
    final rows = [
      {'user_uid': 'me', 'count': 402, 'by_weekday': '{"7":10}'},
      {'user_uid': 'her', 'count': 155, 'by_weekday': '{"7":5}'},
    ];

    test('делит записи на свою и партнёрскую', () {
      final s = MissYouState.fromRows(rows, myUid: 'me');
      expect(s.mine?.count, 402);
      expect(s.partner?.count, 155);
    });

    test('без своей записи счёт нулевой, партнёрский виден', () {
      final s = MissYouState.fromRows([rows[1]], myUid: 'me');
      expect(s.myCount, 0);
      expect(s.partnerCount, 155);
    });

    test('третий uid в группе не подменяет партнёра', () {
      final s = MissYouState.fromRows([
        ...rows,
        {'user_uid': 'stranger', 'count': 999},
      ], myUid: 'me');
      expect(s.partner?.uid, 'her');
    });
  });

  group('weekBars', () {
    test('всегда семь столбиков, с понедельника', () {
      final bars = weekBars(const {}, const {});
      expect(bars.length, 7);
      expect(bars.first.weekday, 1);
      expect(bars.last.weekday, 7);
    });

    test('пустые данные дают нулевые доли, а не деление на ноль', () {
      final bars = weekBars(const {}, const {});
      expect(bars.every((b) => b.mineFraction == 0 && b.partnerFraction == 0),
          isTrue);
    });

    test('шкала общая на обоих: максимум забирает единицу', () {
      final bars = weekBars(const {1: 10}, const {1: 5, 2: 2});
      expect(bars[0].mineFraction, 1.0);
      expect(bars[0].partnerFraction, 0.5);
      expect(bars[1].partnerFraction, closeTo(0.2, 1e-9));
    });

    test('пустая неделя видна отдельно от непустой', () {
      expect(weekBarsAreEmpty(weekBars(const {}, const {})), isTrue);
      expect(weekBarsAreEmpty(weekBars(const {3: 1}, const {})), isFalse);
    });
  });
}
