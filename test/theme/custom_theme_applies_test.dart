import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:love_app/models/custom_theme.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';

/// Своя тема обязана красить приложение своим цветом.
///
/// `buildAppTheme` начинается с `AppThemes.byIndex(p.index)`, а у своей темы
/// индекс за тысячей, и `byIndex` отдаёт ПЕРВУЮ готовую палитру — розовую.
/// Пока это не проверялось, цвет из фотографии и из пикера не доезжал никуда:
/// кружок в ленте зелёный и с галочкой, а всё приложение остаётся розовым
/// (снимки человека, 18.08.2026).
void main() {
  double hueOf(Color c) => Hct.fromInt(c.toARGB32()).hue;

  /// Разница оттенков по кругу.
  double hueGap(double a, double b) {
    final d = (a - b).abs() % 360;
    return math.min(d, 360 - d);
  }

  const green = Color(0xFF7CB342);
  const blue = Color(0xFF2962FF);

  AppTheme themeOf(Color seed, Brightness brightness) {
    final palette = paletteFor(
      customPaletteIndex(0),
      [CustomTheme(seed: seed, name: 'Из фото')],
    );
    return buildAppTheme(palette, brightness, flavor: SchemeFlavor.soft);
  }

  test('зелёный из фотографии красит тему зелёным, а не розовым', () {
    final t = themeOf(green, Brightness.light);
    expect(hueGap(hueOf(t.fillColor), hueOf(green)), lessThan(25),
        reason: 'заливка ушла от цвета человека: ${t.fillColor}');
    expect(hueGap(hueOf(t.primary), hueOf(green)), lessThan(25),
        reason: 'надпись ушла от цвета человека: ${t.primary}');
  });

  test('своя тема отличается от палитры по умолчанию', () {
    final mine = themeOf(blue, Brightness.light);
    final fallback = buildAppTheme(paletteByIndex(0), Brightness.light,
        flavor: SchemeFlavor.soft);
    expect(mine.fillColor, isNot(fallback.fillColor));
    expect(mine.bgGradient.first, isNot(fallback.bgGradient.first));
  });

  test('в тёмном режиме цвет остаётся своим', () {
    final t = themeOf(blue, Brightness.dark);
    expect(t.brightness, Brightness.dark);
    expect(hueGap(hueOf(t.fillColor), hueOf(blue)), lessThan(25),
        reason: 'тёмная своя тема потеряла оттенок: ${t.fillColor}');
  });

  test('две свои темы дают разные цвета', () {
    expect(
      themeOf(green, Brightness.light).fillColor,
      isNot(themeOf(blue, Brightness.light).fillColor),
    );
  });
}
