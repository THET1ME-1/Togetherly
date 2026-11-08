// Тема «Уютная осень» глазами: лента палитр с листом первой, карточка,
// кнопка и круг таймера на фоне с листопадом, светлая и тёмная.
//
//     flutter test test/goldens/autumn_theme_preview.dart → build/autumn-theme/
//
// Инструмент осмотра, а не проверка: имя без `_test`.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/custom_theme.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/seed_swatch.dart';
import 'package:love_app/widgets/theme/theme_leaves_layer.dart';

import '../helpers/achievement_harness.dart';

Future<void> _font(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return;
  final loader = FontLoader(family)
    ..addFont(file.readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

Widget _phone(AppTheme t) {
  final cs = ProfileTheme.schemeFor(t);
  final strip = paletteStripEntries(customCount: 0, plusVisible: false);
  TextStyle caption() => TextStyle(fontFamily: 'Onest', fontSize: 12.5, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant);
  return Theme(
    data: ProfileTheme.data(cs),
    child: Container(
      color: t.bgGradient.first,
      child: Stack(children: [
        // Листья застывают (выключенная анимация), чтобы кадр был один.
        Positioned.fill(
          child: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: ThemeLeavesLayer(theme: t),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: t.cardSurface, borderRadius: BorderRadius.circular(28)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Палитра', style: caption()),
                const SizedBox(height: 8),
                SizedBox(
                  height: 62,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: 5,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (_, i) => SeedSwatch(palette: kPalettes[strip[i].index], selected: strip[i].index == 26),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 120),
            Center(
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(shape: BoxShape.circle, color: t.timerDialBackground),
                alignment: Alignment.center,
                child: Text('312', style: TextStyle(fontFamily: 'Unbounded', fontSize: 34, fontWeight: FontWeight.w700, color: t.textPrimary)),
              ),
            ),
            const SizedBox(height: 120),
            FilledButton(onPressed: () {}, child: const Text('Открыть сундук', style: TextStyle(fontFamily: 'Onest'))),
            const SizedBox(height: 10),
            FilledButton.tonal(onPressed: () {}, child: const Text('Мох — второй цвет', style: TextStyle(fontFamily: 'Onest'))),
          ]),
        ),
      ]),
    ),
  );
}

void main() {
  setUpAll(() async {
    await _font('Onest', 'assets/fonts/Onest.ttf');
    await _font('Unbounded', 'assets/fonts/Unbounded.ttf');
  });

  testWidgets('светлая и тёмная с листопадом', (tester) async {
    tester.view.physicalSize = const Size(760, 760) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final au = kPalettes[26];
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Row(children: [
          SizedBox(width: 370, child: _phone(buildAppTheme(au, Brightness.light))),
          const SizedBox(width: 20),
          SizedBox(width: 370, child: _phone(buildAppTheme(au, Brightness.dark))),
        ]),
      ),
    ));
    await tester.pump();
    await settleImages(tester);

    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 2);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/autumn-theme').createSync(recursive: true);
      File('build/autumn-theme/theme.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  });
}
