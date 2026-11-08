import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/mood_trend.dart';
import 'package:love_app/widgets/mood/mood_trend_chart.dart';

/// График настроения на глаз: полгода с 63 отмеченными днями, как на снимке
/// владельца 08.11.2026, «было» (точка на день) и «стало».
///
/// Имя без `_test`: файл для просмотра, а не сторож. Запуск:
/// `flutter test test/goldens/mood_trend_preview.dart`, картинки в
/// `build/mood-trend/`.
Future<void> _loadFont(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return;
  final loader = FontLoader(family)..addFont(file.readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

void main() {
  setUpAll(() => _loadFont('Onest', 'assets/fonts/Onest.ttf'));

  testWidgets('график настроения', (tester) async {
    tester.view.physicalSize = const Size(1179, 600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final rnd = Random(3);
    final days = <DateTime, double>{};
    var d = DateTime(2026, 6, 8);
    while (days.length < 63) {
      days[d] = (1 + rnd.nextInt(5)).toDouble();
      d = DateTime(d.year, d.month, d.day + 1 + rnd.nextInt(4));
    }
    final daily = [for (final k in days.keys.toList()..sort()) MoodTrendPoint(k, days[k]!)];

    final key = GlobalKey();
    for (final (name, brightness, points) in [
      ('было', Brightness.light, daily),
      ('стало-светлая', Brightness.light, moodTrendPoints(days)),
      ('стало-тёмная', Brightness.dark, moodTrendPoints(days)),
    ]) {
      final cs = ColorScheme.fromSeed(seedColor: const Color(0xFF8B5E34), brightness: brightness);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: cs.surface,
          body: RepaintBoundary(
            key: key,
            child: Container(
              color: cs.surfaceContainerHigh,
              padding: const EdgeInsets.all(18),
              child: SizedBox(
                height: 128,
                child: MoodTrendChart(points: points, scheme: cs, emptyText: '—'),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 3);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory('build/mood-trend').createSync(recursive: true);
        File('build/mood-trend/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
  });
}
