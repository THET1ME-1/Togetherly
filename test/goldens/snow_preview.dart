import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/snowball_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/snow/snow_hit_overlay.dart';
import 'package:love_app/widgets/theme/theme_snow_layer.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Снег темы «Новый год» и попадание снежка — на глаз. В общий прогон не
/// входит: `flutter test test/goldens/snow_preview.dart`, снимки в `build/snow/`.
void main() {
  testWidgets('снег и попадание', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await LocaleService.instance.setLanguage(AppLanguage.ru);
    final ny = kPalettes.firstWhere((p) => p.name == 'Новый год');
    final dir = Directory('build/snow')..createSync(recursive: true);
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<void> save(GlobalKey key, String name) async {
      final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final img = await b.toImage(pixelRatio: 2);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    for (final br in Brightness.values) {
      final theme = buildAppTheme(ny, br);
      final key = GlobalKey();
      SnowballService.instance.debugReset();
      await tester.pumpWidget(MaterialApp(
        theme: ProfileTheme.themeFor(theme),
        builder: (context, child) => RepaintBoundary(key: key, child: SnowHitOverlay(onThrowBack: () {}, child: child!)),
        home: Scaffold(
          backgroundColor: theme.bgGradient.first,
          body: Stack(children: [
            Positioned.fill(child: ThemeSnowLayer(theme: theme)),
            Center(child: Card(color: theme.cardSurface, child: const SizedBox(width: 280, height: 160))),
          ]),
        ),
      ));
      // снег разлетелся, снежок уже падает
      await tester.pump(const Duration(seconds: 6));
      await tester.runAsync(() => precacheImage(const AssetImage(kSnowballAsset), key.currentContext!));
      await tester.pump(const Duration(milliseconds: 100));
      await save(key, 'snow_${br.name}');
      SnowballService.instance.hit(2, partnerName: 'Аня');
      await tester.pump();
      for (final (ms, tag) in [(300, 'a'), (900, 'b'), (1600, 'c'), (2700, 'd')]) {
        await tester.pump(Duration(milliseconds: ms - (tag == 'a' ? 0 : 0)));
        await save(key, 'hit_${br.name}_$tag');
      }
      await tester.pump(const Duration(seconds: 4));
    }
  });
}
