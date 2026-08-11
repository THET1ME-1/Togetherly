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

    /// На заполненной части подпись подчиняется общему правилу чернил
    /// (`AppThemes.onColor`): в светлых темах белым по решению заказчика от
    /// 11 августа 2026, даже когда чёрный контрастнее. Исключение — совсем
    /// светлые заливки (мятная, медовая). В тёмных темах по-прежнему считаем
    /// контраст: там заливки пастельные.
    test('на заполненной части следует правилу чернил', () {
      for (final p in kPalettes) {
        final light = buildAppTheme(p, Brightness.light);
        final veryLight = light.fillColor.computeLuminance() >= 0.407;
        expect(
          petalTextColor(light, 1),
          veryLight
              ? isNot(const Color(0xFFFFFFFF))
              : const Color(0xFFFFFFFF),
          reason: '${p.name} (light)',
        );

        final dark = buildAppTheme(p, Brightness.dark);
        expect(
          contrastRatio(petalTextColor(dark, 1), dark.fillColor),
          greaterThanOrEqualTo(4.3),
          reason: '${p.name} (dark)',
        );
      }
    });

    test('подложка меняется на середине заполнения', () {
      final t = buildAppTheme(kPalettes.first, Brightness.light);
      expect(petalTextColor(t, 0.9), petalTextColor(t, 1));
      expect(petalTextColor(t, 0.1), petalTextColor(t, 0));
    });
  });
}
