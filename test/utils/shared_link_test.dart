import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/shared_link.dart';

void main() {
  group('extractSharedUrl', () {
    test('достаёт ссылку из подписи магазина', () {
      // Магазины шлют «название, перенос строки, ссылка», а не голый адрес.
      const text = 'Кружка «Вместе» за 890 ₽\nhttps://www.ozon.ru/product/123';
      expect(extractSharedUrl(text), 'https://www.ozon.ru/product/123');
    });

    test('берёт голую ссылку целиком', () {
      expect(extractSharedUrl('https://www.wildberries.ru/catalog/1/detail.aspx'),
          'https://www.wildberries.ru/catalog/1/detail.aspx');
    });

    test('оставляет параметры запроса', () {
      const text = 'смотри https://market.yandex.ru/product--x/123?sku=99&from=share';
      expect(extractSharedUrl(text),
          'https://market.yandex.ru/product--x/123?sku=99&from=share');
    });

    test('срезает хвостовую пунктуацию', () {
      expect(extractSharedUrl('вот это: https://ozon.ru/t/abc123.'),
          'https://ozon.ru/t/abc123');
      expect(extractSharedUrl('(https://ozon.ru/t/abc123)'),
          'https://ozon.ru/t/abc123');
    });

    test('берёт первую ссылку, когда их несколько', () {
      const text = 'https://a.example/1 и ещё https://b.example/2';
      expect(extractSharedUrl(text), 'https://a.example/1');
    });

    test('понимает http', () {
      expect(extractSharedUrl('http://shop.local/item'), 'http://shop.local/item');
    });

    test('пусто, когда ссылки нет', () {
      expect(extractSharedUrl('просто текст без адреса'), '');
      expect(extractSharedUrl(''), '');
    });

    test('не принимает чужие схемы', () {
      // Из приложений прилетает и `loveapp://`, и `mailto:` — форме вещи они
      // не нужны, а превью по ним всё равно не собрать.
      expect(extractSharedUrl('loveapp://invite/ABC123'), '');
      expect(extractSharedUrl('mailto:kto@example.com'), '');
    });
  });
}
