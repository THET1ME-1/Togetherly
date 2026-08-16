import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/coloring_clamp.dart';

/// Прижатие мазка к своей половине листа не должно ронять приложение.
///
/// Отзыв 16.08.2026: «часто вылетает в раскрасках». В панели крашей это
/// `ArgumentError: Invalid argument(s): 0.0` из `_clampToMySide` →
/// `double.clamp`, приходящий прямо из `_onPointerMove` — то есть падение
/// случается посреди движения пальца.
///
/// Причина: границы считались как `half - margin` и `half + margin`, где
/// `margin` зависит от толщины кисти. Толстая кисть на узком листе (или лист,
/// который ещё не измерен, шириной ноль) переворачивает диапазон, а `clamp`
/// на перевёрнутом диапазоне бросает исключение.
void main() {
  group('обычный лист', () {
    test('точка на своей половине остаётся на месте', () {
      expect(coloringClampX(100, width: 1000, strokeWidth: 10, left: true), 100);
      expect(coloringClampX(900, width: 1000, strokeWidth: 10, left: false), 900);
    });

    test('точка на чужой половине прижимается к своему краю', () {
      final x = coloringClampX(900, width: 1000, strokeWidth: 10, left: true);
      expect(x, lessThan(500), reason: 'левый не должен заходить за середину');
      expect(x, greaterThan(400), reason: 'и прижимается вплотную, а не в угол');

      final y = coloringClampX(100, width: 1000, strokeWidth: 10, left: false);
      expect(y, greaterThan(500));
    });
  });

  group('случаи, на которых падало', () {
    test('лист ещё не измерен — ширина ноль', () {
      expect(coloringClampX(0, width: 0, strokeWidth: 12, left: true), 0);
      expect(coloringClampX(5, width: 0, strokeWidth: 12, left: false), 5);
    });

    test('кисть толще половины листа', () {
      // Половина 50, отступ 101 — прежние границы давали clamp(0, -51).
      final x = coloringClampX(80, width: 100, strokeWidth: 200, left: true);
      expect(x, inInclusiveRange(0, 50));
      final y = coloringClampX(20, width: 100, strokeWidth: 200, left: false);
      expect(y, inInclusiveRange(50, 100));
    });

    test('кисть ровно в половину листа', () {
      expect(
        () => coloringClampX(10, width: 100, strokeWidth: 98, left: true),
        returnsNormally,
      );
    });

    test('отрицательная и запредельная точка не ломают правило', () {
      expect(coloringClampX(-40, width: 1000, strokeWidth: 10, left: true), 0);
      expect(coloringClampX(5000, width: 1000, strokeWidth: 10, left: false), 1000);
    });
  });
}
