import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/help_items.dart';
import 'package:love_app/screens/help_screen.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/theme/profile_theme.dart';

/// Справка «Как сделать» на розовой теме: экран и лист ответа, 393 и 320.
///
/// Имя без `_test`: файл для глаз. Запуск:
/// `flutter test test/goldens/help_preview.dart`, картинка в
/// `build/qr-preview/help.png`.
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
      '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache'
          '/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);
  });

  testWidgets('справка', (tester) async {
    LocaleService.instance.setLanguage(AppLanguage.ru);
    tester.view.physicalSize = const Size(2440, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final cs = ProfileTheme.schemeFor(AppThemes.pink);
    final key = GlobalKey();
    final item = helpItems(plusInStore: true).firstWhere((i) => i.id == 'widgetPhoto');

    Widget phone(double w, Widget child) => Container(
          width: w,
          height: 860,
          margin: const EdgeInsets.all(12),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
              color: cs.surface, borderRadius: BorderRadius.circular(28)),
          child: child,
        );

    // Лист ответа открываем в своём навигаторе внутри «телефона».
    Widget withAnswer(double w) => phone(
          w,
          Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (ctx) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  showHelpAnswer(ctx,
                      item: item,
                      scheme: cs,
                      onAction: (_) {},
                      onWriteUs: () {});
                });
                return HelpScreen(
                    scheme: cs,
                    plusInStore: true,
                    onAction: (_) {},
                    onWriteUs: () {});
              },
            ),
          ),
        );

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ProfileTheme.data(cs),
      home: RepaintBoundary(
        key: key,
        child: ColoredBox(
          color: const Color(0xFF171210),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              phone(
                  393,
                  HelpScreen(
                      scheme: cs,
                      plusInStore: true,
                      onAction: (_) {},
                      onWriteUs: () {})),
              withAnswer(393),
              phone(
                  320,
                  HelpScreen(
                      scheme: cs,
                      plusInStore: false,
                      onAction: (_) {},
                      onWriteUs: () {})),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/qr-preview')..createSync(recursive: true);
      File('${dir.path}/help.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}
