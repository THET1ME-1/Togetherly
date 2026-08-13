import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/mascot_frame.dart';

void main() {
  group('nextMascotFrame', () {
    test('кадры идут по кругу', () {
      expect(nextMascotFrame(frame: 0, cols: 4, oneShot: false),
          const MascotFrameStep(frame: 1, looped: false, finished: false));
      expect(nextMascotFrame(frame: 2, cols: 4, oneShot: false),
          const MascotFrameStep(frame: 3, looped: false, finished: false));
    });

    test('последний кадр возвращает на начало и отмечает круг', () {
      // Круг — повод разыграть свою сцену: почистить перья, зевнуть.
      final step = nextMascotFrame(frame: 3, cols: 4, oneShot: false);
      expect(step.frame, 0);
      expect(step.looped, isTrue);
      expect(step.finished, isFalse);
    });

    test('разовое состояние доигрывает и заканчивается', () {
      // «Подрос», «обрадовался», «приземлился» проигрываются один раз.
      final step = nextMascotFrame(frame: 3, cols: 4, oneShot: true);
      expect(step.finished, isTrue);
    });

    test('пустой атлас не роняет счёт', () {
      final step = nextMascotFrame(frame: 0, cols: 0, oneShot: false);
      expect(step.frame, 0);
      expect(step.finished, isFalse);
    });
  });

  group('mascotFrameStep', () {
    test('шаг кадра считается по частоте', () {
      expect(mascotFrameStep(10), const Duration(milliseconds: 100));
      expect(mascotFrameStep(12), const Duration(milliseconds: 83));
    });

    test('нулевая частота даёт десять кадров в секунду', () {
      // Так вело себя прежнее умолчание — менять скорость персонажам нельзя.
      expect(mascotFrameStep(0), const Duration(milliseconds: 100));
      expect(mascotFrameStep(-5), const Duration(milliseconds: 100));
    });
  });
}
