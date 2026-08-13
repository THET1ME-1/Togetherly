import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/stroke_layer_cache.dart';

ui.Picture _picture() {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawPaint(ui.Paint());
  return recorder.endRecording();
}

void main() {
  const size = ui.Size(360, 640);

  test('пустой кэш слоя не отдаёт', () {
    expect(StrokeLayerCache().pictureFor(0, size), isNull);
  });

  test('те же штрихи на том же холсте берутся из кэша', () {
    final cache = StrokeLayerCache()..save(_picture(), 12, size);
    expect(cache.pictureFor(12, size), isNotNull);
  });

  test('новый штрих сбрасывает слой', () {
    final cache = StrokeLayerCache()..save(_picture(), 12, size);
    expect(cache.pictureFor(13, size), isNull);
  });

  test('отмена штриха тоже сбрасывает слой', () {
    final cache = StrokeLayerCache()..save(_picture(), 12, size);
    expect(cache.pictureFor(11, size), isNull);
  });

  test('поворот холста сбрасывает слой', () {
    final cache = StrokeLayerCache()..save(_picture(), 12, size);
    expect(cache.pictureFor(12, const ui.Size(640, 360)), isNull);
  });

  test('после invalidate слой не отдаётся', () {
    final cache = StrokeLayerCache()..save(_picture(), 12, size);
    cache.invalidate();
    expect(cache.pictureFor(12, size), isNull);
  });
}
