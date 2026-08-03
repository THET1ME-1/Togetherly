import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/coin_store.dart';

void main() {
  group('Товар магазина для элемента каталога', () {
    test('двоеточие ключа превращается в точку', () {
      expect(catalogProductId('mood_pack:moti'), 'mood_pack.moti');
      expect(catalogProductId('mascot:kuku'), 'mascot.kuku');
    });

    test('меняется только первое двоеточие', () {
      expect(catalogProductId('mood_pack:a:b'), 'mood_pack.a:b');
    });

    test('ключ без двоеточия остаётся как есть', () {
      expect(catalogProductId('togetherly_plus'), 'togetherly_plus');
    });
  });
}
