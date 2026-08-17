// Штрих не может уйти за край холста.
//
// Жалоба тестера (17.08.2026): «рисовать можно картину и выходить за контур
// холста». Так и было: `DrawPoint.fromOffset` только делит координаты на размер
// холста, поэтому палец за краем давал доли меньше нуля и больше единицы. Лист
// обрезает картинку по своей рамке, а холст внутри листа при уменьшении меньше
// него — вот в этом зазоре и рисовалось.
//
// Обрезать надо на вводе, а не при отрисовке: точки в таком виде уходят
// партнёру и в хранилище, и рисунок с ними уже не починить.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/draw_stroke.dart';

void main() {
  const canvas = Size(200, 100);

  test('точка внутри холста остаётся как есть', () {
    final p = DrawPoint.clampedFromOffset(const Offset(50, 25), canvas);
    expect(p.x, closeTo(0.25, 1e-9));
    expect(p.y, closeTo(0.25, 1e-9));
  });

  test('палец за левым верхним углом упирается в ноль', () {
    final p = DrawPoint.clampedFromOffset(const Offset(-40, -10), canvas);
    expect(p.x, 0);
    expect(p.y, 0);
  });

  test('палец за правым нижним углом упирается в единицу', () {
    final p = DrawPoint.clampedFromOffset(const Offset(500, 400), canvas);
    expect(p.x, 1);
    expect(p.y, 1);
  });

  test('края холста остаются краями', () {
    final p = DrawPoint.clampedFromOffset(const Offset(200, 100), canvas);
    expect(p.x, 1);
    expect(p.y, 1);
  });

  test('нулевой холст не даёт NaN', () {
    final p = DrawPoint.clampedFromOffset(const Offset(10, 10), Size.zero);
    expect(p.x, 0);
    expect(p.y, 0);
  });

  test('чтение чужих точек не обрезается: старые рисунки не переедут', () {
    // Разбор пришедшего от партнёра штриха оставляем как есть — иначе рисунок,
    // сделанный до этой правки, у одного участника поедет, а у второго нет.
    final p = DrawPoint.fromMap({'x': -0.5, 'y': 1.5});
    expect(p.x, -0.5);
    expect(p.y, 1.5);
  });
}
