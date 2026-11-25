import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/screens/settings/app_icon_screen.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Экран «Иконка приложения» для глаз: `flutter test
/// test/goldens/app_icon_sheet_preview.dart` → build/app-icon-sheet/*.png.
/// Выбрана иконка «Ту», Розовая светлая и тёмная; узкий телефон, обычный и
/// планшет. Имя без `_test`: обычный прогон его не берёт.
Future<void> _font(String family, String path) async {
  final loader = FontLoader(family)
    ..addFont(File(path).readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

void main() {
  setUpAll(() async {
    await _font('Onest', 'assets/fonts/Onest.ttf');
    await _font('Unbounded', 'assets/fonts/Unbounded.ttf');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocaleService.instance.setLanguage(AppLanguage.ru);
  });

  for (final (name, size, dark) in const [
    ('screen', Size(393, 1200), false),
    ('screen_320', Size(320, 1200), false),
    ('screen_dark', Size(393, 1200), true),
    ('screen_tablet', Size(800, 1100), false),
  ]) {
    testWidgets('экран иконки: $name', (tester) => _shoot(tester, name, size, dark));
  }
}

Future<void> _shoot(WidgetTester tester, String name, Size size, bool dark) async {
  final key = GlobalKey();
  final theme = buildAppTheme(kPalettes[0], dark ? Brightness.dark : Brightness.light);
  final scheme = ProfileTheme.themeFor(theme).colorScheme;
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(RepaintBoundary(
    key: key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AppIconScreen(scheme: scheme, currentId: 'tu'),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);

  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/app-icon-sheet/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
