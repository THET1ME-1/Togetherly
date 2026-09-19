import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/map/map_palette.dart';
import 'package:love_app/services/map/map_style.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

/// Настоящий тайл OpenFreeMap (Москва, z11) проходит весь путь: разбор
/// protobuf (vector_tile 4 подменён поверх рендера, собранного под 2-ю
/// версию), тема из цветов приложения и отрисовка. Сломайся разбор — карта
/// у людей была бы пустой, а сборка зелёной.
void main() {
  testWidgets('тайл Москвы рисуется в цветах темы', (tester) async {
    final base = jsonDecode(File('assets/map/base_style.json').readAsStringSync()) as Map<String, dynamic>;
    final cs = const ColorScheme.light().copyWith(
      surfaceContainerLow: const Color(0xFFFFF0F0),
      secondaryContainer: const Color(0xFFFFDADB),
      tertiaryContainer: const Color(0xFFFFDDB4),
    );
    final palette = MapPalette.of(cs, fill: const Color(0xFFF37094));
    final theme = vtr.ThemeReader().read(buildMapStyle(base, palette, lang: 'ru'));

    final bytes = File('test/fixtures/map/moscow_z11.pbf').readAsBytesSync();
    final tile = vtr.TileFactory(theme, const vtr.Logger.noop()).createTileData(vtr.VectorTileReader().read(bytes)).toTile();
    expect(tile.layers.map((l) => l.name), containsAll(['water', 'transportation', 'place']));

    final image = await tester.runAsync(() => vtr.ImageRenderer(theme: theme, scale: 1)
        .render(vtr.TileSource(tileset: vtr.Tileset({'openmaptiles': tile})), zoom: 11));
    final data = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.rawRgba));
    final px = data!.buffer.asUint8List();

    int count(Color c) {
      final r = (c.r * 255).round(), g = (c.g * 255).round(), b = (c.b * 255).round();
      var n = 0;
      for (var i = 0; i < px.length; i += 4) {
        if ((px[i] - r).abs() < 3 && (px[i + 1] - g).abs() < 3 && (px[i + 2] - b).abs() < 3) n++;
      }
      return n;
    }

    final total = px.length ~/ 4;
    // На тайле центра Москвы видны и вода (Москва-река), и кварталы.
    expect(count(palette.water), greaterThan(total ~/ 200));
    expect(count(palette.residential) + count(palette.land), greaterThan(total ~/ 10));
  });
}
