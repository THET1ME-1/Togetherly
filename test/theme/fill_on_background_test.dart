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

  /// Порог ниже канонических 4,5 не по лени: две ручные палитры стоят ровно на
  /// границе — «Северное сияние» светлая даёт 4,35 (заливка `#7C5CFF`),
  /// «Нордик» светлая 4,48. Подписи на заливке у нас крупные и жирные, для них
  /// WCAG просит 3,0, так что читаются обе. Сторож здесь про другое: поймать
  /// заливку, у которой чернила проваливаются по-настоящему.
  test('чернила на заливке читаются', () {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      for (final palette in kPalettes) {
        final theme = buildAppTheme(palette, brightness);
        final ink = AppThemes.onColor(theme.fillColor);
        expect(
          contrastRatio(ink, theme.fillColor),
          greaterThanOrEqualTo(4.3),
          reason: '${palette.name} ${brightness.name}: подпись на заливке',
        );
      }
    }
  });
}
