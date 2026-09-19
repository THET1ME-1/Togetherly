// Картинки виджета «Где мы» для глаз и для превью в списке виджетов лончера:
//
//   flutter test test/goldens/pair_map_widget_preview.dart
//
// Плитки Кишинёва берутся из build/map-widget-tiles/<z>/<x>/<y>.pbf — их
// качает разовый скрипт (в репозиторий не кладём, это десять мегабайт).
// Картинки ложатся в build/map-widget-preview/.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/pair_map_widget_view.dart';
import 'package:love_app/services/live_location_service.dart' show LivePoint;
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/map/pair_map_widget_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _font(String family, String path) async {
  final f = File(path);
  if (!f.existsSync()) return;
  final loader = FontLoader(family)..addFont(f.readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

Future<Uint8List?> _tile(int z, int x, int y) async {
  final f = File('build/map-widget-tiles/$z/$x/$y.pbf');
  return f.existsSync() ? f.readAsBytes() : null;
}

/// Аватарка-заглушка: мягкий градиент с кругом, как снимок лица издалека.
Future<Uint8List> _fakeAvatar(Color a, Color b) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  const r = Rect.fromLTWH(0, 0, 160, 160);
  c.drawRect(r, Paint()..shader = ui.Gradient.linear(r.topLeft, r.bottomRight, [a, b]));
  c.drawCircle(const Offset(80, 70), 30, Paint()..color = const Color(0xFFF6D5C2));
  c.drawOval(const Rect.fromLTWH(30, 108, 100, 80), Paint()..color = const Color(0xFF5B4A86));
  final img = await rec.endRecording().toImage(160, 160);
  final png = await img.toByteData(format: ui.ImageByteFormat.png);
  return png!.buffer.asUint8List();
}

LivePoint _p(double lat, double lng, {int agoMin = 2}) => LivePoint(
      lat: lat,
      lng: lng,
      accuracy: 10,
      updatedAt: DateTime(2026, 9, 19, 20, 0).millisecondsSinceEpoch - agoMin * 60000,
    );

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'app_language': 'ru'});
    await LocaleService.instance.init();
    await _font('Onest', 'assets/fonts/Onest.ttf');
    await _font('Unbounded', 'assets/fonts/Unbounded.ttf');
    await _font('MaterialIcons',
        '/home/alelx/snap/flutter/common/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  });

  final me = _p(47.0245, 28.8325);
  final botanica = _p(46.9960, 28.8575, agoMin: 12);
  final scenarios = <String, (LivePoint?, LivePoint?, bool)>{
    'map': (me, botanica, true),
    'near': (me, _p(47.02452, 28.83256), true),
    'berlin': (me, _p(52.52, 13.405, agoMin: 95), true),
    'newyork': (me, _p(40.7128, -74.006, agoMin: 30), true),
    'only-me': (me, null, true),
    'no-pair': (null, null, false),
  };

  for (final dark in [false, true]) {
    for (final e in scenarios.entries) {
      final name = '${e.key}-${dark ? 'dark' : 'light'}';
      testWidgets(name, (tester) async {
        await tester.runAsync(() async {
          final b = dark ? Brightness.dark : Brightness.light;
          final t = buildAppTheme(kPalettes.first, b);
          final images = await renderPairMapWidgets(
            PairMapWidgetInput(
              paired: e.value.$3,
              me: e.value.$1,
              partner: e.value.$2,
              myName: 'Саша',
              partnerName: 'Аня',
              myAvatar: await _fakeAvatar(const Color(0xFFFFB38A), const Color(0xFFFF7E8B)),
              partnerAvatar: await _fakeAvatar(const Color(0xFF8FB6FF), const Color(0xFF6A4C93)),
              scheme: ProfileTheme.themeFor(t).colorScheme,
              fill: t.fillColor,
              sizes: {for (final k in MapWidgetSize.values) k: k.size},
              nowMs: DateTime(2026, 9, 19, 20, 0).millisecondsSinceEpoch,
              myPlace: 'Центр',
              partnerPlace: 'Ботаника',
            ),
            tiles: _tile,
          );
          Directory('build/map-widget-preview').createSync(recursive: true);
          for (final img in images.entries) {
            File('build/map-widget-preview/${name}_${img.key.id}.png').writeAsBytesSync(img.value);
          }
          expect(images.length, 3);
        });
      });
    }
  }
}
