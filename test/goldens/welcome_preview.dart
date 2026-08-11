import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:love_app/models/user_data.dart';
import 'package:love_app/screens/welcome_screen.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/theme_scope.dart';

/// Снимок настоящего онбординга — три экрана подряд.
///
/// Имя без `_test`: сцены анимируются бесконечно, обычный прогон на них не
/// сойдётся. Запуск: `flutter test test/goldens/welcome_preview.dart`,
/// картинки в `build/welcome/`.
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
    await _loadFont('Unbounded', ['assets/fonts/Unbounded.ttf']);
    await _loadFont('MaterialIcons', [
      '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('три экрана онбординга', (tester) async {
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: ThemeScope(
          theme: buildAppTheme(kPalettes[0], Brightness.light),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: WelcomeScreen(userData: UserData()),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1600));

    final dir = Directory('build/welcome')..createSync(recursive: true);
    final s = LocaleService.current;

    for (var i = 0; i < 3; i++) {
      if (i > 0) {
        await tester.tap(find.text(s.welcomeNext));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
      }
      // Ждём момент, когда сцены в живой фазе: двое сошлись, круг налит.
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        File('${dir.path}/slide${i + 1}.png')
            .writeAsBytesSync(data!.buffer.asUint8List());
      });
    }
  });
}
