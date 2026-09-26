// Картинки листа «монеты или реклама» в магазине подарков:
// flutter test test/goldens/gift_pay_sheet_preview.dart → build/gift-pay/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/screens/gifts/gift_shop_screen.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
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

  for (final (name, palette, b, width, scale, coins) in [
    ('pink-light-393', 0, Brightness.light, 393.0, 1.0, 120),
    ('pink-dark-393', 0, Brightness.dark, 393.0, 1.0, 120),
    ('mono-light-320-1.3-nocoins', 11, Brightness.light, 320.0, 1.3, 0),
    ('mint-dark-320-1.3', 12, Brightness.dark, 320.0, 1.3, 120),
  ]) {
    testWidgets(name, (tester) async {
      final theme = buildAppTheme(kPalettes[palette], b);
      final cs = ProfileTheme.themeFor(theme).colorScheme;
      const h = 760.0;
      tester.view.physicalSize = Size(width * 3, h * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ProfileTheme.data(cs),
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: GiftShopScreen(theme: theme, groupId: 'g', coins: coins, onCoins: (_) {}),
        ),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
      await tester.pump();
      await tester.tap(find.text('Сердце').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.runAsync(() async {
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await boundary.toImage(pixelRatio: 2);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        Directory('build/gift-pay').createSync(recursive: true);
        File('build/gift-pay/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
      expect(tester.takeException(), isNull);
    });
  }
}
