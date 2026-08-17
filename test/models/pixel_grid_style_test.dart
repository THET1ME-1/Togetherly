// Сетка обязана появляться и на плотных решётках.
//
// Жалоба (17.08.2026): «не работает рисунок по клеткам формата 64×80, клетки не
// появляются». Кнопка сетки переключалась, подпись «64 × 80 · клетка 25 px»
// стояла на месте, а линий не было.
//
// Причина: рисовальщик молча выходил, когда клетка меньше шести логических
// пикселей. На iPhone холст 64×80 даёт клетку около 4,4 dp — порог отсекал
// именно те форматы, где сетка нужнее всего.
//
// Совсем без порога нельзя: при клетке меньше двух точек линии сливаются в
// серое полотно. Поэтому порог ниже, а тонкие клетки рисуются волосяной линией
// послабее.
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/pixel_grid_style.dart';

void main() {
  test('крупная клетка — обычная линия', () {
    final style = pixelGridStyle(20);
    expect(style.visible, isTrue);
    expect(style.strokeWidth, 1);
    expect(style.opacity, closeTo(0.08, 0.001));
  });

  test('64×80 на телефоне: клетка 4,4 — сетка есть', () {
    final style = pixelGridStyle(4.4);
    expect(style.visible, isTrue, reason: 'ровно тот случай из жалобы');
    expect(style.strokeWidth, lessThan(1));
  });

  test('у самой границы порога всё ещё рисуем', () {
    expect(pixelGridStyle(2.5).visible, isTrue);
  });

  test('слишком мелкая клетка — молчим, иначе серое полотно', () {
    expect(pixelGridStyle(2.4).visible, isFalse);
    expect(pixelGridStyle(0.5).visible, isFalse);
  });

  test('мелкая клетка рисуется слабее крупной', () {
    expect(pixelGridStyle(4).opacity, lessThan(pixelGridStyle(20).opacity));
  });

  test('нулевая и отрицательная клетка не роняют расчёт', () {
    expect(pixelGridStyle(0).visible, isFalse);
    expect(pixelGridStyle(-3).visible, isFalse);
  });
}
