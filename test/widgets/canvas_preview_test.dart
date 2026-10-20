import 'dart:io';
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

  test('плитка без снимка грузит заливки, сжатые под свой размер', () {
    final source = File('lib/widgets/draw/canvas_preview.dart').readAsStringSync();
    expect(source, contains('imageOf: _images.imageFor'));
    // В 1600 точек двадцать плиток с заливками заняли бы сотни мегабайт.
    expect(source, contains('CanvasImageCache(decodeSide: '));
  });

  test('заливка ведром видна на плитке', () async {
    // Жалоба владельца 20.10.2026: плитка без снимка стояла пустой, потому
    // что заливка хранится картинкой, а плитка рисовала только линии. В
    // раскраске почти всё — заливки.
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 10, 10),
      Paint()..color = const Color(0xFFFFC107),
    );
    final picture = recorder.endRecording();
    final fill = await picture.toImage(10, 10);
    picture.dispose();

    const stroke = DrawStroke(
      id: 'fill',
      userId: 'u1',
      points: [],
      colorValue: 0xFF000000,
      strokeWidth: 0,
      orderIndex: 0,
      imageUrl: 'pb://media/x/fill.png',
      imageX: 0.5,
      imageY: 0.5,
      imageWidth: 1,
      imageHeight: 1,
    );
    final image = await _render(CanvasPreviewPainter(
      strokes: const [stroke],
      meta: meta,
      imageOf: (s) => s.id == 'fill' ? fill : null,
    ));
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    fill.dispose();
    final i = (30 * 60 + 30) * 4;
    expect(
      Color.fromARGB(255, data!.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2)),
      const Color(0xFFFFC107),
    );
  });

  test('толщина линии на плитке — в той же доле листа, что на холсте', () async {
    // Эмулятор 20.10.2026: плитка считала холст шириной в 1000 точек, а на
    // телефоне он около 400. Линия выходила в 2,5 раза тоньше дырки, которую
    // оставляет в заливке, и вокруг неё белел ободок.
    const tile = Size(200, 250);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(Offset.zero & tile, Paint()..color = const Color(0xFFFFFFFF));
    CanvasPreviewPainter(
      strokes: [
        DrawStroke(
          id: 'line',
          userId: 'u1',
          points: const [DrawPoint(0.1, 0.5), DrawPoint(0.9, 0.5)],
          colorValue: 0xFF0000FF,
          strokeWidth: 10,
          orderIndex: 0,
        ),
      ],
      meta: meta,
    ).paint(canvas, tile);
    final picture = recorder.endRecording();
    final image = await picture.toImage(200, 250);
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    var thick = 0;
    for (var y = 0; y < 250; y++) {
      final i = (y * 200 + 100) * 4;
      if (data!.getUint8(i + 2) > 200 && data.getUint8(i) < 120) thick++;
    }
    // Холст на телефоне около 400 точек в ширину: 10 из 400 на плитке в 200 —
    // это пять пикселей.
    expect(thick, inInclusiveRange(4, 6));
  });

  test('плитка другой формы не сдвигает заливку относительно линий', () async {
    // Эмулятор 20.10.2026: лист 4:5, плитка почти квадратная. Линии плитка
    // растягивала под себя, а заливку обрезала по краям — дырки в заливке
    // съезжали с линий, и рядом белело пустое место.
    final sheet = CanvasMeta(
      id: 'c2',
      name: 'Лист',
      createdAt: _epoch,
      updatedAt: _epoch,
      sheetRatio: 0.8,
    );
    // Заливка 40×50 (тоже 4:5) с синей полосой ровно на четверти высоты.
    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder);
    c.drawRect(const Rect.fromLTWH(0, 0, 40, 50), Paint()..color = const Color(0xFFFFC107));
    c.drawRect(const Rect.fromLTWH(0, 12, 40, 1), Paint()..color = const Color(0xFF0000FF));
    final pic = recorder.endRecording();
    final fill = await pic.toImage(40, 50);
    pic.dispose();

    const tile = Size(60, 50);
    final out = ui.PictureRecorder();
    final canvas = Canvas(out);
    canvas.drawRect(Offset.zero & tile, Paint()..color = const Color(0xFFFFFFFF));
    CanvasPreviewPainter(
      strokes: const [
        DrawStroke(
          id: 'fill',
          userId: 'u1',
          points: [],
          colorValue: 0xFF000000,
          strokeWidth: 0,
          orderIndex: 0,
          imageUrl: 'pb://media/x/fill.png',
          imageX: 0.5,
          imageY: 0.5,
          imageWidth: 1,
          imageHeight: 1,
        ),
        DrawStroke(
          id: 'line',
          userId: 'u1',
          points: [DrawPoint(0.6, 0.25), DrawPoint(0.9, 0.25)],
          colorValue: 0xFFFF0000,
          strokeWidth: 20,
          orderIndex: 1,
        ),
      ],
      meta: sheet,
      imageOf: (s) => s.id == 'fill' ? fill : null,
    ).paint(canvas, tile);
    final picture = out.endRecording();
    final image = await picture.toImage(60, 50);
    picture.dispose();
    fill.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();

    double rowsOf(int x, bool Function(int r, int g, int b) match) {
      final rows = <int>[];
      for (var y = 0; y < 50; y++) {
        final i = (y * 60 + x) * 4;
        if (match(data!.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2))) rows.add(y);
      }
      expect(rows, isNotEmpty);
      return rows.reduce((a, b) => a + b) / rows.length;
    }

    final blue = rowsOf(15, (r, g, b) => b > 200 && r < 80 && g < 80);
    final red = rowsOf(45, (r, g, b) => r > 200 && g < 80 && b < 80);
    expect((blue - red).abs(), lessThanOrEqualTo(1.5),
        reason: 'полоса заливки на ${blue.toStringAsFixed(1)}, линия на ${red.toStringAsFixed(1)}');
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
