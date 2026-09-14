import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/year_ring_spec.dart';

void main() {
  const inner = YearRingSpec.ring - 2 * YearRingSpec.stroke;

  group('число внутри кольца', () {
    // Снимок с iPhone 14.09.2026: «1288» выходило за кольцо.
    for (final days in [7, 125, 1288, 12345]) {
      test('$days помещается во внутренний диаметр', () {
        final digits = '$days'.length;
        final size =
            YearRingSpec.numberSize(inner: inner, digits: digits, max: 36);
        final width = digits * YearRingSpec.digitEm * size;
        expect(width, lessThanOrEqualTo(inner * YearRingSpec.numberShare + 0.01));
        expect(size, lessThanOrEqualTo(36));
      });
    }

    test('короткое число не раздувается сверх потолка', () {
      expect(YearRingSpec.numberSize(inner: inner, digits: 3, max: 36), 36);
    });
  });

  test('длинная строка уменьшается, короткая остаётся базовой', () {
    expect(YearRingSpec.fitText(base: 12.5, chars: 10, width: 164), 12.5);
    final small = YearRingSpec.fitText(base: 12.5, chars: 40, width: 164);
    expect(small * 40 * YearRingSpec.letterEm, lessThanOrEqualTo(164.01));
  });

  test('конец дуги: старт на двенадцати часах, четверть — справа', () {
    const c = Offset(78, 79);
    final top = YearRingSpec.arcEnd(c, 59, 0);
    expect(top.dx, closeTo(78, 0.001));
    expect(top.dy, closeTo(20, 0.001));
    final right = YearRingSpec.arcEnd(c, 59, 0.25);
    expect(right.dx, closeTo(137, 0.001));
    expect(right.dy, closeTo(79, 0.001));
  });

  group('нативные виджеты повторяют правила', () {
    final kotlin = File(
      'android/app/src/main/kotlin/com/togetherly/love/YearRingWidgetProvider.kt',
    ).readAsStringSync();
    final swift =
        File('ios/TogetherlyWidget/YearWidgets.swift').readAsStringSync();

    for (final (name, src) in [('Android', kotlin), ('iPhone', swift)]) {
      test('$name: те же доли числа и букв', () {
        expect(src, contains('0.74'), reason: 'доля диаметра под число');
        expect(src, contains('0.58'), reason: 'ширина цифры');
        expect(src, contains('0.56'), reason: 'ширина буквы');
      });

      test('$name: подписи не красятся светлым акцентом', () {
        // accentOnPrimary на заливке primary давал контраст 1,4: подписи
        // «месяцев» и «воспоминаний» сливались с фоном.
        expect(src.contains('accentOnPrimary'), isFalse);
      });
    }
  });
}
