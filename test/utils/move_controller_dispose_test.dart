import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/anim_dispose.dart';

/// Второй `dispose()` у одного контроллера — падение, а не мелочь.
///
/// На живой карте пары его звали дважды: сперва «показать обоих» гасил анимацию
/// перелёта, а потом экран закрывался и гасил её же — ссылка на контроллер в
/// поле оставалась. В отладке об этом сказал бы assert, в релизе внутри
/// `AnimationController.dispose` остаётся `_ticker!`, и приложение падает с
/// «Null check operator used on a null value». 60 событий за день на
/// 1.24.0+166: `_showBoth`, `_centerOnMe`, `dispose` экрана.
void main() {
  test('повторный dispose контроллера действительно падает', () {
    final ctrl = AnimationController(
      vsync: const TestVSync(),
      duration: const Duration(milliseconds: 10),
    );
    ctrl.dispose();
    expect(ctrl.dispose, throwsA(anything));
  });

  test('disposeAnim гасит контроллер и отдаёт null', () {
    final ctrl = AnimationController(
      vsync: const TestVSync(),
      duration: const Duration(milliseconds: 10),
    );
    expect(disposeAnim(ctrl), isNull);
  });

  test('disposeAnim по уже погашенному полю молчит', () {
    final ctrl = AnimationController(
      vsync: const TestVSync(),
      duration: const Duration(milliseconds: 10),
    );
    final gone = disposeAnim(ctrl);
    expect(() => disposeAnim(gone), returnsNormally);
  });
}
