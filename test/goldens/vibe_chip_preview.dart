import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/miss_you/vibe_chip.dart';

/// Всплеск у плитки импульса (TOG-40) по кадрам: до нажатия и три момента
/// после, на светлой и тёмной теме.
///
/// Имя без `_test`: файл для глаз. Запуск:
/// `flutter test test/goldens/vibe_chip_preview.dart`, картинка в
/// `build/vibe-chip/burst.png`.
Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  var any = false;
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) continue;
    loader.addFont(file.readAsBytes().then(ByteData.sublistView));
    any = true;
  }
  if (any) await loader.load();
}

void main() {
  setUpAll(() async {
    await _loadFont('Onest', ['assets/fonts/Onest.ttf']);
    await _loadFont('MaterialIcons', [
      '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache'
          '/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);
  });

  testWidgets('всплеск у плитки', (tester) async {
    tester.view.physicalSize = const Size(1900, 520);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final rows = <(String, ColorScheme)>[
      ('светлая', ProfileTheme.schemeFor(AppThemes.byIndex(7))),
      ('тёмная', ProfileTheme.schemeFor(AppThemes.byIndex(20))),
    ];
    final keys = [for (var i = 0; i < 8; i++) GlobalKey()];
    final boundary = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: RepaintBoundary(
        key: boundary,
        child: ColoredBox(
          color: const Color(0xFF171210),
          child: Column(
            children: [
              for (var r = 0; r < rows.length; r++)
                Row(
                  children: [
                    for (var c = 0; c < 4; c++)
                      Container(
                        width: 220,
                        height: 120,
                        margin: const EdgeInsets.all(5),
                        color: rows[r].$2.surface,
                        alignment: const Alignment(0, 0.7),
                        child: Theme(
                          data: ProfileTheme.data(rows[r].$2),
                          child: SizedBox(
                            width: 200,
                            child: VibeChip(
                              key: keys[r * 4 + c],
                              scheme: rows[r].$2,
                              icon: Icons.cloud_rounded,
                              label: 'Думаю о тебе',
                              mine: 1045,
                              partner: 1957,
                              onTap: () {},
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    ));

    // Колонки: до нажатия, 120 мс, 320 мс, 600 мс после. Нажатия разнесены
    // так, чтобы в один кадр попали разные моменты всплеска.
    for (var r = 0; r < rows.length; r++) {
      await tester.tap(find.byKey(keys[r * 4 + 3]));
    }
    await tester.pump(const Duration(milliseconds: 280));
    for (var r = 0; r < rows.length; r++) {
      await tester.tap(find.byKey(keys[r * 4 + 2]));
    }
    await tester.pump(const Duration(milliseconds: 200));
    for (var r = 0; r < rows.length; r++) {
      await tester.tap(find.byKey(keys[r * 4 + 1]));
    }
    await tester.pump(const Duration(milliseconds: 120));

    await tester.runAsync(() async {
      final image = await (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/vibe-chip')..createSync(recursive: true);
      File('${dir.path}/burst.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
    await tester.pump(const Duration(seconds: 2));
  });
}
