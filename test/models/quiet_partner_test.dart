import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/quiet_partner.dart';

/// Подсказка «Скучаю», когда второй давно не заходил. Пары гаснут вдвоём:
/// у 45% живых пар последние визиты расходятся меньше чем на сутки, поэтому
/// момент, когда один затих, — последний, где можно вмешаться.
void main() {
  final now = DateTime(2026, 7, 28, 12);
  int ms(DateTime d) => d.millisecondsSinceEpoch;

  group('Когда подсказывать', () {
    test('Партнёр молчит третьи сутки — подсказываем', () {
      expect(
        QuietPartner.shouldPrompt(
          isPaired: true,
          partnerSeenAtMs: ms(now.subtract(const Duration(days: 3))),
          nowMs: ms(now),
          lastNudgeAtMs: null,
        ),
        isTrue,
      );
    });

    test('Заходил вчера — молчим, это не повод', () {
      expect(
        QuietPartner.shouldPrompt(
          isPaired: true,
          partnerSeenAtMs: ms(now.subtract(const Duration(days: 1))),
          nowMs: ms(now),
          lastNudgeAtMs: null,
        ),
        isFalse,
      );
    });

    test('Ровно на пороге — ещё рано, ждём полных двух суток', () {
      expect(
        QuietPartner.shouldPrompt(
          isPaired: true,
          partnerSeenAtMs: ms(now) - QuietPartner.threshold.inMilliseconds,
          nowMs: ms(now),
          lastNudgeAtMs: null,
        ),
        isFalse,
      );
    });

    test('Без пары подсказки нет вовсе', () {
      expect(
        QuietPartner.shouldPrompt(
          isPaired: false,
          partnerSeenAtMs: ms(now.subtract(const Duration(days: 5))),
          nowMs: ms(now),
          lastNudgeAtMs: null,
        ),
        isFalse,
      );
    });

    test('Про партнёра ничего не известно — не выдумываем', () {
      expect(
        QuietPartner.shouldPrompt(
          isPaired: true,
          partnerSeenAtMs: null,
          nowMs: ms(now),
          lastNudgeAtMs: null,
        ),
        isFalse,
        reason: 'пустой seen_at бывает у тех, кто ни разу не открывал приложение',
      );
    });
  });

  group('Не чаще раза в день', () {
    test('Сегодня уже отправляли — второй раз не предлагаем', () {
      expect(
        QuietPartner.shouldPrompt(
          isPaired: true,
          partnerSeenAtMs: ms(now.subtract(const Duration(days: 4))),
          nowMs: ms(now),
          lastNudgeAtMs: ms(now.subtract(const Duration(hours: 3))),
        ),
        isFalse,
      );
    });

    test('Прошли сутки — можно снова', () {
      expect(
        QuietPartner.shouldPrompt(
          isPaired: true,
          partnerSeenAtMs: ms(now.subtract(const Duration(days: 4))),
          nowMs: ms(now),
          lastNudgeAtMs: ms(now.subtract(const Duration(days: 1, minutes: 1))),
        ),
        isTrue,
      );
    });
  });

  group('Сколько дней тишины', () {
    test('Считаем полными сутками', () {
      expect(
        QuietPartner.quietDays(
          partnerSeenAtMs: ms(now.subtract(const Duration(days: 3, hours: 5))),
          nowMs: ms(now),
        ),
        3,
      );
    });

    test('Нет отметки — нет числа', () {
      expect(
        QuietPartner.quietDays(partnerSeenAtMs: null, nowMs: ms(now)),
        isNull,
      );
    });
  });
}
