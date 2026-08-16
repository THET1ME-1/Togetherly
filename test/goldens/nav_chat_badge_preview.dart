import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/screens/home/home_bottom_nav.dart';
import 'package:love_app/theme/app_theme.dart';

/// Снимок навбара со значком чата — посмотреть глазами, а не гадать по коду.
///
/// Имя БЕЗ `_test`: обычный прогон файл не подхватывает. Запуск:
/// `flutter test test/goldens/nav_chat_badge_preview.dart`,
/// картинки лягут в `build/nav-preview/`.
void main() {
  for (final sample in [
    ('pink', AppThemes.pink),
    ('sunset', AppThemes.byIndex(10)),
    ('dark', AppThemes.byIndex(20)),
  ]) {
    testWidgets('навбар — ${sample.$1}', (tester) async {
      tester.view.physicalSize = const Size(1170, 420);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final theme = sample.$2;
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: RepaintBoundary(
            key: key,
            child: Scaffold(
              backgroundColor: theme.cardSurface,
              body: Align(
                alignment: Alignment.bottomCenter,
                child: HomeBottomNav(
                  selectedIndex: 0,
                  theme: theme,
                  isPaired: true,
                  onTap: (_) {},
                  onCreatePin: () {},
                  sideIsArrow: true,
                  onChat: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('build/nav-preview')..createSync(recursive: true);
        File('${dir.path}/${sample.$1}.png')
            .writeAsBytesSync(data!.buffer.asUint8List());
      });
    });
  }
}
