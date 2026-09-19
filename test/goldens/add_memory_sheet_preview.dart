// Картинки листа «Добавить воспоминание» для сверки с макетом:
// flutter test test/goldens/add_memory_sheet_preview.dart → build/add-sheet/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/app_sheet.dart';
import 'package:love_app/widgets/memory/add_memory_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _font(String family, String path) async {
  final loader = FontLoader(family)
    ..addFont(File(path).readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'app_language': 'ru'});
    await LocaleService.instance.init();
    await _font('Onest', 'assets/fonts/Onest.ttf');
    await _font('Unbounded', 'assets/fonts/Unbounded.ttf');
    await _font('MaterialIcons', '${Platform.environment['FLUTTER_ROOT'] ?? '/home/alelx/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  });

  for (final (name, palette, b, width, scale) in [
    ('pink-light-360', 0, Brightness.light, 360.0, 1.0),
    ('pink-dark-360', 0, Brightness.dark, 360.0, 1.0),
    ('mono-light-320-1.3', 11, Brightness.light, 320.0, 1.3),
    ('mint-dark-320-1.3', 12, Brightness.dark, 320.0, 1.3),
  ]) {
    testWidgets(name, (tester) async {
      final theme = buildAppTheme(kPalettes[palette], b);
      final cs = ProfileTheme.themeFor(theme).colorScheme;
      tester.view.physicalSize = Size(width * 3, 520 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ProfileTheme.data(cs),
          home: MediaQuery(
            data: MediaQueryData(size: Size(width, 520), textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              backgroundColor: cs.surface,
              body: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainer,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  child: SheetScaffold(
                    child: AddMemorySheetBody(
                      scheme: cs, fill: theme.fillColor, onType: (_) {}, onCapsule: () {}),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.runAsync(() async {
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await boundary.toImage(pixelRatio: 2);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        Directory('build/add-sheet').createSync(recursive: true);
        File('build/add-sheet/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
      // ignore: avoid_print
      print('${kPalettes[palette].name}');
    });
  }
}
