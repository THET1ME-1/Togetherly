import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/plus_gift.dart';

/// Подарок Togetherly+: разбор ответа сервера и правила витрины.
///
/// Цену и скидку считает сервер, а клиент их только показывает — значит
/// проверять надо именно разбор: соврать здесь значит показать человеку не ту
/// сумму рядом с кнопкой оплаты.
void main() {
  Map<String, dynamic> answer({
    bool ok = true,
    bool enabled = true,
    List<Map<String, dynamic>>? partners,
    String currency = 'RUB',
    num price = 900,
    num basePrice = 900,
    num discount = 0,
  }) =>
      {
        'ok': ok,
        'enabled': enabled,
        'partners': partners ??
            [
              {
                'uid': 'u1',
                'groupId': 'g1',
                'name': 'Аня',
                'avatar': '',
                'already': false,
              },
            ],
        'currency': currency,
        'price': price,
        'basePrice': basePrice,
        'discount': discount,
      };

  group('разбор ответа', () {
    test('обычный ответ с одним получателем', () {
      final offer = PlusGiftOffer.fromJson(answer());
      expect(offer.visible, isTrue);
      expect(offer.recipients.single.name, 'Аня');
      expect(offer.recipients.single.groupId, 'g1');
      expect(offer.hasAnyoneToGift, isTrue);
      expect(offer.priceLabel, '900 ₽');
      expect(offer.baseLabel, isEmpty, reason: 'скидки нет — зачёркивать нечего');
    });

    test('отказ сервера превращается в пустое предложение', () {
      expect(PlusGiftOffer.fromJson(answer(ok: false)).visible, isFalse);
    });

    test('подарок выключен на сервере — карточки нет', () {
      expect(PlusGiftOffer.fromJson(answer(enabled: false)).visible, isFalse);
    });

    test('дарить некому — карточки нет', () {
      final offer = PlusGiftOffer.fromJson(answer(partners: []));
      expect(offer.visible, isFalse);
      expect(offer.suggested, isNull);
    });

    test('получатель без uid или связи отбрасывается', () {
      final offer = PlusGiftOffer.fromJson(answer(partners: [
        {'uid': '', 'groupId': 'g1', 'name': 'Никто'},
        {'uid': 'u2', 'groupId': '', 'name': 'Тоже никто'},
        {'uid': 'u3', 'groupId': 'g3', 'name': 'Марина'},
      ]));
      expect(offer.recipients.map((r) => r.name), ['Марина']);
    });
  });

  group('кому предлагать', () {
    test('первым идёт тот, у кого Плюса ещё нет', () {
      final offer = PlusGiftOffer.fromJson(answer(partners: [
        {'uid': 'u1', 'groupId': 'g1', 'name': 'Костя', 'already': true},
        {'uid': 'u2', 'groupId': 'g2', 'name': 'Аня', 'already': false},
      ]));
      expect(offer.suggested?.name, 'Аня');
      expect(offer.hasAnyoneToGift, isTrue);
    });

    test('у всех уже есть — карточка видна, но дарить нечего', () {
      final offer = PlusGiftOffer.fromJson(answer(partners: [
        {'uid': 'u1', 'groupId': 'g1', 'name': 'Костя', 'already': true},
      ]));
      expect(offer.visible, isTrue,
          reason: 'знакомое имя не должно исчезать из списка');
      expect(offer.hasAnyoneToGift, isFalse);
    });
  });

  group('скидка', () {
    test('процент и старая цена доезжают с сервера', () {
      final offer = PlusGiftOffer.fromJson(
          answer(price: 720, basePrice: 900, discount: 20));
      expect(offer.discount, 20);
      expect(offer.priceLabel, '720 ₽');
      expect(offer.baseLabel, '900 ₽');
    });

    test('бессмысленный процент отбрасывается', () {
      expect(PlusGiftOffer.fromJson(answer(discount: 120)).discount, 0);
      expect(PlusGiftOffer.fromJson(answer(discount: -5)).discount, 0);
    });

    test('базовая цена ниже итоговой не зачёркивается', () {
      final offer = PlusGiftOffer.fromJson(
          answer(price: 900, basePrice: 500, discount: 10));
      expect(offer.baseLabel, isEmpty);
    });
  });

  group('деньги строкой', () {
    test('круглая сумма идёт без копеек', () {
      expect(formatMoney(900, 'RUB'), '900 ₽');
      expect(formatMoney(10, 'USD'), '10 \$');
      expect(formatMoney(8, 'EUR'), '8 €');
    });

    test('копейки показываются, когда они есть', () {
      expect(formatMoney(827.82, 'RUB'), '827,82 ₽');
      expect(formatMoney(8.57, 'EUR'), '8,57 €');
    });

    test('нулевая цена не превращается в «0 ₽»', () {
      expect(formatMoney(0, 'RUB'), isEmpty);
      expect(PlusGiftOffer.fromJson(answer(price: 0)).priceLabel, isEmpty);
    });

    test('незнакомая валюта не роняет витрину', () {
      expect(formatMoney(100, 'GBP'), '100 ₽');
    });
  });

  group('цена самого Плюса', () {
    test('цена покупки приходит в той же валюте', () {
      final offer = PlusGiftOffer.fromJson({
        ...answer(currency: 'EUR', price: 10, basePrice: 10),
        'plusPrice': 10,
        'plusBasePrice': 10,
        'plusDiscount': 0,
      });
      expect(offer.plusPriceLabel, '10 €');
      expect(offer.plusBaseLabel, isEmpty);
    });

    test('распродажа зачёркивает прежнюю цену', () {
      final offer = PlusGiftOffer.fromJson({
        ...answer(),
        'plusPrice': 630,
        'plusBasePrice': 900,
        'plusDiscount': 30,
      });
      expect(offer.plusPriceLabel, '630 ₽');
      expect(offer.plusBaseLabel, '900 ₽');
      expect(offer.plusDiscount, 30);
    });

    test('сервер промолчал о цене — витрина не выдумывает', () {
      final offer = PlusGiftOffer.fromJson(answer());
      expect(offer.plusPriceLabel, isEmpty);
    });
  });
}
