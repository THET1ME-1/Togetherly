import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/plus_access.dart';
import 'package:love_app/widgets/plus/plus_promo_rule.dart';

void main() {
  const hour = 3600 * 1000;
  const day = 24 * hour;
  const now = 1786000000000;

  group('shouldShowPlusPromo', () {
    test('некупившему через семь часов после прошлого раза — показываем', () {
      expect(
        shouldShowPlusPromo(
          gate: PlusGate.locked,
          nowMs: now,
          lastShownMs: now - 8 * hour,
          installedMs: now - 30 * day,
        ),
        isTrue,
      );
    });

    test('купившему не показываем никогда', () {
      expect(
        shouldShowPlusPromo(
          gate: PlusGate.open,
          nowMs: now,
          lastShownMs: 0,
          installedMs: now - 30 * day,
        ),
        isFalse,
      );
    });

    test('на iPhone плашки нет — Плюса там не существует', () {
      expect(
        shouldShowPlusPromo(
          gate: PlusGate.hidden,
          nowMs: now,
          lastShownMs: 0,
          installedMs: now - 30 * day,
        ),
        isFalse,
      );
    });

    test('чаще семи часов не повторяем', () {
      expect(
        shouldShowPlusPromo(
          gate: PlusGate.locked,
          nowMs: now,
          lastShownMs: now - 3 * hour,
          installedMs: now - 30 * day,
        ),
        isFalse,
      );
    });

    test('в первые сутки после установки молчим', () {
      // Человек ещё не понял, что это за приложение: витрина в первый день
      // читается как «сначала заплати».
      expect(
        shouldShowPlusPromo(
          gate: PlusGate.locked,
          nowMs: now,
          lastShownMs: 0,
          installedMs: now - 3 * hour,
        ),
        isFalse,
      );
    });

    test('первый показ после суток — можно', () {
      expect(
        shouldShowPlusPromo(
          gate: PlusGate.locked,
          nowMs: now,
          lastShownMs: 0,
          installedMs: now - 2 * day,
        ),
        isTrue,
      );
    });

    test('часы устройства перевели назад — не спамим', () {
      // Отметка из будущего означала бы «показывать каждый раз»: считаем, что
      // показ уже был.
      expect(
        shouldShowPlusPromo(
          gate: PlusGate.locked,
          nowMs: now,
          lastShownMs: now + 5 * day,
          installedMs: now - 30 * day,
        ),
        isFalse,
      );
    });
  });
}
