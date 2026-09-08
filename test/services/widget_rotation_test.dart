// Режим карусели в редакторе всегда показан.
//
// Пока в фото-виджете один снимок, экран пишет в настройки `none` — крутить
// нечего. Человек добавляет второй снимок, открывает настройку и видит два
// пустых кружка: ни «При разблокировке», ни «По времени» не отмечены, хотя
// карусель уже работает и меняет фото при разблокировке (`unlock` — значение по
// умолчанию у Android-приёмника). Проверено на эмуляторе 08.09.2026.
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/widget_rotation.dart';

void main() {
  test('«по времени» остаётся собой', () {
    expect(rotationTypeForEditor('time'), 'time');
  });

  test('всё остальное читается как «при разблокировке»', () {
    expect(rotationTypeForEditor('unlock'), 'unlock');
    expect(rotationTypeForEditor('none'), 'unlock');
    expect(rotationTypeForEditor(''), 'unlock');
    expect(rotationTypeForEditor(null), 'unlock');
    expect(rotationTypeForEditor('какая-то ерунда'), 'unlock');
  });
}
