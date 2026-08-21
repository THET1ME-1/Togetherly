import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/canvas_meta.dart';
import 'package:love_app/models/draw_stroke.dart';
import 'package:love_app/widgets/draw/canvas_preview.dart';

/// Плитка холста в галерее пустовала, пока человек не зайдёт внутрь: превью
/// снималось только на выходе с экрана рисования. Здесь проверяется рисование
/// плитки прямо из штрихов — то, чем эта пустота закрывается.

const _size = Size(60, 60);

Future<ui.Image> _render(CustomPainter painter) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Offset.zero & _size, Paint()..color = const Color(0xFFFFFFFF));
  painter.paint(canvas, _size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(60, 60);
  picture.dispose();
  return image;
}

Future<int> _paintedPixels(CustomPainter painter) async {
  final image = await _render(painter);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  var painted = 0;
  for (var i = 0; i < data!.lengthInBytes; i += 4) {
    final r = data.getUint8(i), g = data.getUint8(i + 1), b = data.getUint8(i + 2);
    if (r != 255 || g != 255 || b != 255) painted++;
  }
  return painted;
}

DrawStroke _stroke(List<DrawPoint> points, {int color = 0xFFFF0000}) => DrawStroke(
      id: 'stroke-${points.length}-$color',
      userId: 'u1',
      points: points,
      colorValue: color,
      strokeWidth: 6,
      orderIndex: 0,
    );

void main() {
  final meta = CanvasMeta(
    id: 'c1',
    name: 'Холст',
    createdAt: _epoch,
    updatedAt: _epoch,
  );

  test('штрихи рисуются: плитка перестаёт быть пустой', () async {
    final painted = await _paintedPixels(CanvasPreviewPainter(
      strokes: [
        _stroke(const [DrawPoint(0.1, 0.5), DrawPoint(0.9, 0.5)]),
      ],
      meta: meta,
    ));
    expect(painted, greaterThan(50), reason: 'линия не нарисовалась');
  });

  test('пустой холст остаётся пустым, заглушку рисует галерея', () async {
    final painted = await _paintedPixels(
      CanvasPreviewPainter(strokes: const [], meta: meta),
    );
    expect(painted, 0);
  });

  test('пиксельный холст рисуется клетками', () async {
    final pixelMeta = CanvasMeta(
      id: 'c2',
      name: 'Пиксельные',
      createdAt: _epoch,
      updatedAt: _epoch,
      pixelW: 6,
      pixelH: 6,
    );
    final image = await _render(CanvasPreviewPainter(
      strokes: [
        _stroke(const [DrawPoint(0.25, 0.25)]),
      ],
      meta: pixelMeta,
    ));
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    Color at(int x, int y) {
      final i = (y * 60 + x) * 4;
      return Color.fromARGB(255, data!.getUint8(i), data.getUint8(i + 1),
          data.getUint8(i + 2));
    }

    // Клетка 10×10 точек: середина и угол одной клетки красятся одинаково.
    expect(at(11, 11), at(18, 18), reason: 'клетка закрашена неровно');
    expect(at(11, 11).r, greaterThan(0.9), reason: 'клетка не закрашена');
    expect(at(35, 35), const Color(0xFFFFFFFF), reason: 'закрасилось лишнее');
  });

  test('тяжёлый холст не рисуется целиком: плитка размером в ноготь', () async {
    final many = List.generate(
      5000,
      (i) => _stroke([
        DrawPoint(i / 5000, 0.2),
        DrawPoint(i / 5000, 0.8),
      ]),
    );
    final painter = CanvasPreviewPainter(strokes: many, meta: meta);
    expect(painter.visibleStrokes.length, lessThanOrEqualTo(kPreviewStrokeLimit));
  });
}

final _epoch = DateTime.fromMillisecondsSinceEpoch(0);
