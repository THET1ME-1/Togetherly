import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/reels_source.dart';
import 'package:love_app/widgets/reels/reels_start_sheet.dart';

/// Лист выбора площадки «Лент вдвоём»: на 320 точках и шрифте 1.3 ничего не
/// вылезает, работает только Shorts, остальные помечены «скоро».
/// Картинка для глаз: REELS_PREVIEW=1 → build/reels/start-sheet.png.
void main() {
  for (final w in [320.0, 393.0]) {
    testWidgets('лист выбора на $w точках', (tester) async {
      tester.view.physicalSize = Size(w * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      ReelsSource? picked;
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            theme: ThemeData(colorSchemeSeed: const Color(0xFFFF7E9B), useMaterial3: true),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
              child: Builder(
                builder: (ctx) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () async => picked = await showReelsStartSheet(ctx),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('TikTok'), findsOneWidget);
      // «Скоро» нажать нельзя — выбор остаётся на Shorts.
      await tester.tap(find.text('TikTok'));
      await tester.pumpAndSettle();
      if (Platform.environment['REELS_PREVIEW'] == '1') {
        await tester.runAsync(() async {
          final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          Directory('build/reels').createSync(recursive: true);
          File('build/reels/start-sheet-${w.toInt()}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(picked, ReelsSource.shorts);
    });
  }
}
