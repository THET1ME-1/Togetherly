import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/mood/mood_canvas.dart';

/// Цвет пикселя PNG в точке (x, y).
Future<Color> _pixel(Uint8List png, int x, int y) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final i = (y * frame.image.width + x) * 4;
  final b = data!.buffer.asUint8List();
  return Color.fromARGB(b[i + 3], b[i], b[i + 1], b[i + 2]);
}

void main() {
  testWidgets('рисунок уходит картинкой 512 на белом, как его видно на холсте', (tester) async {
    await tester.runAsync(() async {
      final png = await renderStrokesPng([
        MoodStroke(
          points: const [Offset(0.1, 0.5), Offset(0.9, 0.5)],
          color: const Color(0xFFFA282F),
          width: 0.05,
        ),
      ]);
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 512);
      expect(frame.image.height, 512);
      // Середина линии — красная, угол — белый: фон не прозрачный, иначе в
      // тёмной теме рисунок встал бы чёрным квадратом.
      expect(await _pixel(png, 256, 256), const Color(0xFFFA282F));
      expect(await _pixel(png, 5, 5), const Color(0xFFFFFFFF));
    });
  });

  testWidgets('ластик стирает до белого', (tester) async {
    await tester.runAsync(() async {
      final png = await renderStrokesPng([
        MoodStroke(points: const [Offset(0.1, 0.5), Offset(0.9, 0.5)], color: const Color(0xFF1F2430), width: 0.05),
        MoodStroke(points: const [Offset(0.4, 0.5), Offset(0.6, 0.5)], color: const Color(0xFF1F2430), width: 0.1, eraser: true),
      ]);
      expect(await _pixel(png, 256, 256), const Color(0xFFFFFFFF));
      expect(await _pixel(png, 100, 256), const Color(0xFF1F2430));
    });
  });

  testWidgets('точка от касания без движения тоже рисуется', (tester) async {
    await tester.runAsync(() async {
      final png = await renderStrokesPng([
        MoodStroke(points: const [Offset(0.5, 0.5)], color: const Color(0xFF5FBF7F), width: 0.06),
      ]);
      expect(await _pixel(png, 256, 256), const Color(0xFF5FBF7F));
    });
  });
}
