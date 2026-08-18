// Слой штрихов переживает дописывание в конец и не переживает всё остальное.
//
// Экран пересобирает список видимых штрихов целиком (`_composeVisibleStrokes`),
// но объекты в нём те же самые. Поэтому «дописали в конец» узнаётся сравнением
// ссылок: дёшево, точно и не зависит от того, как список собрали.
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/stroke_layer_cache.dart';

void main() {
  final a = Object();
  final b = Object();
  final c = Object();

  test('дописали в конец', () {
    expect(appendOnly([a, b], [a, b, c]), isTrue);
  });

  test('ничего не поменялось', () {
    expect(appendOnly([a, b], [a, b]), isTrue);
  });

  test('убрали из середины', () {
    expect(appendOnly([a, b, c], [a, c]), isFalse);
  });

  test('переставили местами', () {
    expect(appendOnly([a, b], [b, a]), isFalse);
  });

  test('заменили объект на равный по содержанию, но другой', () {
    expect(appendOnly([a, b], [a, Object(), c]), isFalse,
        reason: 'сверяем ссылки: подменённый штрих обязан пересобрать слой');
  });

  test('стало короче', () {
    expect(appendOnly([a, b, c], [a, b]), isFalse);
  });

  test('пустое начало', () {
    expect(appendOnly([], [a]), isTrue);
    expect(appendOnly([], []), isTrue);
  });
}
