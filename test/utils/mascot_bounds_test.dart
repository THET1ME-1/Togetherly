import 'dart:io';
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

    // TOG-15, обращение 411: маскот уехал под нижнюю панель, и оттуда его не
    // взять — касание забирает панель.
    test('не уходит под нижнюю панель', () {
      expect(
        clampMascotPosition(const Offset(200, 790), screen, half,
                top: 24, bottom: 110)
            .dy,
        screen.height - 110 - half,
      );
    });

    test('не уходит под строку состояния', () {
      expect(
        clampMascotPosition(const Offset(200, 10), screen, half,
                top: 24, bottom: 110)
            .dy,
        24 + half,
      );
    });

    test('между полями не помещается — позиция остаётся прежней', () {
      const p = Offset(200, 300);
      expect(clampMascotPosition(p, screen, half, top: 400, bottom: 300), p);
    });
  });

  test('маскот на главной считает нижнюю панель и строку состояния', () {
    final src = File('lib/widgets/active_mascot_widget.dart').readAsStringSync();
    final start = src.indexOf('void _clampPosition()');
    final body = src.substring(start, src.indexOf('\n  }\n', start));
    expect(body, contains('kHomeBottomNavHeight'));
    expect(body, contains('viewPadding'));
  });

  group('mascotGestureIsTap', () {
    test('короткое касание почти без движения — тап', () {
      expect(
        mascotGestureIsTap(
          travel: 4,
          held: const Duration(milliseconds: 120),
        ),
        isTrue,
      );
    });

    test('палец уехал — это перетаскивание', () {
      expect(
        mascotGestureIsTap(
          travel: 40,
          held: const Duration(milliseconds: 120),
        ),
        isFalse,
      );
    });

    test('долгое удержание на месте тапом не считается', () {
      expect(
        mascotGestureIsTap(
          travel: 2,
          held: const Duration(seconds: 1),
        ),
        isFalse,
      );
    });

    test('дрожание руки на пороге ещё тап', () {
      expect(
        mascotGestureIsTap(
          travel: 12,
          held: const Duration(milliseconds: 200),
        ),
        isTrue,
      );
    });
  });
}
