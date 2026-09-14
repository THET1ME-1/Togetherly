import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/year_ring_spec.dart';
import 'package:love_app/services/widget_theme_sync.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/utils/readable_text.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

/// Виджеты рабочего стола обязаны читаться на КАЖДОЙ теме, а не на тех, где
/// их рисовали.
///
/// Замер 14.09.2026 по всем сочетаниям — 25 палитр, светлая и тёмная
/// яркость, три варианта насыщенности, AMOLED: у 28 светлых белые подписи на
/// заливке `primary` давали меньше 3:1 (Лимонная 1,97, Розовая 2,00, Песочная
/// 2,03). На «Кольце года» это и было «текст сливается». Правило «на цвете
/// пишем белым» остаётся, поэтому вместо цвета надписи глубже становится
/// сама заливка — тем же оттенком.
void main() {
  /// Все темы приложения плюс свои цвета на краях: чистые жёлтый, белый,
  /// чёрный и голубой.
  List<(String, ColorScheme)> allSchemes() {
    final out = <(String, ColorScheme)>[];
    final palettes = [
      ...kPalettes,
      for (final c in const [
        Color(0xFFFFFF00),
        Color(0xFFFFFFFF),
        Color(0xFF000000),
        Color(0xFF00E5FF),
      ])
        customPalette(c, slot: 0),
    ];
    for (final p in palettes) {
      for (final b in Brightness.values) {
        for (final f in SchemeFlavor.values) {
          for (final amoled in [false, true]) {
            if (amoled && b == Brightness.light) continue;
            final t = buildAppTheme(p, b, flavor: f, amoled: amoled);
            out.add((
              '${p.name} ${b.name} ${f.name}${amoled ? ' amoled' : ''}',
              t.scheme!,
            ));
          }
        }
      }
    }
    return out;
  }

  final schemes = allSchemes();

  test('тем проверено все — палитры, яркость, насыщенность, AMOLED', () {
    expect(schemes.length, greaterThanOrEqualTo(225));
  });

  test('подпись на заливке виджета читается на каждой теме', () {
    final bad = <String>[];
    for (final (name, scheme) in schemes) {
      final r = WidgetThemeSync.rolesOf(scheme);
      final fill = r['primary']!;
      final on = r['onPrimary']!;
      // Самый светлый угол фона «Кольца года» и вторичная подпись на нём.
      final corner = YearRingSpec.lightOf(fill);
      final soft = Color.alphaBlend(
        on.withValues(alpha: YearRingSpec.softAlpha),
        corner,
      );
      final main = contrastRatio(on, fill);
      final second = [
        contrastRatio(soft, corner),
        contrastRatio(r['onPrimarySoft']!, fill),
      ].reduce((a, b) => a < b ? a : b);
      if (main < WidgetThemeSync.minFillContrast ||
          second < WidgetThemeSync.minSoftContrast) {
        bad.add('$name: ${main.toStringAsFixed(2)} / ${second.toStringAsFixed(2)}');
      }
    }
    expect(bad, isEmpty, reason: 'подписи сливаются:\n${bad.join('\n')}');
  });

  test('заливка остаётся цветом темы: оттенок тот же', () {
    for (final (name, scheme) in schemes) {
      final fill = WidgetThemeSync.rolesOf(scheme)['primary']!;
      final a = Hct.fromInt(scheme.primary.toARGB32());
      final b = Hct.fromInt(fill.toARGB32());
      if (a.chroma < 8) continue; // у серых оттенок не определён
      final d = (a.hue - b.hue).abs() % 360;
      expect(d > 180 ? 360 - d : d, lessThan(12), reason: name);
    }
  });

  test('читаемые темы не трогаем вовсе', () {
    for (final (name, scheme) in schemes) {
      final on = scheme.onPrimary;
      final fill = scheme.primary;
      final corner = YearRingSpec.lightOf(fill);
      final soft = Color.alphaBlend(
        on.withValues(alpha: YearRingSpec.softAlpha),
        corner,
      );
      final softRole =
          Color.lerp(fill, on, WidgetThemeSync.softShare)!;
      if (contrastRatio(on, fill) >= WidgetThemeSync.minFillContrast &&
          contrastRatio(soft, corner) >= WidgetThemeSync.minSoftContrast &&
          contrastRatio(softRole, fill) >= WidgetThemeSync.minSoftContrast) {
        expect(WidgetThemeSync.rolesOf(scheme)['primary'], fill, reason: name);
      }
    }
  });

  test('розовая остаётся сочной, а не буреет', () {
    final s = buildAppTheme(kPalettes[0], Brightness.light).scheme!;
    final fill = WidgetThemeSync.rolesOf(s)['primary']!;
    final a = Hct.fromInt(s.primary.toARGB32());
    final b = Hct.fromInt(fill.toARGB32());
    expect(a.tone - b.tone, lessThan(10),
        reason: 'заливка темнее темы больше чем на 10 тонов');
  });
}
