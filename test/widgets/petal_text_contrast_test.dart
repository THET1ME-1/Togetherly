import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/utils/readable_text.dart';
import 'package:love_app/widgets/petal_timer_dial.dart';

/// Подписи лепестков были прибиты к белому. Пока заливка круга шла сырым
/// насыщенным акцентом, белое читалось; после перевода палитр на M3 круг стал
/// пастельным, и «0 Сек», «1 Лет» на нём пропали.
void main() {
  group('подпись лепестка', () {
    test('читается на пустом лепестке в любой теме', () {
      for (final p in kPalettes) {
        for (final b in Brightness.values) {
          final t = buildAppTheme(p, b);
          expect(
            contrastRatio(petalTextColor(t, 0), t.timerDialBackground),
            greaterThanOrEqualTo(4.5),
            reason: '${p.name} (${b.name})',
          );
        }
      }
    });

    test('читается на заполненной части', () {
      for (final p in kPalettes) {
        for (final b in Brightness.values) {
          final t = buildAppTheme(p, b);
          expect(
            contrastRatio(petalTextColor(t, 1), t.fillColor),
            greaterThanOrEqualTo(4.5),
            reason: '${p.name} (${b.name})',
          );
        }
      }
    });

    test('подложка меняется на середине заполнения', () {
      final t = buildAppTheme(kPalettes.first, Brightness.light);
      expect(petalTextColor(t, 0.9), petalTextColor(t, 1));
      expect(petalTextColor(t, 0.1), petalTextColor(t, 0));
    });
  });
}
