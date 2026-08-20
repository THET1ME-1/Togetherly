import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/canvas_gestures.dart';

void main() {
  group('тап несколькими пальцами', () {
    MultiTapAction call({
      int fingers = 2,
      int ms = 160,
      double travel = 3,
      bool zoomed = false,
    }) =>
        multiTapAction(
          fingers: fingers,
          held: Duration(milliseconds: ms),
          travel: travel,
          zoomed: zoomed,
        );

    test('два пальца отменяют', () {
      expect(call(), MultiTapAction.undo);
    });

    test('три пальца возвращают', () {
      expect(call(fingers: 3), MultiTapAction.redo);
    });

    test('один палец рисует, а не отменяет', () {
      expect(call(fingers: 1), MultiTapAction.none);
    });

    test('ладонь из четырёх пальцев ничего не делает', () {
      expect(call(fingers: 4), MultiTapAction.none);
    });

    test('положили и держат — это не тап', () {
      expect(call(ms: 900), MultiTapAction.none);
    });

    test('пальцы поехали — это щипок', () {
      expect(call(travel: 40), MultiTapAction.none);
    });

    test('масштаб изменился — работа отменяться не должна', () {
      expect(call(zoomed: true), MultiTapAction.none);
    });
  });
}
