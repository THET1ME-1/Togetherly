import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/shake_detector.dart';

/// Облачко пугается, когда телефон встряхнули. Встряска — несколько резких
/// рывков подряд за короткое время; шаг, поездка в транспорте или телефон,
/// положенный на стол, встряской не считаются.
void main() {
  ShakeDetector make() => ShakeDetector();
  Duration ms(int v) => Duration(milliseconds: v);

  test('три резких рывка за полсекунды — встряска', () {
    final d = make();
    expect(d.add(ms(0), 0, 0, 30), isFalse);
    expect(d.add(ms(150), 0, 28, 0), isFalse);
    expect(d.add(ms(300), 31, 0, 0), isTrue);
  });

  test('один удар (положили на стол) — не встряска', () {
    final d = make();
    expect(d.add(ms(0), 0, 0, 40), isFalse);
    for (var t = 50; t < 1500; t += 50) {
      expect(d.add(ms(t), 0, 0, 0.3), isFalse);
    }
  });

  test('ходьба: слабые толчки — не встряска', () {
    final d = make();
    for (var t = 0; t < 3000; t += 100) {
      expect(d.add(ms(t), 2, 5, 3), isFalse);
    }
  });

  test('рывки растянуты на две секунды — не встряска', () {
    final d = make();
    expect(d.add(ms(0), 30, 0, 0), isFalse);
    expect(d.add(ms(900), 30, 0, 0), isFalse);
    expect(d.add(ms(1800), 30, 0, 0), isFalse);
  });

  test('после встряски пауза: тряска продолжается, а облачко пугается один раз', () {
    final d = make();
    d.add(ms(0), 30, 0, 0);
    d.add(ms(100), 30, 0, 0);
    expect(d.add(ms(200), 30, 0, 0), isTrue);
    expect(d.add(ms(300), 30, 0, 0), isFalse);
    expect(d.add(ms(400), 30, 0, 0), isFalse);
    expect(d.add(ms(500), 30, 0, 0), isFalse);
    // Через паузу снова можно.
    d.add(ms(4000), 30, 0, 0);
    d.add(ms(4100), 30, 0, 0);
    expect(d.add(ms(4200), 30, 0, 0), isTrue);
  });
}
