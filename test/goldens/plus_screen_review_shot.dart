import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:love_app/screens/plus_screen.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';

/// Снимок экрана Togetherly+ для карточки товара в App Store Connect.
///
/// Apple требует к покупке скриншот, показывающий, где она живёт в приложении.
/// Снимать его с телефона неудобно и незачем: экран рисуется из настоящего
/// кода, и снимок всегда совпадает с тем, что увидит ревьюер.
///
/// Имя без `_test`: файл для глаз, а не сторож. Запуск:
/// `flutter test test/goldens/plus_screen_review_shot.dart`,
/// картинка — `build/asc/plus-screen.png`.
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
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({'app_language': 'ru'});
    await LocaleService.instance.init();
    // Без настоящих шрифтов тест рисует чёрные прямоугольники вместо букв —
    // такой снимок в карточке товара выглядит как поломка приложения.
    await _loadFont('Onest', ['assets/fonts/Onest.ttf']);
    await _loadFont('Unbounded', ['assets/fonts/Unbounded.ttf']);
    await _loadFont('MaterialIcons', [
      '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache/'
          'artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);
    await _loadFont('MaterialSymbolsRounded', [
      'assets/fonts/MaterialSymbolsRounded.ttf',
    ]);
  });

  testWidgets('экран Togetherly+ для ревью', (tester) async {
    // 1290×2796 — снимок iPhone 15 Pro Max, размер, который принимает ASC.
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    final theme = buildAppTheme(kPalettes[0], Brightness.light);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorScheme: theme.scheme, fontFamily: 'Onest'),
        home: RepaintBoundary(
          key: key,
          child: PlusScreen(scheme: theme.scheme!),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    final dir = Directory('build/asc')..createSync(recursive: true);
    final file = File('${dir.path}/plus-screen.png');
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
    // ignore: avoid_print
    print('снимок: ${file.absolute.path} (${file.lengthSync()} б)');
  });
}
