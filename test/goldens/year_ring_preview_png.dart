// Картинки «Кольца года» для списка виджетов лончера (previewImage).
//
// Рисует тот же YearRingCard, что превью в каталоге приложения, поэтому
// картинка в диалоге установки совпадает с виджетом. Имя без _test: обычный
// прогон тестов её не трогает, запускается руками после правки раскладки:
//
//   flutter test test/goldens/year_ring_preview_png.dart
//
// Остальные превью по-прежнему рисует tools/gen_widget_previews.py.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/year_ring_card.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader('Onest')
      ..addFont(
        File('assets/fonts/Onest.ttf').readAsBytes().then(ByteData.sublistView),
      );
    await loader.load();
  });

  // Палитра остальных превью (tools/gen_widget_previews.py): фиолетовая M3.
  const colors = YearRingColors(
    primary: Color(0xFF6750A4),
    onPrimary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFFFD8E4),
  );
  const texts = YearRingTexts(
    daysCaption: 'Дней вместе',
    untilAnniversary: 'До годовщины',
    daysLeftUnit: 'дней',
    anniversaryLine: 'Годовщина 30 сентября',
    monthsShort: 'мес.',
    memoriesUnit: 'воспоминаний',
    smallLine: 'Ещё 355 дней',
  );

  const smallTexts = YearRingTexts(
    daysCaption: 'Дней',
    untilAnniversary: 'До годовщины',
    daysLeftUnit: 'дней',
    anniversaryLine: 'Годовщина 30 сентября',
    monthsShort: 'мес.',
    memoriesUnit: 'воспоминаний',
    smallLine: 'Ещё 355 дней',
  );

  for (final (small, name, width, height) in [
    (false, 'tg_preview_ring_4x2', 848.0, 400.0),
    (true, 'tg_preview_ring_2x2', 400.0, 400.0),
  ]) {
    testWidgets(name, (tester) async {
      tester.view.physicalSize = Size(width, height);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: width,
                height: height,
                child: Center(
                  child: YearRingCard(
                    small: small,
                    colors: colors,
                    texts: small ? smallTexts : texts,
                    daysTotal: 2126,
                    daysLeft: 355,
                    months: 69,
                    memories: 412,
                    progress: 10 / 365,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final bytes = await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      });
      File(
        'android/app/src/main/res/drawable-nodpi/$name.png',
      ).writeAsBytesSync(bytes!);
    });
  }
}
