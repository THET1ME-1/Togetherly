import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/draw_stroke.dart';
import 'package:love_app/widgets/draw/stroke_painting.dart';

const _size = Size(100, 100);

/// Рисует по белому листу и отдаёт пиксели.
Future<ByteData> _render(void Function(Canvas canvas) draw) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 100, 100),
    Paint()..color = const Color(0xFFFFFFFF),
  );
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
  return Color.fromARGB(
    data.getUint8(i + 3),
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
  );
}

void main() {
  const red = 0xFFFF0000;

  test('кисть кладёт линию поперёк листа', () async {
    final data = await _render((c) => paintStroke(
          c,
          const [DrawPoint(0.1, 0.5), DrawPoint(0.9, 0.5)],
          red,
          6,
          false,
          _size,
        ));
    expect(_at(data, 50, 50), const Color(red));
    expect(_at(data, 50, 10), const Color(0xFFFFFFFF));
  });

  test('ластик снимает нарисованное, а не красит поверх', () async {
    // Слой нужен, чтобы стирание не выело фон холста: сетку и узор рисуют
    // ниже, они в этот слой не входят.
    final data = await _render((c) {
      c.saveLayer(const Rect.fromLTWH(0, 0, 100, 100), Paint());
      paintStroke(
        c,
        const [DrawPoint(0.1, 0.5), DrawPoint(0.9, 0.5)],
        0xFF0000FF,
        10,
        false,
        _size,
      );
      paintStroke(
        c,
        const [DrawPoint(0.4, 0.5), DrawPoint(0.6, 0.5)],
        0xFF00FF00,
        10,
        true,
        _size,
      );
      c.restore();
    });
    // Там, где прошёл ластик, остался белый лист, а не зелёная полоса.
    expect(_at(data, 50, 50), const Color(0xFFFFFFFF));
    // Слева линия цела.
    expect(_at(data, 15, 50), const Color(0xFF0000FF));
  });

  test('прямоугольник рисуется рамкой, а не заливкой', () async {
    final data = await _render((c) => paintShape(
          c,
          const [DrawPoint(0.2, 0.2), DrawPoint(0.8, 0.8)],
          red,
          4,
          DrawShapeType.rect,
          _size,
          isFilledShape: false,
        ));
    expect(_at(data, 50, 20), const Color(red));
    expect(_at(data, 50, 50), const Color(0xFFFFFFFF));
  });

  test('залитая фигура закрашена внутри', () async {
    final data = await _render((c) => paintShape(
          c,
          const [DrawPoint(0.2, 0.2), DrawPoint(0.8, 0.8)],
          red,
          4,
          DrawShapeType.circle,
          _size,
          isFilledShape: true,
        ));
    expect(_at(data, 50, 50), const Color(red));
  });

  test('пиксельный штрих закрашивает клетку целиком', () async {
    final data = await _render((c) => paintStroke(
          c,
          const [DrawPoint(0.5, 0.5)],
          red,
          1,
          false,
          _size,
          pixelCols: 10,
          pixelRows: 10,
        ));
    expect(_at(data, 51, 51), const Color(red));
    expect(_at(data, 58, 58), const Color(red));
    expect(_at(data, 65, 65), const Color(0xFFFFFFFF));
  });

  test('круг на пиксельном холсте рисуется клетками, а не гладкой кривой',
      () async {
    // Холст 10×10 клеток на 100 точках — клетка ровно 10 точек.
    const cols = 10, rows = 10;
    final data = await _render((canvas) {
      paintShape(
        canvas,
        const [DrawPoint(0.1, 0.1), DrawPoint(0.85, 0.85)],
        red,
        4,
        DrawShapeType.circle,
        _size,
        isFilledShape: false,
        pixelCols: cols,
        pixelRows: rows,
      );
    });

    // Внутри клетки цвет постоянный: у гладкой кривой край размывается
    // полупрозрачными точками, у клетки — нет.
    var painted = 0;
    for (var cy = 0; cy < rows; cy++) {
      for (var cx = 0; cx < cols; cx++) {
        final corner = _at(data, cx * 10 + 2, cy * 10 + 2);
        final middle = _at(data, cx * 10 + 7, cy * 10 + 7);
        expect(middle, corner,
            reason: 'клетка $cx,$cy закрашена неровно — это сглаживание');
        if (corner.r > 0.9 && corner.g < 0.1) painted++;
      }
    }
    expect(painted, greaterThan(8), reason: 'круг не нарисовался');
    expect(painted, lessThan(cols * rows),
        reason: 'контур закрасил весь холст');
  });

  test('залитый прямоугольник на пиксельном холсте закрывает ровно клетки',
      () async {
    final data = await _render((canvas) {
      paintShape(
        canvas,
        const [DrawPoint(0.25, 0.25), DrawPoint(0.55, 0.55)],
        red,
        4,
        DrawShapeType.rect,
        _size,
        isFilledShape: true,
        pixelCols: 10,
        pixelRows: 10,
      );
    });
    // Клетки со 2-й по 5-ю включительно закрашены, соседние — нет.
    expect(_at(data, 25, 25).r, greaterThan(0.9));
    expect(_at(data, 55, 55).r, greaterThan(0.9));
    expect(_at(data, 15, 25), const Color(0xFFFFFFFF));
    expect(_at(data, 65, 55), const Color(0xFFFFFFFF));
  });

  test('толщина на пиксельном холсте задаёт кисть в клетках', () async {
    // Холст 10×10 клеток на 100 точках. Тонкая кисть — одна клетка,
    // толстая — квадрат: раньше ползунок толщины тут не делал ничего.
    Future<int> paintedCells(double width) async {
      final data = await _render((canvas) {
        paintStroke(
          canvas,
          const [DrawPoint(0.45, 0.45)],
          red,
          width,
          false,
          _size,
          pixelCols: 10,
          pixelRows: 10,
        );
      });
      var n = 0;
      for (var cy = 0; cy < 10; cy++) {
        for (var cx = 0; cx < 10; cx++) {
          final c = _at(data, cx * 10 + 5, cy * 10 + 5);
          if (c.r > 0.9 && c.g < 0.1) n++;
        }
      }
      return n;
    }

    expect(await paintedCells(2), 1, reason: 'тонкая кисть шире клетки');
    expect(await paintedCells(20), 9, reason: 'кисть 3×3 не получилась');
    expect(await paintedCells(40), 25, reason: 'кисть 5×5 не получилась');
  });
}
