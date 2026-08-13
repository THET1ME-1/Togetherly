import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/mascot_frame.dart';

void main() {
  group('mascotOnScreen', () {
    const screen = 800.0;

    test('персонаж в середине экрана играет', () {
      expect(mascotOnScreen(top: 300, bottom: 396, screenHeight: screen),
          isTrue);
    });

    test('уехавший далеко вниз замирает', () {
      // В галерее список строится целиком: без этой проверки тикали бы все
      // тридцать персонажей разом, включая тех, кого не видно.
      expect(mascotOnScreen(top: 1600, bottom: 1696, screenHeight: screen),
          isFalse);
    });

    test('уехавший далеко вверх замирает', () {
      expect(mascotOnScreen(top: -900, bottom: -804, screenHeight: screen),
          isFalse);
    });

    test('на подходе к краю уже играет', () {
      // Запас в пол-экрана: персонаж выезжает уже живым, а не оживает рывком.
      expect(mascotOnScreen(top: 900, bottom: 996, screenHeight: screen),
          isTrue);
    });

    test('без высоты экрана считаем видимым', () {
      // Странная среда (тест, нулевой размер) — лучше играть, чем замереть
      // навсегда.
      expect(mascotOnScreen(top: 0, bottom: 96, screenHeight: 0), isTrue);
    });
  });
}
