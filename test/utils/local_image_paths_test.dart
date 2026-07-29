import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/local_image_paths.dart';

/// Заливка холста рисуется картинкой. Пока она лежит только на диске, всё
/// видно сразу; но серверная запись приходит под своим id, и если путь не
/// переехал — виджет качает по сети файл, который сам же и отправил. Человек
/// видит, как заливка исчезает, крутится индикатор и заливка возвращается.
void main() {
  group('Перенос локального файла на серверный id', () {
    test('Путь переезжает и старый ключ уходит', () {
      final paths = {'fill_local': '/tmp/fill_1.png'};
      expect(adoptLocalImagePath(paths, 'fill_local', 'srv123'), isTrue);
      expect(paths['srv123'], '/tmp/fill_1.png');
      expect(paths.containsKey('fill_local'), isFalse);
    });

    test('Обычному штриху переносить нечего', () {
      final paths = <String, String>{};
      expect(adoptLocalImagePath(paths, 'stroke_local', 'srv123'), isFalse);
      expect(paths, isEmpty);
    });

    test('Совпадающие id ничего не ломают', () {
      final paths = {'same': '/tmp/a.png'};
      expect(adoptLocalImagePath(paths, 'same', 'same'), isFalse);
      expect(paths['same'], '/tmp/a.png');
    });

    test('Чужие записи не задеваются', () {
      final paths = {'a': '/tmp/a.png', 'b': '/tmp/b.png'};
      adoptLocalImagePath(paths, 'a', 'srv_a');
      expect(paths['b'], '/tmp/b.png');
      expect(paths.length, 2);
    });
  });
}
