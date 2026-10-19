// Тема «Хэллоуин» глазами: лента палитр с тыквой первой и подпись под
// переключателем режима. Под карточкой виден фон с узором.
//
//     flutter test test/goldens/halloween_theme_preview.dart → build/halloween-theme/
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
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/seed_swatch.dart';
import 'package:love_app/widgets/theme/theme_pattern_layer.dart';

import '../helpers/achievement_harness.dart';

Future<void> _font(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return;
  final loader = FontLoader(family)
    ..addFont(file.readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

void main() {
  setUpAll(() async {
    await _font('Onest', 'assets/fonts/Onest.ttf');
    await _font('Unbounded', 'assets/fonts/Unbounded.ttf');
  });

  testWidgets('лента палитр и образец темы', (tester) async {
    tester.view.physicalSize = const Size(360, 560) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final hw = kPalettes[25];
    final t = buildAppTheme(hw, Brightness.dark);
    final cs = ProfileTheme.schemeFor(t);
    final strip = paletteStripEntries(customCount: 0, plusVisible: false);
    final key = GlobalKey();
    TextStyle caption() => TextStyle(
        fontFamily: 'Onest',
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: cs.onSurfaceVariant);

    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ProfileTheme.data(cs),
        home: Scaffold(
          backgroundColor: t.bgGradient.first,
          body: Stack(children: [
            Positioned.fill(child: ThemePatternLayer(theme: t)),
            Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Палитра', style: caption()),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 62,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: 6,
                          separatorBuilder: (_, _) =>
                              const SizedBox(width: 12),
                          itemBuilder: (_, i) => SeedSwatch(
                            palette: kPalettes[strip[i].index],
                            selected: i == 0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text('Режим', style: caption()),
                      const SizedBox(height: 8),
                      SegmentedButton<int>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                              value: 0, icon: Icon(Icons.light_mode_rounded)),
                          ButtonSegment(
                              value: 1, icon: Icon(Icons.dark_mode_rounded)),
                          ButtonSegment(
                              value: 2,
                              icon: Icon(Icons.brightness_auto_rounded)),
                        ],
                        selected: const {0},
                        onSelectionChanged: (_) {},
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 8, left: 2),
                        child: Text('Эта тема бывает только тёмной',
                            style: caption()
                                .copyWith(fontWeight: FontWeight.w400)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ]),
        ),
      ),
    ));
    await tester.pump();
    await settleImages(tester);

    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 2);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/halloween-theme').createSync(recursive: true);
      File('build/halloween-theme/strip.png')
          .writeAsBytesSync(png!.buffer.asUint8List());
    });
  });
}
