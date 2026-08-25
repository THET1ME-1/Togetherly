import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/draw_stroke.dart';
import 'package:love_app/widgets/draw/stroke_painting.dart';

/// Заливка ведром — это картинка, а не мазок, и до 25.08.2026 холст рисовал её
/// отдельным виджетом поверх `CustomPaint`. Из-за этого залитое пятно ложилось
/// сверху всего рисунка, что бы ни говорили `orderIndex` и слой: тестер залил
/// квадрат, стал рисовать по нему кистью — линия уходила под пятно, и на любом
/// слое повторялось то же самое.
///
/// Здесь холст проверяется на порядок: кто позже в списке, тот и сверху,
/// независимо от того, картинка это или мазок.

const _size = Size(40, 40);

Future<ui.Image> _solid(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Offset.zero & const Size(8, 8),
    Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(8, 8);
  picture.dispose();
  return image;
}

/// Цвет середины холста после отрисовки списка.
Future<Color> _centerColor(
  List<DrawStroke> strokes,
  ui.Image? Function(DrawStroke) imageOf,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Offset.zero & _size, Paint()..color = const Color(0xFFFFFFFF));
  paintStrokeRange(canvas, strokes, _size, imageOf: imageOf);
  final picture = recorder.endRecording();
  final image = await picture.toImage(40, 40);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  const offset = (20 * 40 + 20) * 4;
  return Color.fromARGB(
    data!.getUint8(offset + 3),
    data.getUint8(offset),
    data.getUint8(offset + 1),
    data.getUint8(offset + 2),
  );
}

DrawStroke _fill(int order) => DrawStroke(
      id: 'fill_$order',
      userId: 'u1',
      colorValue: 0xFF000000,
      strokeWidth: 0,
      points: const [],
      orderIndex: order,
      imageUrl: 'file:///fake.png',
      imageX: 0.5,
      imageY: 0.5,
      imageWidth: 1.0,
      imageHeight: 1.0,
      imageRotation: 0,
    );

DrawStroke _brush(int order) => DrawStroke(
      id: 'brush_$order',
      userId: 'u1',
      colorValue: 0xFFFF0000,
      strokeWidth: 12,
      points: const [DrawPoint(0.1, 0.5), DrawPoint(0.9, 0.5)],
      orderIndex: order,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('мазок поверх заливки виден', () async {
    final black = await _solid(const Color(0xFF000000));
    final color = await _centerColor(
      [_fill(0), _brush(1)],
      (_) => black,
    );
    expect(color.r, greaterThan(0.7), reason: 'кисть должна лежать поверх пятна');
    expect(color.g, lessThan(0.3));
    black.dispose();
  });

  test('заливка поверх мазка закрывает его', () async {
    final black = await _solid(const Color(0xFF000000));
    final color = await _centerColor(
      [_brush(0), _fill(1)],
      (_) => black,
    );
    expect(color.r, lessThan(0.1), reason: 'пятно нарисовано позже — оно сверху');
    black.dispose();
  });

  test('ещё не загруженная картинка не рушит отрисовку', () async {
    final color = await _centerColor([_fill(0), _brush(1)], (_) => null);
    expect(color.r, greaterThan(0.7), reason: 'мазок рисуется и без растра');
  });
}
