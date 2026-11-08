import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/plus_access.dart';
import 'package:love_app/widgets/plus/plus_promo_rule.dart';

void main() {
  const hour = 3600 * 1000;
  const day = 24 * hour;
  const now = 1786000000000;

  group('shouldShowPlusPromo', () {
    test('некупившему через три дня после прошлого раза — показываем', () {
      expect(
        shouldShowPlusPromo(
          gate: PlusGate.locked,
          nowMs: now,
          lastShownMs: now - 3 * day,
          plusKnown: true,
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
          plusKnown: true,
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
          plusKnown: true,
          installedMs: now - 30 * day,
        ),
        isFalse,
      );
    });

    // Раз в 7 часов при нескольких заходах в день выходило «окно покупки при
    // каждом заходе» (отзыв в App Store 29.09.2026), владелец 08.11.2026:
    // «пусть раз в 2-3 дня показывается».
    test('через два дня ещё молчим', () {
      expect(
        shouldShowPlusPromo(
          gate: PlusGate.locked,
          nowMs: now,
          lastShownMs: now - 2 * day,
          plusKnown: true,
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
          plusKnown: true,
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
          plusKnown: true,
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
          plusKnown: true,
          installedMs: now - 30 * day,
        ),
        isFalse,
      );
    });

    test('флаг Плюса ещё не прочитан — молчим', () {
      // Холодный старт: `users.plus` лежит на сервере, и до ответа приложение
      // считает человека не купившим. Витрина в эту секунду показывалась тому,
      // у кого Плюс есть, — жалоба тестировщицы 19 августа 2026.
      expect(
        shouldShowPlusPromo(
          gate: PlusGate.locked,
          nowMs: now,
          plusKnown: false,
          lastShownMs: 0,
          installedMs: now - 30 * day,
        ),
        isFalse,
      );
    });
  });
  // Отзыв 10.09.2026: «после обновления при каждом заходе окно, чтоб сделали
  // покупку». После обновления главная показывала подряд ДВЕ витрины: экран
  // Togetherly+ про новую версию и, стоило его закрыть, нижний лист
  // напоминания. Экран обязан засчитываться за напоминание.
  test('экран Плюса после обновления засчитан за напоминание', () {
    final src = File('lib/screens/home_screen.dart').readAsStringSync();
    final pitch = src
        .split('Future<void> _maybePitchPlus() async {')[1]
        .split('\n  }\n')[0];
    final mark = pitch.indexOf('UiPrefs.setPlusPromoShown(');
    final push = pitch.indexOf('PlusScreen(');
    expect(mark, greaterThan(-1),
        reason: 'без отметки лист напоминания выскакивает следом за экраном');
    expect(mark, lessThan(push));
  });
}
