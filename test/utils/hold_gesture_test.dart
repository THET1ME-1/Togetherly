import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/canvas_gestures.dart';

void main() {
  group('удержание пальца на холсте', () {
    test('палец постоял на месте — это пипетка', () {
      expect(
        holdIsEyedropper(
          held: const Duration(milliseconds: 600),
          travel: 3,
        ),
        isTrue,
      );
    });

    test('короткое касание остаётся точкой', () {
      expect(
        holdIsEyedropper(held: const Duration(milliseconds: 200), travel: 1),
        isFalse,
      );
    });

    test('палец повело — человек рисует', () {
      expect(
        holdIsEyedropper(held: const Duration(milliseconds: 900), travel: 30),
        isFalse,
      );
    });
  });
}
