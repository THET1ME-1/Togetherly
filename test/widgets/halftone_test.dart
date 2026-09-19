// Растр на главной кнопке листа «Добавить воспоминание» (19.09.2026).
//
// Выбран заказчиком из шести узоров макета «Узор кнопки»: точки растут слева
// направо, как полиграфический растр. Левая треть чистая — там подпись.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/common/halftone_painter.dart';

void main() {
  const size = Size(328, 104);

  test('левая треть чистая: под подписью точек нет', () {
    final dots = halftoneDots(size, dark: false);
    expect(dots, isNotEmpty);
    expect(dots.every((d) => d.center.dx > size.width * 0.34), isTrue);
  });

  test('точки растут слева направо и не крупнее 3,3', () {
    final dots = halftoneDots(size, dark: false);
    final row = dots.where((d) => d.center.dy == dots.first.center.dy).toList()
      ..sort((a, b) => a.center.dx.compareTo(b.center.dx));
    for (var i = 1; i < row.length; i++) {
      expect(row[i].radius, greaterThanOrEqualTo(row[i - 1].radius));
    }
    expect(dots.map((d) => d.radius).reduce((a, b) => a > b ? a : b),
        closeTo(3.3, 0.001));
  });

  test('ряды сдвинуты через один, шаг 11', () {
    final ys = halftoneDots(size, dark: false).map((d) => d.center.dy).toSet()
      .toList()
      ..sort();
    expect(ys.first, 5);
    expect(ys[1] - ys[0], 11);
    final first = halftoneDots(size, dark: false)
        .where((d) => d.center.dy == ys[0])
        .map((d) => d.center.dx % 11)
        .toSet();
    final second = halftoneDots(size, dark: false)
        .where((d) => d.center.dy == ys[1])
        .map((d) => d.center.dx % 11)
        .toSet();
    expect(first.single, isNot(second.single));
  });

  test('в тёмной теме тише: подпись там тёмная и сильнее по контрасту', () {
    final light = halftoneDots(size, dark: false).last.alpha;
    final dark = halftoneDots(size, dark: true).last.alpha;
    expect(light, closeTo(0.22, 0.001));
    expect(dark, closeTo(0.143, 0.001));
  });

  test('узкая кнопка не ломает расчёт', () {
    expect(halftoneDots(const Size(0, 104), dark: false), isEmpty);
    expect(halftoneDots(const Size(200, 104), dark: false), isNotEmpty);
  });

  testWidgets('painter перерисовывается только при смене цвета или темы',
      (tester) async {
    const a = HalftonePainter(color: Colors.white, dark: false);
    expect(a.shouldRepaint(const HalftonePainter(color: Colors.white, dark: false)),
        isFalse);
    expect(a.shouldRepaint(const HalftonePainter(color: Colors.black, dark: false)),
        isTrue);
    expect(a.shouldRepaint(const HalftonePainter(color: Colors.white, dark: true)),
        isTrue);
  });
}
