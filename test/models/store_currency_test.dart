import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/store_currency.dart';

/// Валюта покупки считается по стране устройства.
///
/// До 24.08.2026 приложение всегда просило рубли: покупатель из Германии видел
/// рублёвую сумму, хотя цена в евро у товара есть с самого начала.
void main() {
  group('валюта по стране', () {
    test('рублёвая зона платит рублями', () {
      for (final c in ['RU', 'BY', 'KZ', 'AM', 'KG']) {
        expect(currencyForCountry(c), kCurrencyRub, reason: c);
      }
    });

    test('Европа платит евро', () {
      for (final c in ['DE', 'FR', 'IT', 'ES', 'PL', 'UA', 'GE', 'TR']) {
        expect(currencyForCountry(c), kCurrencyEur, reason: c);
      }
    });

    test('остальной мир платит долларами', () {
      for (final c in ['US', 'BR', 'IN', 'JP', 'AU', 'ZA']) {
        expect(currencyForCountry(c), kCurrencyUsd, reason: c);
      }
    });

    test('регистр и пробелы не мешают', () {
      expect(currencyForCountry('ru'), kCurrencyRub);
      expect(currencyForCountry(' de '), kCurrencyEur);
    });

    test('страны нет — доллары, а не пустота', () {
      expect(currencyForCountry(null), kCurrencyUsd);
      expect(currencyForCountry(''), kCurrencyUsd);
      expect(currencyForCountry('RUS'), kCurrencyUsd);
    });
  });

  group('способ оплаты', () {
    test('за рубли только СБП: карточная форма российские карты не берёт', () {
      expect(paymentMethodFor(kCurrencyRub), 'sbp');
    });

    test('в валюте провайдера выбирает сама lava', () {
      expect(paymentMethodFor(kCurrencyEur), isEmpty);
      expect(paymentMethodFor(kCurrencyUsd), isEmpty);
    });
  });
}
