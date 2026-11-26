import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/coloring_figures.dart';
import 'package:love_app/models/coloring_picture.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/coloring/coloring_figures_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Лист «Кто на рисунке» — на глаз. В общий прогон не входит:
/// `flutter test test/goldens/coloring_figures_preview.dart`, снимки в
/// `build/coloring-figures/`.
Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  var any = false;
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) continue;
    loader.addFont(Future.value(file.readAsBytesSync().buffer.asByteData()));
    any = true;
  }
  if (any) await loader.load();
}

void main() {
  testWidgets('кто на рисунке', (tester) async {
    await _loadFont('Onest', ['assets/fonts/Onest.ttf']);
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() => LocaleService.instance.setLanguage(AppLanguage.ru));

    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<void> shot(String name, Brightness light, {bool locked = false}) async {
      await tester.binding.setSurfaceSize(const Size(360, 760));
      final key = GlobalKey();
      final theme = buildAppTheme(kPalettes[0], light);
      final scheme = ProfileTheme.themeFor(theme).colorScheme;
      await tester.pumpWidget(MaterialApp(
        // Свой ключ на снимок: иначе навигатор прежнего снимка с открытым
        // листом переживёт пересборку, и второй снимок повторит первый.
        key: ValueKey(name),
        debugShowCheckedModeBanner: false,
        theme: ProfileTheme.data(scheme).copyWith(
          textTheme: ProfileTheme.data(scheme).textTheme.apply(fontFamily: 'Onest'),
        ),
        // Лист рисуется поверх экрана, в слое навигатора: снимаем всё
        // приложение, а не только экран под ним.
        builder: (context, child) => RepaintBoundary(key: key, child: child),
        home: RepaintBoundary(
          child: Builder(
            builder: (context) => Scaffold(
              backgroundColor: scheme.surface,
              body: Center(
                child: TextButton(
                  onPressed: () => showColoringFiguresSheet(
                    context,
                    theme: theme,
                    picture: ColoringPicture.byId('snowman')!,
                    initial: const ColoringFigures(
                        left: ColoringFigure.girl, right: ColoringFigure.girl),
                    mySide: ColoringSide.left,
                    rightLocked: locked,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // Картинки ассетов декодируются по-настоящему, вне поддельного времени.
      await tester.runAsync(() async {
        for (final element in find.byType(Image).evaluate()) {
          final image = element.widget as Image;
          await precacheImage(image.image, element);
        }
      });
      await tester.pumpAndSettle();
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      });
      Directory('build/coloring-figures').createSync(recursive: true);
      File('build/coloring-figures/$name.png').writeAsBytesSync(bytes!);
    }

    await shot('light', Brightness.light);
    await shot('dark_locked', Brightness.dark, locked: true);
  });
}
