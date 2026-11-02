import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/widgets/app_icon_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Лист «Иконка приложения» для глаз: `flutter test
/// test/goldens/app_icon_sheet_preview.dart` → build/app-icon-sheet/sheet.png.
/// Выбрана иконка «Ту», Розовая светлая, 393 точки. Имя без `_test`: обычный
/// прогон его не берёт.
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

  testWidgets('лист иконок с Ту', (tester) async {
    final key = GlobalKey();
    final theme = buildAppTheme(kPalettes[0], Brightness.light);
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showAppIconSheet(context, theme: theme, currentId: 'tu'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
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
      final file = File('build/app-icon-sheet/sheet.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
