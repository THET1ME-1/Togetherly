import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/utils/readable_text.dart';

/// Сторож заливки: цветной блок обязан быть виден на фоне страницы.
///
/// Повод — баннер «Создать открытку», который на светлой теме пропадал совсем.
/// Он был выкрашен `primaryContainer`, а у тем, нарисованных руками, эта роль
/// берётся из `primaryLight`, то есть из «чуть тонированного фона»: контраст к
/// странице выходил 1,00 у Фиолетовой и 1,04 у Вишнёвой. У вычисленных тем в
/// той же роли лежит заливка, поэтому в тёмном режиме всё было видно, и баг
/// казался «только в светлой теме».
///
/// Замер по всем палитрам в обеих яркостях (худший случай):
/// заливка 2,05 · primaryContainer 1,00 · secondaryContainer 1,05 ·
/// surfaceContainerHigh 1,01. Отсюда правило: **сплошной цветной блок красится
/// `AppTheme.fillColor`**, а роли-контейнеры годятся только поверх карточки, не
/// поверх фона страницы.
void main() {
  /// Ниже этого фон и блок сливаются: 1,5 — уже различимая ступень, а мерить
  /// по WCAG 3:1 нельзя, у тональных заливок такого запаса нет и не должно быть.
  const minRatio = 1.5;

  test('заливка темы видна на фоне страницы во всех палитрах', () {
    final offenders = <String>[];
    for (final brightness in [Brightness.light, Brightness.dark]) {
      for (final palette in kPalettes) {
        final theme = buildAppTheme(palette, brightness);
        for (final bg in theme.bgGradient) {
          final ratio = contrastRatio(theme.fillColor, bg);
          if (ratio < minRatio) {
            offenders.add('${palette.name} ${brightness.name}: '
                '${ratio.toStringAsFixed(2)}');
          }
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'заливка сливается с фоном: ${offenders.join(', ')}');
  });

  /// Правило чернил задано, а не вычислено (решение заказчика 11 августа
  /// 2026): в светлых темах поверх цветного пишем белым, даже когда чёрный
  /// контрастнее. Чёрные подписи на персиковой и закатной заливке выглядели
  /// дёшево, а контраст там и с белым остаётся в районе 2,4–3,2.
  ///
  /// Исключение — совсем светлые заливки (яркость 0,41 и выше, это тон 70 по
  /// HCT): мятная и медовая, где белым не разобрать даже вывеску.
  ///
  /// Тёмные темы считают по контрасту, как раньше: их заливки пастельные,
  /// белый по ним даёт 1,7.
  test('чернила на заливке подчиняются правилу', () {
    for (final palette in kPalettes) {
      final light = buildAppTheme(palette, Brightness.light);
      final ink = AppThemes.onColor(light.fillColor, mode: Brightness.light);
      final veryLight = light.fillColor.computeLuminance() >= 0.407;
      expect(
        ink,
        veryLight ? isNot(const Color(0xFFFFFFFF)) : const Color(0xFFFFFFFF),
        reason: '${palette.name}: заливка ${light.fillColor}',
      );

      final dark = buildAppTheme(palette, Brightness.dark);
      final darkInk = AppThemes.onColor(dark.fillColor, mode: Brightness.dark);
      expect(
        contrastRatio(darkInk, dark.fillColor),
        greaterThanOrEqualTo(4.3),
        reason: '${palette.name} тёмная: подпись на заливке',
      );
    }
  });
}
