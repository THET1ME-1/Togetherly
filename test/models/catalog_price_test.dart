import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/catalog_price.dart';

/// Цену платного набора называет магазин, а каталог — только пока магазин
/// молчит.
///
/// В карточке товара App Store у «Моти» стоит ровно 5,00 $, в манифесте
/// каталога — те же 5 USD. Но у Apple и Google свои налоги и округления по
/// странам: в Германии это будет 5,49 €, а в Бразилии своя цифра. Если рядом
/// показать обе, выйдет то же, что было на кнопке Togetherly+ — «Купить за
/// $10 · 9,99 $», две разные цены подряд.
void main() {
  group('catalogPriceLabel', () {
    test('магазин ответил — берём его цену', () {
      expect(
        catalogPriceLabel(storePrice: '5,00 \$', catalogPrice: '5\$'),
        '5,00 \$',
      );
    });

    test('магазин молчит — показываем цену каталога', () {
      // Товар ещё грузится или сборка без биллинга: молчать о цене хуже, чем
      // назвать ту, что лежит в манифесте.
      expect(
        catalogPriceLabel(storePrice: null, catalogPrice: '5\$'),
        '5\$',
      );
      expect(
        catalogPriceLabel(storePrice: '', catalogPrice: '5\$'),
        '5\$',
      );
    });

    test('двух цен подряд не бывает никогда', () {
      final label = catalogPriceLabel(storePrice: '5,00 \$', catalogPrice: '5\$');
      // В строке ровно одно число: две цены рядом человек читает как ошибку.
      final numbers = RegExp(r'\d+([.,]\d+)?').allMatches(label);
      expect(numbers.length, 1);
    });
  });

  group('catalogBuysInStore', () {
    test('на iPhone платим через StoreKit', () {
      // Товар `mood_pack.moti` заведён в App Store Connect 19.08.2026.
      // Внешняя оплата там — 3.1.1, за неё версию уже отклоняли.
      expect(catalogBuysInStore(isIOS: true, store: 'github'), isTrue);
    });

    test('в сборке Google Play — через биллинг Play', () {
      expect(catalogBuysInStore(isIOS: false, store: 'play'), isTrue);
    });

    test('в sideload и RuStore остаётся счёт на сайте', () {
      expect(catalogBuysInStore(isIOS: false, store: 'github'), isFalse);
      expect(catalogBuysInStore(isIOS: false, store: 'rustore'), isFalse);
    });
  });

  group('код слушается этих правил', () {
    test('решение о биллинге считается в рантайме', () {
      final src = File('lib/services/coin_store.dart').readAsStringSync();
      expect(src.contains('bool get kCatalogBuysInStore => catalogBuysInStore('),
          isTrue,
          reason: 'IPA собирается с STORE=github — одного kStore мало');
    });

    test('платный набор на iPhone показывается, когда его можно купить', () {
      final src = File('lib/models/mood_pack.dart').readAsStringSync();
      expect(src.contains('bool buysInStore = false'), isTrue);
      final call = File('lib/widgets/mood_pack_selector.dart').readAsStringSync();
      expect(call.contains('buysInStore: kCatalogBuysInStore'), isTrue,
          reason: 'иначе набор так и остался бы скрытым на iPhone');
    });

    test('покупка на iPhone идёт через магазин, а не на сайт', () {
      final src = File('lib/widgets/mood_pack_selector.dart').readAsStringSync();
      expect(src.contains('if (Platform.isIOS && !kCatalogBuysInStore) return;'),
          isTrue,
          reason: 'внешняя оплата на iPhone — 3.1.1');
    });

    test('цена на кнопке одна и от магазина', () {
      for (final path in [
        'lib/widgets/mood_pack_selector.dart',
        'lib/screens/home/widgets/mood_picker_dialog.dart',
      ]) {
        final src = File(path).readAsStringSync();
        expect(src.contains('catalogPriceLabel('), isTrue,
            reason: '$path показывает цену мимо правила');
      }
    });
  });
}
