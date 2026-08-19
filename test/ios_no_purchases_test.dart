// Сторож: паки монет живут только в сборке Google Play.
//
// В App Store из товаров заведён ОДИН Togetherly+ (19.08.2026), продуктов
// монет там нет; у RuStore не работает биллинг, в sideload платит lava.top.
// Значит ни витрины монет, ни их идентификаторов в этих сборках быть не
// должно. Про сам Плюс на iPhone — соседний тест
// `ios_plus_only_purchase_test.dart`.
//
// Отказы по 2.1(b) прилетали трижды подряд: витрина монет была скрыта, но
// приложение всё равно спрашивало у StoreKit `coins_10/50/120/300`, а сами
// продукты в App Store Connect лежат черновиками. Плюс 3.1.1 за любую внешнюю
// оплату. Проверять это глазами при каждой правке бессмысленно — пусть валит
// тест.
//
// Тест читает исходники, а не запускает приложение: гейт по платформе — это
// свойство КОДА, и проверять его надо там же.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/coin_store.dart';

/// Обращения, каждое из которых на iPhone обязано быть закрыто.
const _guarded = <String, String>{
  'IapService(': 'биллинг Google Play',
  'RuStoreIapService(': 'биллинг RuStore',
  'queryProductDetails': 'запрос товаров у стора',
  'buyConsumable': 'покупка расходуемого в сторе',
  'checkoutUrl(': 'счёт на внешнюю оплату',
  'purchaseUrl': 'ссылка на внешнюю оплату',
};

/// Файлы, где гейт стоит выше по стеку и повторять его в каждой строке незачем.
/// Реализации биллинга целиком про покупки — их создаёт только фабрика
/// `createCoinStore`, а она на iOS отдаёт заглушку (это проверяет свой тест).
const _exempt = <String>{
  'lib/services/coin_store.dart',
  'lib/services/iap_service.dart',
  'lib/services/rustore_iap_service.dart',
  'lib/services/plus_service.dart',
  'lib/services/catalog_service.dart',
  'lib/main.dart',
};

/// Есть ли рядом (в пределах окна) отсечка по платформе или по доступности.
bool _hasGuard(List<String> lines, int index) {
  final from = (index - 60).clamp(0, lines.length);
  final window = lines.sublist(from, index + 1).join('\n');
  return window.contains('Platform.isIOS') ||
      window.contains('PlusGate.hidden') ||
      window.contains('kCatalogBuysInStore') ||
      window.contains('kCoinsPurchasable') ||
      window.contains('PlusService.exists');
}

void main() {
  test('идентификаторы товаров не попадают в сборки без магазина', () {
    // Тест идёт с STORE по умолчанию (play) — там товары нужны и должны быть.
    expect(kStore, 'play', reason: 'тест рассчитан на сборку по умолчанию');
    expect(kCoinPacks, isNotEmpty);

    // А объявления обязаны быть условными: иначе строки товаров уедут в IPA.
    final src = File('lib/services/coin_store.dart').readAsStringSync();
    expect(src.contains('const List<CoinPack> kCoinPacks = _storeHasProducts'), isTrue,
        reason: 'список паков обязан зависеть от _storeHasProducts');
    expect(src.contains("_storeHasProducts = kStore == 'play'"), isTrue,
        reason: 'товары заведены только в Google Play');
    expect(src.contains("kCoinsPurchasable = kStore == 'play'"), isTrue,
        reason: 'витрина монет живёт только там, где работает биллинг');
    expect(src.contains("'play' => IapService(),"), isTrue,
        reason: 'на Android биллинг поднимается только в сборке Play');
  });

  test('каждое обращение к покупкам закрыто гейтом', () {
    final offenders = <String>[];
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final rel = file.path.replaceAll(r'\', '/');
      if (_exempt.any(rel.endsWith)) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//') || line.trimLeft().startsWith('///')) continue;
        for (final entry in _guarded.entries) {
          if (!line.contains(entry.key)) continue;
          if (_hasGuard(lines, i)) continue;
          offenders.add('$rel:${i + 1} — ${entry.value}: ${line.trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'на iPhone это недостижимо только по случайности:\n${offenders.join('\n')}');
  });

  test('на iPhone магазин поднимается только ради Togetherly+', () {
    // Единственная точка, где решается, трогать ли StoreKit вообще. Паки монет
    // туда не попадают: kCoinPacks в этой сборке пуст.
    final src = File('lib/services/coin_store.dart').readAsStringSync();
    expect(
      src.contains('return kPlusInStore ? IapService() : _DisabledCoinStore();'),
      isTrue,
      reason: 'createCoinStore на iOS обязан смотреть на kPlusInStore',
    );
  });

  test('лист монет без витрины называется заданиями', () {
    final src = File('lib/screens/profile_screen.dart').readAsStringSync();
    expect(src.contains('packsVisible ? _s.coinShopTitle : _s.coinEarnTitle'), isTrue,
        reason: 'без паков это не магазин, а список способов заработать');
    expect(src.contains('packsVisible ? _s.coinShopSubtitle : _s.coinEarnSubtitle'), isTrue);
    expect(src.contains('if (kCoinsPurchasable && !Platform.isIOS) ...['), isTrue,
        reason: '«Восстановить покупки» показываем только там, где покупки есть');
  });

  test('донаты и код пополнения на iPhone выключены явно', () {
    final profile = File('lib/screens/profile_screen.dart').readAsStringSync();
    expect(profile.contains('kDonationsEnabled && !Platform.isIOS'), isTrue,
        reason: 'IPA собирается с STORE=github, где донаты включены по флагу');
  });
}
