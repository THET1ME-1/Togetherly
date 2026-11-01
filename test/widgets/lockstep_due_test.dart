import 'dart:ui' show Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/mascot/lockstep_art.dart';

// Слои Ту двигаются по своим часам, а не по счёту кадров: при упаковке
// одинаковые кадры склеиваются в один длинный, и у слоя одежды взрыва 29
// кадров против 64 у тела. Пошаговое движение стояло на склеенном кадре
// 1,8 с, и тело замирало на хлопке, а потом прыгало к собранному Ту.
void main() {
  const ms = Duration(milliseconds: 1);

  test('двигаются только слои, чьё время подошло', () {
    expect(lockstepDue([ms * 50, ms * 1800, ms * 50], ms * 60), [0, 2]);
  });

  test('длинный кадр одежды не держит тело', () {
    final due = lockstepDue([ms * 100, ms * 1800], ms * 120);
    expect(due, contains(0));
    expect(due, isNot(contains(1)));
  });

  test('ничего не подошло — шага нет', () {
    expect(lockstepDue([ms * 100, ms * 200], ms * 50), isEmpty);
  });

  // Одетый Ту рисуется тремя слоями, и на медленном телефоне кадры идут
  // медленнее часов. Разовую сцену заканчивают, когда все слои показали
  // свои кадры, иначе кувырок обрывался раньше переворота (сборка 263).
  group('сцена доиграна', () {
    test('все слои показали свои кадры, хоть их и разное число', () {
      expect(lockstepPlayedThrough(shown: [56, 29, 56], frames: [56, 29, 56]), isTrue);
    });

    test('тело ещё не дошло до конца — сцена идёт', () {
      expect(lockstepPlayedThrough(shown: [10, 29, 56], frames: [56, 29, 56]), isFalse);
    });

    test('неподвижный слой одежды конца не ждёт', () {
      expect(lockstepPlayedThrough(shown: [56, 1], frames: [56, 1]), isTrue);
    });
  });

  group('слой за краем экрана кадры не разжимает', () {
    const screen = Size(400, 800);

    test('Ту на экране', () {
      expect(lockstepOnScreen(const Rect.fromLTWH(300, 600, 112, 112), screen), isTrue);
    });

    test('блок маскота ниже экрана', () {
      expect(lockstepOnScreen(const Rect.fromLTWH(20, 1400, 112, 112), screen), isFalse);
    });

    test('краешек на экране — уже рисуется', () {
      expect(lockstepOnScreen(const Rect.fromLTWH(20, 760, 112, 112), screen), isTrue);
    });
  });
}
