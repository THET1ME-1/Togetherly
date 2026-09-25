import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/streak_restore.dart';

/// Правило то же, что на сервере (`_возврат_серии` в hotpath.py и
/// pocketbase/hotpath/test_streak_restore.py): приложение показывает кнопку
/// «Вернуть серию» только там, где сервер согласится её вернуть.
void main() {
  final now = DateTime(2026, 9, 22, 20);

  group('streakRestoreOffer', () {
    test('пара ещё не вернулась: вчера пропущено — вернуть можно', () {
      final offer = streakRestoreOffer({'s': 12, 'd': '2026-09-20'}, now);
      expect(offer?.days, 12);
    });

    test('живую серию возвращать нечего', () {
      expect(streakRestoreOffer({'s': 12, 'd': '2026-09-21'}, now), isNull);
      expect(streakRestoreOffer({'s': 12, 'd': '2026-09-22'}, now), isNull);
    });

    test('после долгого перерыва возврата нет', () {
      expect(streakRestoreOffer({'s': 12, 'd': '2026-09-17'}, now), isNull);
      expect(streakRestoreOffer({'s': 12, 'd': '2026-09-18'}, now)?.days, 12);
    });

    test('серия из одного дня потерей не считается', () {
      expect(streakRestoreOffer({'s': 1, 'd': '2026-09-20'}, now), isNull);
    });

    test('после сброса возвращается сумма прежней и новой серии', () {
      final offer = streakRestoreOffer(
        {'s': 2, 'd': '2026-09-22', 'lost': 12, 'lost_d': '2026-09-21'},
        now,
      );
      expect(offer?.days, 14);
    });

    test('через три дня после сброса возврата нет', () {
      final entry = {'s': 1, 'd': '2026-09-22', 'lost': 12, 'lost_d': '2026-09-18'};
      expect(streakRestoreOffer(entry, now), isNull);
    });

    test('ключ предложения свой у каждого обрыва', () {
      final a = streakRestoreOffer({'s': 12, 'd': '2026-09-20'}, now)!;
      final b = streakRestoreOffer(
        {'s': 1, 'd': '2026-09-22', 'lost': 12, 'lost_d': '2026-09-22'},
        now,
      )!;
      expect(a.key, isNot(b.key));
    });

    test('пустая или чужая запись не ломает', () {
      expect(streakRestoreOffer(null, now), isNull);
      expect(streakRestoreOffer({'s': 'x', 'd': 5}, now), isNull);
    });
  });
}
