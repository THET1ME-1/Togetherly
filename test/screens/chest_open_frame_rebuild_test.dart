import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// TOG-70 (канал, 27.10.2026): «анимация открывания сундука кажется зависает».
// Каждый кадр открытия (16 в секунду) звал setState всего экрана сундука, хотя
// на кадре сдвигается только приз над сундуком: перестраивались листалка
// сундуков, лучи, кнопки, таблица шансов. Приз теперь слушает номер кадра сам,
// а экран перестраивается один раз, когда появляется название выигрыша.
void main() {
  final src = File('lib/screens/chest_screen.dart').readAsStringSync();

  String body(String name) {
    final start = src.indexOf(RegExp('(?:void|Widget) $name\\('));
    expect(start, isNonNegative, reason: name);
    final next = src.indexOf(RegExp(r'\n  (?:void|Future|Widget|String|static|@override)'), start + 1);
    return src.substring(start, next);
  }

  test('кадр открытия не перестраивает весь экран', () {
    final frame = body('_onOpenFrame');
    final setStateAt = frame.indexOf('setState(');
    expect(setStateAt, isNonNegative, reason: 'название выигрыша появляется через setState');
    final guard = frame.lastIndexOf('if (', setStateAt);
    expect(guard, isNonNegative, reason: 'setState только при появлении названия');
    expect(frame.substring(guard, setStateAt), contains('slot.won == null'));
  });

  test('приз над сундуком слушает номер кадра сам', () {
    expect(body('_chestArt'), contains('ListenableBuilder('));
    expect(src, contains('frameTick'));
  });
}
