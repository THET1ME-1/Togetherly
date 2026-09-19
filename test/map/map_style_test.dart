import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/map/map_palette.dart';
import 'package:love_app/services/map/map_style.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

/// Схема розовой темы (снята из buildAppTheme(kPalettes[0])).
ColorScheme _pink(Brightness b) => b == Brightness.light
    ? const ColorScheme.light().copyWith(
        surfaceContainerLowest: const Color(0xFFFFFFFF),
        surfaceContainerLow: const Color(0xFFFFF0F0),
        surfaceContainer: const Color(0xFFFCEAEA),
        surfaceContainerHigh: const Color(0xFFF6E4E4),
        surfaceContainerHighest: const Color(0xFFF0DEDE),
        secondaryContainer: const Color(0xFFFFDADB),
        onSecondaryContainer: const Color(0xFF5C3F41),
        tertiaryContainer: const Color(0xFFFFDDB4),
        onSurface: const Color(0xFF22191A),
        onSurfaceVariant: const Color(0xFF524344),
        outlineVariant: const Color(0xFFD7C1C2),
      )
    : const ColorScheme.dark().copyWith(
        surfaceContainerLowest: const Color(0xFF140C0D),
        surfaceContainerLow: const Color(0xFF22191A),
        surfaceContainer: const Color(0xFF271D1E),
        surfaceContainerHigh: const Color(0xFF312828),
        surfaceContainerHighest: const Color(0xFF3D3233),
        secondaryContainer: const Color(0xFF5C3F41),
        onSecondaryContainer: const Color(0xFFFFDADB),
        tertiaryContainer: const Color(0xFF5C421A),
        onSurface: const Color(0xFFF0DEDE),
        onSurfaceVariant: const Color(0xFFD7C1C2),
        outlineVariant: const Color(0xFF524344),
      );

const _fill = Color(0xFFF37094);

Map<String, dynamic> _base() => jsonDecode(
    File('assets/map/base_style.json').readAsStringSync()) as Map<String, dynamic>;

Map<String, dynamic> _layer(Map<String, dynamic> style, String id) =>
    (style['layers'] as List).cast<Map<String, dynamic>>().firstWhere((l) => l['id'] == id);

void main() {
  group('MapPalette', () {
    test('суша светлой темы — surfaceContainerLow', () {
      final p = MapPalette.of(_pink(Brightness.light), fill: _fill);
      expect(p.land, const Color(0xFFFFF0F0));
    });

    test('вода светлой темы — secondaryContainer с 14% заливки', () {
      final p = MapPalette.of(_pink(Brightness.light), fill: _fill);
      expect(p.water, const Color(0xFFFDCBD1));
    });

    test('вода тёмной темы — суша с 24% заливки, чтобы не тонуть в черноте', () {
      final p = MapPalette.of(_pink(Brightness.dark), fill: _fill);
      // #22191A → #F37094 на 24%: (34+209*.24, 25+87*.24, 26+122*.24) = (84, 46, 55)
      expect(p.water, const Color(0xFF542E37));
    });

    test('нитка между точками — заливка темы', () {
      final p = MapPalette.of(_pink(Brightness.light), fill: _fill);
      expect(p.thread, _fill);
    });

    // Жалоба 19.09.2026: «Почему не Молдова, а мы в середине океана?» Суша на
    // глобусе была бледной, как фон вокруг шара, а вода — насыщенной, и моря,
    // окружённые сушей, читались материками. Суша обязана стоять дальше от
    // фона, чем вода, — тогда глаз берёт её за фигуру.
    for (final b in Brightness.values) {
      test('на глобусе суша выделяется сильнее воды ($b)', () {
        final cs = _pink(b).copyWith(surface: b == Brightness.light ? const Color(0xFFFFF8F7) : const Color(0xFF1A1112));
        final p = MapPalette.of(cs, fill: b == Brightness.light ? _fill : const Color(0xFFF7A5B6));
        double lum(Color c) => c.computeLuminance();
        final sky = lum(p.halo);
        expect((lum(p.globeLand) - sky).abs(), greaterThan((lum(p.water) - sky).abs() * 1.3));
      });
    }

    test('ключ меняется вместе с цветами', () {
      final a = MapPalette.of(_pink(Brightness.light), fill: _fill);
      final b = MapPalette.of(_pink(Brightness.dark), fill: _fill);
      expect(a.key, isNot(b.key));
      expect(a.key, MapPalette.of(_pink(Brightness.light), fill: _fill).key);
    });
  });

  group('buildMapStyle', () {
    final palette = MapPalette.of(_pink(Brightness.light), fill: _fill);

    test('фон карты — цвет суши', () {
      final s = buildMapStyle(_base(), palette, lang: 'ru');
      expect(_layer(s, 'background')['paint']['background-color'], '#FFF0F0');
    });

    test('вода перекрашена', () {
      final s = buildMapStyle(_base(), palette, lang: 'ru');
      expect(_layer(s, 'water')['paint']['fill-color'], '#FDCBD1');
    });

    test('подписи на языке приложения и шрифтом Onest', () {
      final s = buildMapStyle(_base(), palette, lang: 'de');
      final city = _layer(s, 'label_city');
      expect(city['layout']['text-field'], [
        'coalesce',
        ['get', 'name:de'],
        ['get', 'name'],
      ]);
      expect(city['layout']['text-font'], ['Onest']);
    });

    test('исходный стиль не портится', () {
      final base = _base();
      final before = jsonEncode(base);
      buildMapStyle(base, palette, lang: 'ru');
      expect(jsonEncode(base), before);
    });

    test('отрисовщик принимает все слои стиля', () {
      final base = _base();
      final theme = vtr.ThemeReader().read(buildMapStyle(base, palette, lang: 'ru'));
      expect(theme.layers.length, (base['layers'] as List).length);
    });
  });
}
