import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/gift.dart';
import 'package:love_app/screens/chest_screen.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/chest/chest_home_card.dart';
import 'package:love_app/widgets/chest/chest_prize_image.dart';

/// Сундук недели на живой теме «Кофе» (как на макете): блок на главной и экран
/// сундука, на ширине 393 и 320 точек.
///
/// Имя без `_test`: файл для глаз. Запуск:
/// `flutter test test/goldens/chest_preview.dart`, картинка в
/// `build/qr-preview/chest.png`.
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

  testWidgets('сундук недели', (tester) async {
    tester.view.physicalSize = const Size(3000, 3000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    final t = buildAppTheme(kPalettes.firstWhere((p) => p.name == 'Кофе'), Brightness.light);
    final cs = t.scheme!;

    Widget phone(double w, double h, Widget child) => Container(
      width: w,
      height: h,
      margin: const EdgeInsets.all(12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(28)),
      child: child,
    );
    Widget ph(String text) => Container(
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(text, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
    );
    Widget home(double w) => phone(
      w,
      460,
      Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            ph('[таймер пары]'),
            const SizedBox(height: 8),
            ChestHomeCard(theme: t, groupId: 'g'),
            const SizedBox(height: 8),
            ph('[остальное на главной]'),
          ],
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ProfileTheme.data(cs),
        home: RepaintBoundary(
          key: key,
          child: ColoredBox(
            color: const Color(0xFF171210),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(children: [home(393), home(320)]),
                phone(393, 1400, ChestScreen(theme: t, groupId: 'g')),
                phone(320, 1400, ChestScreen(theme: t, groupId: 'g')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      final ctx = key.currentContext!;
      await precacheImage(const AssetImage(kChestStill), ctx);
      for (final g in [...GiftCatalog.chest.map((g) => g.key), 'chest_plus']) {
        await precacheImage(AssetImage('assets/images/gifts/$g.webp'), ctx);
      }
      await precacheImage(const AssetImage('assets/images/icons/coin.webp'), ctx);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump(const Duration(milliseconds: 500));

    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/qr-preview')..createSync(recursive: true);
      File('${dir.path}/chest.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}
