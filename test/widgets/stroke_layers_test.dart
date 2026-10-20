import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/draw_stroke.dart';
import 'package:love_app/widgets/draw/stroke_painting.dart';

/// Слои рисуются каждый отдельно.
///
/// Жалоба 20.10.2026: «криво работают слои». Холст складывал все слои в одно
/// полотно, и ластик на верхнем слое стирал рисунок нижних, а линия нижнего
/// слоя, пока её ведёшь, лежала поверх всего и прыгала вниз при отпускании.
const _size = Size(100, 100);
const _red = 0xFFFF0000;
const _blue = 0xFF0000FF;
const _white = Color(0xFFFFFFFF);

DrawStroke _line(String id, int color, int layer, int order, {bool eraser = false, double y = 0.5}) =>
    DrawStroke(
      id: id,
      userId: 'u',
      colorValue: color,
      strokeWidth: 10,
      points: [DrawPoint(0.1, y), DrawPoint(0.9, y)],
      isEraser: eraser,
      orderIndex: order,
      layer: layer,
    );

Future<ByteData> _render(void Function(Canvas canvas) draw) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Offset.zero & _size, Paint()..color = _white);
  draw(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(100, 100);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return bytes!;
}

Color _at(ByteData data, int x, int y) {
  final i = (y * 100 + x) * 4;
  return Color.fromARGB(data.getUint8(i + 3), data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
}

/// Считает отдельные буферы слоёв, остальное пропускает.
class _LayerCounter implements Canvas {
  int layers = 0;

  @override
  void saveLayer(Rect? bounds, Paint paint) => layers++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  test('буфер заводится только у слоя с ластиком', () {
    // Буфер на весь холст стоит кадра; слой без ластика рисуется прямо на
    // холст с тем же результатом.
    final plain = _LayerCounter();
    paintLayers(plain, [_line('a', _red, 0, 0), _line('b', _blue, 1, 1)], _size);
    expect(plain.layers, 0);

    final erased = _LayerCounter();
    paintLayers(erased, [_line('a', _red, 0, 0), _line('e', 0xFF000000, 1, 1, eraser: true)], _size);
    expect(erased.layers, 1);

    final liveEraser = _LayerCounter();
    paintLayers(
      liveEraser,
      [_line('a', _red, 0, 0), _line('b', _blue, 1, 1)],
      _size,
      liveLayers: const [0],
      eraserLayers: const [0],
      live: (_, __) {},
    );
    expect(liveEraser.layers, 1, reason: 'живой ластик тоже требует буфер своего слоя');
  });

  test('ластик на верхнем слое не стирает нижний', () async {
    final strokes = [
      _line('red', _red, 0, 0),
      _line('blue', _blue, 1, 1, y: 0.2),
      _line('eraser', 0xFF000000, 1, 2, eraser: true),
    ];
    final data = await _render((c) => paintLayers(c, strokes, _size));
    expect(_at(data, 50, 50), const Color(_red), reason: 'нижний слой цел');
  });

  test('ластик на своём слое стирает свой рисунок', () async {
    final strokes = [
      _line('red', _red, 0, 0),
      _line('eraser', 0xFF000000, 0, 1, eraser: true),
    ];
    final data = await _render((c) => paintLayers(c, strokes, _size));
    expect(_at(data, 50, 50), _white);
  });

  test('линия нижнего слоя, пока её ведут, лежит под верхним', () async {
    final strokes = [_line('blue', _blue, 1, 0)];
    final data = await _render((c) => paintLayers(
          c,
          strokes,
          _size,
          liveLayers: const [0],
          live: (canvas, layer) {
            if (layer == 0) paintStroke(canvas, const [DrawPoint(0.5, 0.1), DrawPoint(0.5, 0.9)], _red, 10, false, _size);
          },
        ));
    expect(_at(data, 50, 50), const Color(_blue), reason: 'верхний слой поверх живой линии нижнего');
    expect(_at(data, 50, 20), const Color(_red), reason: 'живая линия видна там, где сверху пусто');
  });
}
