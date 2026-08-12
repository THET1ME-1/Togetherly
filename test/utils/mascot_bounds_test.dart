import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/mascot_bounds.dart';

/// Маскот падал с «Invalid argument(s): 65.0» на живой сборке: границы
/// прижатия переворачивались, когда экран оказывался у́же двух радиусов — а
/// такое случается в момент, когда виджет смонтирован, но размер ещё не
/// известен и MediaQuery отдаёт нули.
void main() {
  group('clampMascotPosition', () {
    const screen = Size(400, 800);
    const half = 65.0;

    test('внутри экрана позиция не меняется', () {
      expect(clampMascotPosition(const Offset(200, 400), screen, half),
          const Offset(200, 400));
    });

    test('за левым краем прижимается к радиусу', () {
      expect(clampMascotPosition(const Offset(-30, 400), screen, half).dx, half);
    });

    test('за нижним краем прижимается к радиусу', () {
      expect(clampMascotPosition(const Offset(200, 5000), screen, half).dy,
          screen.height - half);
    });

    test('нулевой экран не роняет: позиция остаётся прежней', () {
      const p = Offset(120, 300);
      expect(clampMascotPosition(p, Size.zero, half), p);
    });

    test('экран уже двух радиусов не роняет', () {
      const p = Offset(50, 50);
      expect(clampMascotPosition(p, const Size(100, 800), half), p);
      expect(clampMascotPosition(p, const Size(400, 100), half), p);
    });

    test('нулевой радиус ничего не меняет', () {
      const p = Offset(10, 20);
      expect(clampMascotPosition(p, screen, 0), p);
    });
  });
}
