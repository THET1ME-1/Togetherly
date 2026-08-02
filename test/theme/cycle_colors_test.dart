// Пара из двух девушек ведёт два цикла, и сетки лежат одна под другой. Пока
// метка у обеих была одного красного, чьи это дни, приходилось вспоминать по
// заголовку — а он уезжает вверх при первой прокрутке.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/theme/cycle_colors.dart';

void main() {
  group('CycleColors.period — чей это день', () {
    test('свой и партнёрский цвет не совпадают ни в одной теме', () {
      for (final brightness in Brightness.values) {
        expect(
          CycleColors.period(brightness, partner: false),
          isNot(CycleColors.period(brightness, partner: true)),
          reason: 'тема ${brightness.name}',
        );
      }
    });

    test('свой цвет в светлой теме остался прежним', () {
      // Тот же красный, что стоял в календаре до разделения: привычную метку
      // не трогаем, новый цвет получает только партнёрша.
      expect(
        CycleColors.period(Brightness.light, partner: false),
        const Color(0xFFD32F2F),
      );
    });

    test('в тёмной теме оба цвета светлее, чем в светлой', () {
      for (final partner in [false, true]) {
        final light = HSLColor.fromColor(
            CycleColors.period(Brightness.light, partner: partner));
        final dark = HSLColor.fromColor(
            CycleColors.period(Brightness.dark, partner: partner));
        expect(dark.lightness, greaterThan(light.lightness),
            reason: partner ? 'партнёрский' : 'свой');
      }
    });

    test('цвета разведены по тону, а не только по яркости', () {
      // Разная яркость одного тона при цветовой слепоте сливается. Тона должны
      // отличаться заметно — иначе метка снова становится неразличимой.
      for (final brightness in Brightness.values) {
        final mine =
            HSLColor.fromColor(CycleColors.period(brightness, partner: false));
        final hers =
            HSLColor.fromColor(CycleColors.period(brightness, partner: true));
        final gap = (mine.hue - hers.hue).abs();
        expect(gap > 60 && gap < 300, isTrue,
            reason: 'тема ${brightness.name}: разница тона $gap°');
      }
    });
  });
}
