import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/anim_dispose.dart';

/// Повторное гашение контроллера в релизе доходит до `_ticker!` внутри Flutter
/// и роняет экран. Карта пары падала так десятками раз в день: «показать обоих»
/// гасило перелёт, а закрытие экрана гасило тот же контроллер второй раз.
void main() {
  test('гасит контроллер и отдаёт пустое поле', () {
    final ctrl = AnimationController(
      duration: const Duration(milliseconds: 10),
      vsync: const TestVSync(),
    );
    expect(disposeAnim(ctrl), isNull);
  });

  test('второе гашение того же контроллера ничего не роняет', () {
    final ctrl = AnimationController(
      duration: const Duration(milliseconds: 10),
      vsync: const TestVSync(),
    );
    disposeAnim(ctrl);
    expect(() => disposeAnim(ctrl), returnsNormally);
  });

  test('пустое поле принимается молча', () {
    expect(disposeAnim(null), isNull);
  });
}
