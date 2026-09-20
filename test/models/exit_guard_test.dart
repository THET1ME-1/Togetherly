import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/exit_guard.dart';

/// Выход из комнаты совместного просмотра по двойному «назад».
///
/// Просьба пары: «случайно нажимаешь и тебя выбрасывает с комнаты». Кино при
/// этом останавливается у обоих, и вернуться — значит заново искать место.
void main() {
  final t0 = DateTime(2026, 9, 20, 22, 0, 0);

  test('первое нажатие не выпускает, а предупреждает', () {
    expect(exitOnBack(lastPress: null, now: t0), isFalse);
  });

  test('второе нажатие подряд выпускает', () {
    expect(exitOnBack(lastPress: t0, now: t0.add(const Duration(seconds: 1))),
        isTrue);
  });

  test('через паузу счёт начинается заново', () {
    expect(exitOnBack(lastPress: t0, now: t0.add(const Duration(seconds: 4))),
        isFalse);
  });

  test('граница окна включительна', () {
    expect(
      exitOnBack(lastPress: t0, now: t0.add(const Duration(seconds: 3))),
      isTrue,
    );
  });

  test('часы, прыгнувшие назад, не запирают в комнате', () {
    expect(
      exitOnBack(lastPress: t0, now: t0.subtract(const Duration(minutes: 5))),
      isFalse,
    );
  });
}
