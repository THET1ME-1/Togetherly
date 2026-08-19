/// Цена платного элемента каталога и путь оплаты.
///
/// В манифесте каталога у набора лежит своя цена («5 USD»), а у магазина —
/// своя: Apple и Google считают налог и округление по стране покупателя, и в
/// Германии те же пять долларов превращаются в 5,49 €. Показывать обе разом
/// нельзя: ровно так на кнопке Togetherly+ выходило «Купить за $10 · 9,99 $».
library;

/// Что писать на кнопке покупки.
///
/// Цену называет магазин; каталог остаётся запасным ответом на те секунды,
/// пока товар не подгрузился, и для сборок, где биллинга магазина нет вовсе.
String catalogPriceLabel({
  required String? storePrice,
  required String catalogPrice,
}) {
  final fromStore = (storePrice ?? '').trim();
  return fromStore.isEmpty ? catalogPrice : fromStore;
}

/// Платить через биллинг магазина или через счёт на сайте.
///
/// На iPhone — всегда магазин: товары каталога заведены в App Store Connect
/// (`mood_pack.moti` — 19.08.2026), а внешняя оплата это 3.1.1, за которую
/// версию уже отклоняли. На Android магазин только в сборке для Google Play:
/// в sideload и RuStore товаров Play нет, там остаётся lava.top.
bool catalogBuysInStore({required bool isIOS, required String store}) =>
    isIOS || store == 'play';
