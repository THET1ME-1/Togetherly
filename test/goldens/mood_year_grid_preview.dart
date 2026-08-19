import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/widgets/mood/mood_year_sheet.dart';

/// Год настроений клетками — на глаз, на настоящем годе отметок.
///
/// Имя без `_test`: файл для просмотра, а не сторож. Запуск:
/// `flutter test test/goldens/mood_year_grid_preview.dart`,
/// картинки в `build/mood-year/`.
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
  });

  testWidgets('год клетками', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // Похоже на живой год: сериями по несколько дней, с пропусками и провалом
    // в ноябре — иначе не видно, работают ли скругления серий.
    final rnd = Random(7);
    final scores = <DateTime, int>{};
    var day = DateTime(2026);
    var mood = 4;
    while (day.year == 2026 && day.isBefore(DateTime(2026, 12, 20))) {
      final skip = rnd.nextDouble() < (day.month == 11 ? 0.55 : 0.12);
      if (!skip) {
        if (rnd.nextDouble() < 0.35) {
          mood = (mood + (rnd.nextBool() ? 1 : -1)).clamp(1, 5);
        }
        scores[day] = day.month == 11 ? max(1, mood - 2) : mood;
      }
      day = DateTime(day.year, day.month, day.day + 1);
    }

    final key = GlobalKey();
    for (final (name, palette, brightness) in [
      ('light', kPalettes[0], Brightness.light),
    ]) {
      final theme = buildAppTheme(palette, brightness);
      final cs = theme.scheme!;
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Material(
            color: cs.surface,
            child: RepaintBoundary(
              key: key,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: MoodYearGridView(
                    year: 2026,
                    scores: scores,
                    scheme: cs,
                    today: DateTime(2026, 12, 20),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/mood-year')..createSync(recursive: true);
      File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      // ignore: avoid_print
      print('снимок: build/mood-year/$name.png');
    }
  });
}
