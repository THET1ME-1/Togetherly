import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/utils/readable_text.dart';

/// Белый текст на заливке: что будет, если притемнить цвет темы.
///
/// Слева — как сейчас (светлая заливка, чернила выбираются по контрасту, у
/// 17 палитр из 25 они чёрные). Справа — заливка, опущенная до тона 47, где
/// белый читается всегда. Оттенок и насыщенность не трогаем: тянем только
/// светлоту, чтобы персик остался персиком.
///
/// Имя без `_test`: файл для глаз. Запуск:
/// `flutter test test/goldens/fill_ink_preview.dart`.
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

/// Опускает светлоту до [tone], сохраняя оттенок и насыщенность.
Color darkened(Color c, double tone) {
  final h = Hct.fromInt(c.toARGB32());
  return Color(Hct.from(h.hue, h.chroma, tone).toInt());
}

void main() {
  setUpAll(() async {
    await _loadFont('Onest', ['assets/fonts/Onest.ttf']);
    await _loadFont('Unbounded', ['assets/fonts/Unbounded.ttf']);
  });

  testWidgets('заливка и цвет текста', (tester) async {
    tester.view.physicalSize = const Size(1300, 2700);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    final light = [
      for (final p in kPalettes)
        if (buildAppTheme(p, Brightness.light).brightness == Brightness.light)
          p,
    ];

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: key,
          child: Container(
            color: const Color(0xFFF7F3F2),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('СЕЙЧАС',
                            style: TextStyle(
                                fontFamily: 'Onest',
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                      ),
                      Expanded(
                        child: Text('ЗАЛИВКА ТЕМНЕЕ, ТЕКСТ БЕЛЫЙ',
                            style: TextStyle(
                                fontFamily: 'Onest',
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
                for (final p in light.take(20))
                  _PaletteRow(palette: p),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.6);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/qr-preview')..createSync(recursive: true);
      File('${dir.path}/fill-ink.png')
          .writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}

class _PaletteRow extends StatelessWidget {
  const _PaletteRow({required this.palette});

  final Palette palette;

  @override
  Widget build(BuildContext context) {
    final t = buildAppTheme(palette, Brightness.light);
    final now = t.fillColor;
    final deep = darkened(now, 47);

    Widget chip(Color fill, Color ink, String note) => Expanded(
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    palette.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: 'Unbounded',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: ink),
                  ),
                ),
                Text(note,
                    style: TextStyle(
                        fontFamily: 'Onest',
                        fontSize: 11,
                        color: ink.withValues(alpha: 0.8))),
              ],
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          chip(now, AppThemes.onColor(now),
              contrastRatio(AppThemes.onColor(now), now).toStringAsFixed(1)),
          chip(deep, Colors.white,
              contrastRatio(Colors.white, deep).toStringAsFixed(1)),
        ],
      ),
    );
  }
}
