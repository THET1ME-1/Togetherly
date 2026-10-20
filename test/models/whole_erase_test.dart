import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/draw_stroke.dart';
import 'package:love_app/models/whole_erase.dart';

/// Ластик «Линия целиком»: касание убирает задетый мазок полностью, но только
/// своего слоя и только линии и фигуры.
const _canvas = Size(100, 100);

DrawStroke _line(String id, double y, {int layer = 0, bool eraser = false, String? image}) => DrawStroke(
      id: id,
      userId: 'u',
      colorValue: 0xFF000000,
      strokeWidth: 4,
      points: [DrawPoint(0.1, y), DrawPoint(0.9, y)],
      orderIndex: 0,
      layer: layer,
      isEraser: eraser,
      imageUrl: image,
      imageX: image == null ? null : 0.5,
      imageY: image == null ? null : y,
      imageWidth: image == null ? null : 0.8,
      imageHeight: image == null ? null : 0.2,
    );

void main() {
  final strokes = [
    _line('top', 0.2),
    _line('middle', 0.5),
    _line('other-layer', 0.5, layer: 1),
    _line('eraser', 0.5, eraser: true),
    _line('photo', 0.5, image: 'pb://media/x/a.jpg'),
    _line('live_s9', 0.5),
  ];

  test('задетая линия своего слоя уходит, соседние остаются', () {
    final hits = strokesUnderFinger(strokes, const Offset(50, 50), _canvas, layer: 0);
    expect(hits.map((s) => s.id), ['middle']);
  });

  test('палец рядом с линией, но в пределах ластика — линия задета', () {
    final hits = strokesUnderFinger(strokes, const Offset(50, 58), _canvas, layer: 0, reach: 10);
    expect(hits.map((s) => s.id), ['middle']);
    expect(strokesUnderFinger(strokes, const Offset(50, 58), _canvas, layer: 0, reach: 2), isEmpty);
  });

  test('уже стёртые повторно не берутся', () {
    final hits = strokesUnderFinger(strokes, const Offset(50, 50), _canvas, layer: 0, skip: {'middle'});
    expect(hits, isEmpty);
  });

  test('чужой слой, ластики, картинки и мазки в полёте не трогаем', () {
    final hits = strokesUnderFinger(strokes, const Offset(50, 50), _canvas, layer: 1);
    expect(hits.map((s) => s.id), ['other-layer']);
  });

  test('восстановленный свой мазок встаёт на прежнее место в истории', () {
    expect(insertAt(['a', 'c'], 1, 'b2'), ['a', 'b2', 'c']);
    expect(insertAt(['a'], 5, 'z'), ['a', 'z']);
    expect(insertAt(const [], 0, 'z'), ['z']);
  });
}
