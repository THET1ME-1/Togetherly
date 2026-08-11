import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/custom_wishes_store.dart';

void main() {
  group('withWish', () {
    test('свежее встаёт первым', () {
      expect(withWish(const ['кофе'], 'чай'), ['чай', 'кофе']);
    });

    test('повтор поднимается, а не задваивается', () {
      expect(withWish(const ['чай', 'кофе'], 'кофе'), ['кофе', 'чай']);
    });

    test('регистр не создаёт второй записи', () {
      expect(withWish(const ['Кофе'], 'кофе'), ['кофе']);
    });

    test('больше трёх не копится', () {
      final list = withWish(withWish(withWish(const ['а'], 'б'), 'в'), 'г');
      expect(list, ['г', 'в', 'б']);
    });

    test('пробелы обрезаются, пустая строка ничего не меняет', () {
      expect(withWish(const [], '  кофе '), ['кофе']);
      expect(withWish(const ['кофе'], '   '), ['кофе']);
    });
  });
}
