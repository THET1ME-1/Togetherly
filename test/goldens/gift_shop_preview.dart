import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/screens/gifts/gift_shop_screen.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/theme/profile_theme.dart';

/// Снимок магазина подарков для глаз: `flutter test test/goldens/gift_shop_preview.dart`
/// → build/gift-shop/*.png. Имя без `_test`: обычный прогон его не берёт.
void main() {
  for (final (w, scale) in [(393.0, 1.0), (320.0, 1.3)]) {
    testWidgets('магазин $w x$scale', (tester) async {
      tester.view.physicalSize = Size(w * 2, 1400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final theme = AppThemes.byIndex(6);
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
          theme: ProfileTheme.data(ProfileTheme.schemeFor(theme)),
          home: MediaQuery(
            data: MediaQueryData(size: Size(w, 700), textScaler: TextScaler.linear(scale)),
            child: GiftShopScreen(theme: theme, groupId: 'g', coins: 25),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await b.toImage(pixelRatio: 2);
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        Directory('build/gift-shop').createSync(recursive: true);
        File('build/gift-shop/shop_${w.toInt()}_$scale.png').writeAsBytesSync(data!.buffer.asUint8List());
      });
    });
  }
}
