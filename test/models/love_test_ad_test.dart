import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/love_test_ad.dart';

/// Ролик перед результатом теста «Умение любить».
///
/// Решение владельца от 20.08.2026: человек отвечает на двадцать утверждений,
/// и перед тем как показать фигуру, крутится видео. Отказаться от показа
/// нельзя — но само правило показа обязано знать про исключения, иначе мы
/// либо покажем рекламу оплатившему, либо запустим её без загруженного
/// ролика и человек уставится в пустой экран.
void main() {
  const now = 1787000000000;

  test('обычный человек видит ролик', () {
    expect(
      showAdBeforeLoveResult(plusActive: false, adReady: true, lastShownMs: 0, nowMs: now),
      isTrue,
    );
  });

  test('оплативший Togetherly+ рекламы не видит', () {
    expect(
      showAdBeforeLoveResult(plusActive: true, adReady: true, lastShownMs: 0, nowMs: now),
      isFalse,
    );
  });

  test('незагруженный ролик не задерживает результат', () {
    expect(
      showAdBeforeLoveResult(plusActive: false, adReady: false, lastShownMs: 0, nowMs: now),
      isFalse,
    );
  });

  group('повтор теста подряд', () {
    test('второй прогон через минуту ролик не крутит', () {
      expect(
        showAdBeforeLoveResult(
          plusActive: false,
          adReady: true,
          lastShownMs: now - 60 * 1000,
          nowMs: now,
        ),
        isFalse,
        reason: 'две рекламы подряд обе сети считают недобросовестным трафиком',
      );
    });

    test('через полчаса — снова показываем', () {
      expect(
        showAdBeforeLoveResult(
          plusActive: false,
          adReady: true,
          lastShownMs: now - 31 * 60 * 1000,
          nowMs: now,
        ),
        isTrue,
      );
    });

    test('часы телефона убежали назад — показ не блокируется навсегда', () {
      expect(
        showAdBeforeLoveResult(
          plusActive: false,
          adReady: true,
          lastShownMs: now + 5 * 60 * 1000,
          nowMs: now,
        ),
        isTrue,
      );
    });
  });

  test('ролик крутится ДО того, как экран покажет фигуру', () {
    final src =
        File('lib/screens/love_test_screen.dart').readAsStringSync();
    final ad = src.indexOf('_showAdIfDue()');
    final result = src.indexOf('_stage = _Stage.result;');
    expect(ad, greaterThan(0), reason: 'показ ролика из экрана пропал');
    expect(result, greaterThan(0));
    expect(
      ad,
      lessThan(result),
      reason: 'переставленный вызов означает, что человек увидит фигуру '
          'раньше ролика — и реклама станет необязательной',
    );
  });
}
