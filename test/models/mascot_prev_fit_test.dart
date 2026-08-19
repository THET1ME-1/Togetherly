import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/contain_rect.dart';

/// Прежний рисунок маскота обязан лечь в снимок так же, как лежал на экране.
///
/// Редактор показывает его `BoxFit.contain`, а сохранение растягивало на весь
/// квадрат холста: неквадратный набросок получал другие пропорции, и поверх
/// нового рисунка оставалась его раздутая, сдвинутая копия — жирные чёрные
/// мазки там, где на холсте тонкая линия. Жалоба 18.08.2026 звучала так:
/// «на холсте выглядит норм, как захожу поменять маскота — он аномально
/// чёрный, но на самом холсте этого не видно».
void main() {
  group('containRect', () {
    test('широкую картинку прижимает по ширине и центрирует по высоте', () {
      final r = containRect(
        source: const Size(400, 200),
        target: const Size(300, 300),
      );
      expect(r.width, 300);
      expect(r.height, 150);
      expect(r.left, 0);
      expect(r.top, 75);
    });

    test('высокую — по высоте', () {
      final r = containRect(
        source: const Size(200, 400),
        target: const Size(300, 300),
      );
      expect(r.height, 300);
      expect(r.width, 150);
      expect(r.top, 0);
      expect(r.left, 75);
    });

    test('квадрат ложится целиком — прежнее поведение не меняется', () {
      final r = containRect(
        source: const Size(700, 700),
        target: const Size(300, 300),
      );
      expect(r, const Rect.fromLTWH(0, 0, 300, 300));
    });

    test('пустая картинка не даёт ни NaN, ни бесконечности', () {
      final r = containRect(
        source: const Size(0, 0),
        target: const Size(300, 300),
      );
      expect(r, const Rect.fromLTWH(0, 0, 300, 300));
    });
  });

  test('редактор маскота вписывает набросок, а не растягивает', () {
    final source =
        File('lib/screens/mascot_draw_screen.dart').readAsStringSync();
    final draws = RegExp(r'drawImageRect\(\s*\n\s*_prevDrawingImage!,(.*?)\);',
            dotAll: true)
        .allMatches(source);
    expect(draws.length, 2,
        reason: 'набросок композитится в двух местах: заливка и сохранение');
    for (final m in draws) {
      expect(m.group(1), contains('containRect('),
          reason: 'оба места кладут набросок по пропорциям');
    }
  });
}
