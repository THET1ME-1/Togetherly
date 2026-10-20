import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/draw_stroke.dart';
import 'package:love_app/models/stroke_brush.dart';
import 'package:love_app/widgets/draw/stroke_painting.dart';

/// Пять кистей холста по пикселям: каждая обязана выглядеть так, как
/// обещает её подпись в панели.
const _size = Size(100, 100);
const _red = 0xFFFF0000;
const _line = [DrawPoint(0.1, 0.5), DrawPoint(0.9, 0.5)];

Future<ByteData> _render(void Function(Canvas canvas) draw) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 100, 100), Paint()..color = const Color(0xFFFFFFFF));
  draw(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(100, 100);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return bytes!;
}

/// Зелёный канал: на белом листе красная краска его гасит, поэтому чем он
/// меньше, тем гуще краска.
int _g(ByteData data, int x, int y) => data.getUint8((y * 100 + x) * 4 + 1);

/// Сколько точек столбца [x] закрашено гуще половины.
int _denseRows(ByteData data, int x) {
  var n = 0;
  for (var y = 0; y < 100; y++) {
    if (_g(data, x, y) < 128) n++;
  }
  return n;
}

int _painted(ByteData data) {
  var n = 0;
  for (var i = 0; i < 100 * 100; i++) {
    if (data.getUint8(i * 4 + 1) < 200) n++;
  }
  return n;
}

Future<ByteData> _brush(List<DrawPoint> points, StrokeBrush brush, {double width = 10, int seed = 7}) =>
    _render((c) => paintStroke(c, points, _red, width, false, _size, brush: brush, seed: seed));

void main() {
  test('маркер полупрозрачный, сам себя не темнит, чужой мазок темнит', () async {
    final single = await _brush(_line, StrokeBrush.marker);
    expect(_g(single, 50, 50), inInclusiveRange(100, 160), reason: 'половина краски');

    // Мазок туда и обратно по той же полосе: внутри одного мазка темнее не
    // становится, как у настоящего маркера.
    final twice = await _brush(
      const [DrawPoint(0.1, 0.5), DrawPoint(0.9, 0.5), DrawPoint(0.1, 0.51)],
      StrokeBrush.marker,
    );
    expect(_g(twice, 50, 50), inInclusiveRange(100, 160));

    final crossed = await _render((c) {
      paintStroke(c, _line, _red, 10, false, _size, brush: StrokeBrush.marker);
      paintStroke(c, const [DrawPoint(0.5, 0.1), DrawPoint(0.5, 0.9)], _red, 10, false, _size,
          brush: StrokeBrush.marker);
    });
    expect(_g(crossed, 50, 50), lessThan(90), reason: 'наложение двух мазков темнее');
  });

  test('маркер шире пера той же толщины', () async {
    final pen = await _brush(_line, StrokeBrush.pen);
    final marker = await _brush(_line, StrokeBrush.marker);
    var markerRows = 0;
    for (var y = 0; y < 100; y++) {
      if (_g(marker, 50, y) < 200) markerRows++;
    }
    expect(markerRows, greaterThan(_denseRows(pen, 50)));
  });

  test('карандаш тоньше пера и с зерном, одинаковым при том же мазке', () async {
    final pen = await _brush(_line, StrokeBrush.pen);
    final pencil = await _brush(_line, StrokeBrush.pencil, seed: 42);
    expect(_denseRows(pencil, 50), lessThan(_denseRows(pen, 50) - 3));
    expect(_g(pencil, 50, 50), lessThan(200), reason: 'сердцевина видна');

    final again = await _brush(_line, StrokeBrush.pencil, seed: 42);
    expect(again.buffer.asUint8List(), pencil.buffer.asUint8List(), reason: 'зерно не мигает');
    final other = await _brush(_line, StrokeBrush.pencil, seed: 43);
    expect(other.buffer.asUint8List(), isNot(pencil.buffer.asUint8List()));
  });

  test('аэрограф без края: краска тает за пределами толщины', () async {
    final pen = await _brush(_line, StrokeBrush.pen);
    final air = await _brush(_line, StrokeBrush.airbrush);
    // Перо толщиной 10 кончается на пяти точках от середины.
    expect(_g(pen, 50, 58), 255);
    expect(_g(air, 50, 58), inInclusiveRange(120, 252), reason: 'напыление за краем');
    expect(_g(air, 50, 50), greaterThan(40), reason: 'середина не сплошная');
  });

  test('каллиграфия: поперёк пера толсто, вдоль пера тонко', () async {
    // Перо держат под −45°: мазок вниз-вправо идёт поперёк насадки.
    final across = await _brush(const [DrawPoint(0.2, 0.2), DrawPoint(0.8, 0.8)], StrokeBrush.calligraphy,
        width: 12);
    final along = await _brush(const [DrawPoint(0.2, 0.8), DrawPoint(0.8, 0.2)], StrokeBrush.calligraphy,
        width: 12);
    expect(_painted(along), greaterThan(0), reason: 'вдоль пера линия не пропадает');
    expect(_painted(across), greaterThan(_painted(along) * 3));
  });

  test('мягкий ластик оставляет размытый край, твёрдый — ровный', () async {
    Future<ByteData> erase(StrokeBrush brush) => _render((c) {
          c.saveLayer(const Rect.fromLTWH(0, 0, 100, 100), Paint());
          c.drawRect(const Rect.fromLTWH(0, 0, 100, 100), Paint()..color = const Color(0xFF0000FF));
          paintStroke(c, _line, _red, 10, true, _size, brush: brush);
          c.restore();
        });
    int r(ByteData d, int y) => d.getUint8((y * 100 + 50) * 4);

    final hard = await erase(StrokeBrush.pen);
    final soft = await erase(StrokeBrush.airbrush);
    expect(r(hard, 50), 255, reason: 'посередине стёрто до белого');
    expect(r(hard, 57), 0, reason: 'за краем синий нетронут');
    expect(r(soft, 50), greaterThan(150));
    expect(r(soft, 57), inInclusiveRange(10, 240), reason: 'край стёрт наполовину');
  });

  test('список штрихов рисуется кистью самого штриха', () async {
    const stroke = DrawStroke(
      id: 's',
      clientId: 'c',
      userId: 'u',
      colorValue: _red,
      strokeWidth: 10,
      points: _line,
      orderIndex: 0,
      brush: StrokeBrush.pencil,
    );
    final viaList = await _render((c) => paintStrokeRange(c, const [stroke], _size));
    final direct = await _brush(_line, StrokeBrush.pencil, seed: stroke.brushSeed);
    expect(viaList.buffer.asUint8List(), direct.buffer.asUint8List());
  });

  test('точка любой кистью видна', () async {
    for (final brush in StrokeBrush.values) {
      final dot = await _brush(const [DrawPoint(0.5, 0.5), DrawPoint(0.5, 0.5)], brush);
      expect(_painted(dot), greaterThan(0), reason: brush.name);
    }
  });
}
