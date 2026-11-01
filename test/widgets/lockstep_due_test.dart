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
}
