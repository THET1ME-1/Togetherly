// Сторож: на iPhone продаётся ровно одна вещь — Togetherly+.
//
// 19 августа 2026 в App Store Connect заведён товар `togetherly_plus`
// (разовая покупка, 9,99 $, 175 территорий, READY_TO_SUBMIT). До этого дня
// продуктов там не было вовсе, и любое обращение к StoreKit стоило отказа по
// 2.1(b) — Apple ищет в бинарнике продукты, связанные с версией.
//
// Что осталось запретным и почему:
// • паки монет `coins_*` — их в App Store Connect по-прежнему нет, и строки
//   в бинарнике снова притянут 2.1(b);
// • внешняя оплата (lava.top, доначные ссылки) — это 3.1.1, за него версию
//   уже отклоняли.
//
// Проверяем по исходникам: гейт по платформе — свойство кода.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/coin_store.dart';

void main() {
  test('идентификатор Togetherly+ живёт во всех сборках', () {
    // Товар заведён и в Google Play, и в App Store с одним и тем же id.
    expect(kPlusProductId, 'togetherly_plus');
  });

  test('паки монет остаются только там, где они заведены', () {
    final src = File('lib/services/coin_store.dart').readAsStringSync();
    expect(
      src.contains('const List<CoinPack> kCoinPacks = _storeHasProducts'),
      isTrue,
      reason: 'список паков обязан зависеть от _storeHasProducts — иначе '
          'строки coins_* уедут в IPA, где этих товаров нет',
    );
    expect(src.contains("_storeHasProducts = kStore == 'play'"), isTrue);
    expect(src.contains("kCoinsPurchasable = kStore == 'play'"), isTrue);
  });

  test('на iPhone магазин поднимается ради Плюса, а не ради монет', () {
    final src = File('lib/services/coin_store.dart').readAsStringSync();
    expect(
      src.contains('kPlusInStore'),
      isTrue,
      reason: 'нужен отдельный флаг: биллинг на iOS поднимается только под '
          'Togetherly+',
    );
  });

  test('запрос товаров не спрашивает того, чего нет в магазине', () {
    final src = File('lib/services/iap_service.dart').readAsStringSync();
    expect(
      src.contains('if (kPlusProductId.isNotEmpty) kPlusProductId'),
      isTrue,
      reason: 'пустой id уходил бы в queryProductDetails как пустая строка',
    );
  });

  test('внешняя оплата на iPhone по-прежнему закрыта', () {
    final plus = File('lib/services/plus_service.dart').readAsStringSync();
    expect(
      plus.contains("canPurchase =>"),
      isTrue,
      reason: 'правило покупки должно быть в одном месте',
    );
    // Ссылка на lava.top — только там, где нет биллинга магазина.
    final screen = File('lib/screens/plus_screen.dart').readAsStringSync();
    expect(
      screen.contains('if (PlusService.buysInStore)'),
      isTrue,
      reason: 'сначала биллинг магазина, внешняя ссылка — только запасной путь',
    );
  });

  test('донаты на iPhone остаются выключенными', () {
    // Продажа монет за внешний платёж — то же 3.1.1.
    final src = File('lib/services/coin_store.dart').readAsStringSync();
    expect(
      src.contains("kDonationsEnabled = kStore == 'github' || kStore == 'rustore'"),
      isTrue,
    );
    final profile = File('lib/screens/profile_screen.dart').readAsStringSync();
    expect(profile.contains('Platform.isIOS'), isTrue,
        reason: 'карточка доната скрыта на iOS платформенной проверкой');
  });
}
