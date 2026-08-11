import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';

/// Баннер «Создать открытку» на настоящем фоне светлой темы — тремя заливками.
///
/// Имя без `_test`: файл для глаз, а не сторож. Запуск:
/// `flutter test test/goldens/postcard_banner_preview.dart`, картинка в
/// `build/qr-preview/`.
void main() {
  testWidgets('чем красить баннер', (tester) async {
    tester.view.physicalSize = const Size(1200, 1500);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    // Вишнёвая светлая — на ней и заметили пропажу фона.
    final t = buildAppTheme(kPalettes[7], Brightness.light);
    final cs = t.scheme!;

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: key,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: t.bgGradient,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Label('Было: primaryContainer', cs),
                  _Banner(cs: cs, fill: cs.primaryContainer, ink: cs.onPrimaryContainer),
                  const SizedBox(height: 22),
                  _Label('secondaryContainer', cs),
                  _Banner(
                    cs: cs,
                    fill: cs.secondaryContainer,
                    ink: cs.onSecondaryContainer,
                  ),
                  const SizedBox(height: 22),
                  _Label('Стало: заливка темы', cs),
                  _Banner(
                    cs: cs,
                    fill: t.fillColor,
                    ink: AppThemes.onColor(t.fillColor),
                  ),
                  const SizedBox(height: 22),
                  _Label('surfaceContainerHigh — как карточки', cs),
                  _Banner(
                    cs: cs,
                    fill: cs.surfaceContainerHigh,
                    ink: cs.onSurface,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/qr-preview')..createSync(recursive: true);
      File('${dir.path}/postcard-banner.png')
          .writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}

class _Label extends StatelessWidget {
  const _Label(this.text, this.cs);

  final String text;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 6, bottom: 8),
        child: Text(
          text,
          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
        ),
      );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.cs, required this.fill, required this.ink});

  final ColorScheme cs;
  final Color fill;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: ink.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Center(child: Icon(Icons.mail_rounded, color: ink, size: 26)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Создать открытку',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800, color: ink),
                ),
                const SizedBox(height: 4),
                Text(
                  'Соберите открытку и отправьте партнёру',
                  style: TextStyle(
                      fontSize: 12.5, color: ink.withValues(alpha: 0.82)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
            child: Icon(Icons.arrow_forward_ios_rounded, color: fill, size: 15),
          ),
        ],
      ),
    );
  }
}
