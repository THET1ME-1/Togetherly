// Слой готовых штрихов: ревизия основы плюс длина префикса.
//
// Ключом кэша было ЧИСЛО штрихов, и отсюда шли две беды. Удалили один штрих и
// добавили другой — число совпало, и на экране оставалась прежняя картинка.
// А любое добавление меняло число и пересобирало слой из всех прошлых штрихов,
// поэтому в пиксельной раскраске (штрих — это клетка, их десятки в секунду)
// работа росла квадратично: тот самый «холст дёргается».
//
// Теперь слой знает, какой ПРЕФИКС состава он содержит. Пока штрихи только
// дописываются в конец, картинка не трогается вовсе, а свежие рисуются поверх.
// Всё, что ломает префикс (отмена, замена, пересортировка, смена фона), двигает
// ревизию основы, и слой честно пересобирается.
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/stroke_layer_cache.dart';

ui.Picture _picture() {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawPaint(ui.Paint());
  return recorder.endRecording();
}

void main() {
  const size = ui.Size(300, 400);

  test('слой отдаётся, пока основа та же', () {
    final cache = StrokeLayerCache();
    final picture = _picture();
    cache.save(picture, revision: 7, size: size, prefixCount: 40);
    expect(cache.prefixFor(revision: 7, available: 40, size: size),
        same(picture));
    expect(cache.prefixCount, 40);
  });

  test('дописали штрихи в конец — слой годится, хвост рисуется поверх', () {
    final cache = StrokeLayerCache();
    final picture = _picture();
    cache.save(picture, revision: 7, size: size, prefixCount: 100);
    expect(cache.prefixFor(revision: 7, available: 130, size: size),
        same(picture),
        reason: 'ради этого случая всё и затевалось: рисование не пересобирает слой');
  });

  test('штрихов стало меньше — слой не годится', () {
    final cache = StrokeLayerCache();
    cache.save(_picture(), revision: 7, size: size, prefixCount: 100);
    expect(cache.prefixFor(revision: 7, available: 90, size: size), isNull,
        reason: 'отменили штрих: часть картинки уже неверна');
  });

  test('ревизия основы сменилась — слой не годится', () {
    final cache = StrokeLayerCache();
    cache.save(_picture(), revision: 7, size: size, prefixCount: 100);
    expect(cache.prefixFor(revision: 8, available: 130, size: size), isNull,
        reason: 'состав поменялся не дописыванием в конец');
  });

  test('другой размер холста — слой не годится', () {
    final cache = StrokeLayerCache();
    cache.save(_picture(), revision: 7, size: size, prefixCount: 10);
    expect(
        cache.prefixFor(
            revision: 7, available: 10, size: const ui.Size(200, 200)),
        isNull);
  });

  test('сброс убирает слой', () {
    final cache = StrokeLayerCache();
    cache.save(_picture(), revision: 7, size: size, prefixCount: 10);
    cache.invalidate();
    expect(cache.prefixFor(revision: 7, available: 10, size: size), isNull);
    expect(cache.prefixCount, 0);
  });

  test('пустой кэш ничего не отдаёт', () {
    expect(
        StrokeLayerCache().prefixFor(revision: 0, available: 0, size: size),
        isNull);
  });

  test('повторное сохранение той же картинки её не разрушает', () {
    final cache = StrokeLayerCache();
    final picture = _picture();
    cache.save(picture, revision: 1, size: size, prefixCount: 3);
    cache.save(picture, revision: 2, size: size, prefixCount: 5);
    expect(cache.prefixFor(revision: 2, available: 5, size: size),
        same(picture),
        reason: 'иначе слой освободили бы и тут же отдали освобождённым');
  });
}
