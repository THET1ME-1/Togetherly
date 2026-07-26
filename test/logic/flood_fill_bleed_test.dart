// Заливка залезает под контур. Линии рисуются со сглаживанием: у них есть
// полупрозрачная кромка, и заливка «до цвета» до неё не доходит — вдоль каждой
// линии оставался светлый ободок, который в раскраске виден как дырки.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/flood_fill.dart';

/// Белый квадрат с чёрной рамкой в один пиксель по краю.
Future<ui.Image> _framed(int size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    Paint()..color = const Color(0xFF000000),
  );
  canvas.drawRect(
    Rect.fromLTWH(1, 1, size - 2.0, size - 2.0),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  picture.dispose();
  return image;
}

Future<int> _filledPixels(ui.Image image, int color) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final pixels = data!.buffer.asUint32List();
  var count = 0;
  for (final p in pixels) {
    if ((p >> 24) != 0) count++;
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('без расширения заливка не трогает рамку', () async {
    final source = await _framed(20);
    final filled = await FloodFill.fill(
      source: source,
      startX: 10,
      startY: 10,
      fillColor: 0xFFFF0000,
      bleed: 0,
    );
    source.dispose();

    expect(filled, isNotNull);
    // Внутренность 18×18 = 324 пикселя, рамка остаётся нетронутой.
    expect(await _filledPixels(filled!, 0xFFFF0000), 324);
    filled.dispose();
  });

  test('расширение добавляет пиксели по краю области', () async {
    final source = await _framed(20);
    final filled = await FloodFill.fill(
      source: source,
      startX: 10,
      startY: 10,
      fillColor: 0xFFFF0000,
      bleed: 1,
    );
    source.dispose();

    expect(filled, isNotNull);
    // Один шаг захватывает рамку, кроме четырёх угловых пикселей: расширение
    // четырёхсвязное, как и сама заливка — по диагонали краска просачивалась бы
    // сквозь тонкие наклонные линии. 20×20 − 4 = 396.
    expect(await _filledPixels(filled!, 0xFFFF0000), 396);
    filled.dispose();
  });

  test('расширение не вылезает за пределы холста', () async {
    final source = await _framed(12);
    final filled = await FloodFill.fill(
      source: source,
      startX: 6,
      startY: 6,
      fillColor: 0xFF00FF00,
      bleed: 5,
    );
    source.dispose();

    expect(filled, isNotNull);
    expect(await _filledPixels(filled!, 0xFF00FF00), 144); // 12×12, не больше
    filled.dispose();
  });
}
