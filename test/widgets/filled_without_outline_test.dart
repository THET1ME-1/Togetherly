import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Залитая поверхность не носит обводку.
///
/// В M3 контейнер отделяет элемент от фона своей ролью, а рамка поверх заливки
/// читается как поле ввода. Варианты ответа в «Умении любить» были залиты и
/// обведены разом, поле «Название» в листе своей темы стояло в
/// `OutlineInputBorder` рядом с залитыми кнопками (замечание автора,
/// 18.08.2026).
void main() {
  test('вариант ответа в тесте залит и без обводки', () {
    final src = File('lib/screens/love_test_screen.dart').readAsStringSync();
    final button = src.substring(src.indexOf('Widget _answerButton'));
    final body = button.substring(0, button.indexOf('// ── Результат'));
    expect(body.contains('Border.all'), isFalse,
        reason: 'обводка вернулась к варианту ответа');
    expect(body.contains('surfaceContainer'), isTrue,
        reason: 'вариант ответа обязан быть залит ролью контейнера');
    expect(body.contains('width: double.infinity'), isTrue,
        reason: 'вариант ответа занимает всю ширину');
  });

  test('поле названия своей темы залито и без обводки', () {
    final src =
        File('lib/widgets/theme/custom_theme_sheet.dart').readAsStringSync();
    expect(src.contains('borderSide: BorderSide.none'), isTrue,
        reason: 'поле снова получило рамку');
    expect(src.contains('filled: true'), isTrue,
        reason: 'поле обязано быть залитым');
  });

  test('кнопка выбора снимка занимает всю ширину', () {
    final src =
        File('lib/widgets/theme/custom_theme_sheet.dart').readAsStringSync();
    final tab = src.substring(src.indexOf('Widget _photoTab'));
    final button = tab.substring(0, tab.indexOf('FilledButton.tonalIcon'));
    expect(button.contains('width: double.infinity'), isTrue,
        reason: 'кнопка «Выбрать снимок» снова уже контейнера');
  });
}
