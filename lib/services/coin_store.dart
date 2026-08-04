import 'package:flutter/foundation.dart';

import 'iap_service.dart';
import 'rustore_iap_service.dart';

/// Описание пака коинов, продаваемого через магазин.
class CoinPack {
  const CoinPack({
    required this.productId,
    required this.coins,
  });

  /// Идентификатор продукта (одинаков во всех магазинах: Google Play, App
  /// Store, RuStore — продукты заводятся с теми же id).
  final String productId;

  /// Количество монет, которое получит пользователь после покупки.
  final int coins;
}

/// Все доступные паки монет. Порядок = порядок отображения в UI.
///
/// Список пуст в сборках, где товаров монет нет в магазине (`STORE=github`, а
/// с ним собирается и IPA). Причина не в UI: витрина и так была скрыта, но
/// идентификаторы `coins_10/50/120/300` лежали КОНСТАНТАМИ в бинарнике, и
/// App Review находил их сканированием, а в App Store Connect эти продукты
/// черновики — отсюда отказы 2.1(b) «products could not be found in the
/// submitted binary». Ветка константная, поэтому в снапшот AOT попадает
/// только выбранная половина, и в IPA строк товаров нет вовсе.
const List<CoinPack> kCoinPacks = _storeHasProducts
    ? <CoinPack>[
        CoinPack(productId: 'coins_10', coins: 10),
        CoinPack(productId: 'coins_50', coins: 50),
        CoinPack(productId: 'coins_120', coins: 120),
        CoinPack(productId: 'coins_300', coins: 300),
      ]
    : <CoinPack>[];

/// Товар Togetherly+ в магазинах приложений (Google Play — способ покупки
/// `lifetime`, заведён 26 июля 2026). В отличие от монет это НЕрасходуемая
/// покупка: купить второй раз нельзя, а восстанавливать доступ не нужно — флаг
/// живёт на аккаунте в PocketBase и переезжает вместе с ним.
const String kPlusProductId = _storeHasProducts ? 'togetherly_plus' : '';

/// Продаётся ли платный элемент каталога через биллинг магазина, а не через
/// сайт. В сборке для Google Play платить мимо Google нельзя — за это снимают
/// приложение; в sideload и RuStore товаров Play нет, там остаётся lava.top.
const bool kCatalogBuysInStore = kStore == 'play';

/// Товар магазина для ключа владения: `mood_pack:moti` → `mood_pack.moti`.
///
/// Двоеточие в идентификаторе товара Google Play не принимает, поэтому в
/// консоли те же ключи заводятся через точку. Пересчёт вместо таблицы
/// соответствий: новый пак — это запись каталога плюс товар в консоли, кода
/// это не касается.
String catalogProductId(String featureKey) => featureKey.replaceFirst(':', '.');

/// Статус обработки одной покупки.
enum IapStatus {
  /// Покупка подтверждена и монеты начислены.
  success,

  /// Платёж был инициирован, но сервер ещё не начислил монеты
  /// (например, pending-платёж).
  pending,

  /// Покупка отменена пользователем.
  cancelled,

  /// Произошла ошибка (сеть, магазин, сервер).
  error,
}

/// Результат попытки покупки.
class IapResult {
  const IapResult(this.status, {this.coins = 0, this.error});

  final IapStatus status;

  /// Количество начисленных монет (только при [IapStatus.success]).
  final int coins;

  /// Человекочитаемое описание ошибки (только при [IapStatus.error]).
  final String? error;
}

/// Коллбек для подтверждения покупки на сервере и начисления монет.
/// Возвращает новый баланс или null при ошибке.
///
///  - [productId] — идентификатор купленного продукта (например, `coins_50`)
///  - [purchaseToken] — токен/идентификатор покупки (Google Play / App Store
///    serverVerificationData либо RuStore purchaseId) — используется сервером
///    как ключ идемпотентности.
typedef GrantCoinsCallback = Future<int?> Function({
  required String productId,
  required String purchaseToken,
});

/// Абстракция магазина монет. Реализуется per-store ([IapService] для Google
/// Play / App Store, [RuStoreIapService] для RuStore). UI работает только
/// через этот интерфейс и не знает, какой магазин под капотом.
abstract class CoinStore extends ChangeNotifier {
  /// true если магазин доступен на этом устройстве.
  bool get isAvailable;

  /// true если идёт загрузка продуктов или обработка покупки.
  bool get isLoading;

  /// Готовый ценник продукта (с валютой), либо null если ещё не загружен.
  String? priceLabel(String productId);

  /// Цена числом в валюте магазина — нужна витрине, чтобы отметить пак с
  /// лучшей ценой за монету. Считать по [priceLabel] нельзя: там валюта,
  /// пробелы и запятая, и в каждой стране по-своему. null — цена ещё не
  /// приехала или магазин её не отдаёт.
  double? priceValue(String productId) => null;

  /// Инициализация. [onGrantCoins] — серверное начисление после оплаты.
  Future<void> init({required GrantCoinsCallback onGrantCoins});

  /// Инициирует покупку продукта [productId]. Завершается после оплаты/отмены.
  Future<IapResult> buy(String productId);

  /// Догрузить описание товара, которого нет в постоянном списке.
  ///
  /// Паки и маскоты приезжают каталогом с сервера уже после старта, поэтому их
  /// товары нельзя спросить у магазина заранее вместе с монетами. Возвращает
  /// true, если товар известен магазину и покупку можно начинать.
  Future<bool> ensureProduct(String productId) async => false;

  /// Восстановление/доведение незавершённых покупок (кнопка «Restore»).
  Future<void> restorePurchases();
}

/// Магазин текущей сборки. Переключается флагом сборки:
///   flutter build apk --dart-define=STORE=rustore
/// По умолчанию (Google Play / App Store) — `play`.
const String kStore = String.fromEnvironment('STORE', defaultValue: 'play');

/// Заведены ли товары этой сборки в магазине. Только Google Play: в App Store
/// продуктов нет вовсе, у RuStore биллинг не работает, в sideload платит
/// lava.top. От этого флага зависит, попадут ли идентификаторы товаров в
/// бинарник вообще — сканер ревью читает именно строки.
const bool _storeHasProducts = kStore == 'play';

/// Можно ли ПОКУПАТЬ монеты в этой сборке. Только Google Play: в sideload
/// платёжный провайдер (lava.top) отклонил товары монет, у RuStore не работает
/// биллинг, в App Store продуктов нет. Сами монеты остаются везде (ежедневный
/// вход, реклама, серия настроений, приглашение) — исчезает только витрина.
const bool kCoinsPurchasable = kStore == 'play';

/// Показывать ли донат→монеты (DonationAlerts с подсказкой указать email). Только
/// в sideload/веб-сборках: GitHub-Android, RuStore, iOS-IPA (все собираются с
/// `STORE=github`/`rustore`). На Google Play и App Store (`STORE=play`) —
/// нельзя (продажа валюты за внешний платёж = нарушение биллинга/3.1.1).
const bool kDonationsEnabled = kStore == 'github' || kStore == 'rustore';

/// Создаёт реализацию магазина под текущую сборку. Биллинг поднимается ровно в
/// одной: Google Play — [IapService]. RuStore, гитхаб-версия и iOS получают
/// заглушку без покупок. [RuStoreIapService] лежит рядом нетронутым — вернуть
/// его в строй, когда у RuStore заработает биллинг, будет одной строкой.
///
/// На iOS StoreKit не трогаем совсем. Витрина паков там скрыта (см.
/// `profile_screen`), но [IapService.init] всё равно спрашивал у стора
/// `coins_10/50/120/300`, а эти продукты в App Store Connect лежат
/// черновиками. App Review видел механику покупок без рабочих продуктов и
/// отклонял версию по 2.1(b) — «products … could not be found in the
/// submitted binary». Вернём паки на iPhone — сначала проводим продукты через
/// ревью, потом снимаем эту ветку.
CoinStore createCoinStore() {
  if (defaultTargetPlatform == TargetPlatform.iOS) return _DisabledCoinStore();
  // RuStore тоже получает заглушку: их биллинг не работает, монеты там не
  // продаются, а Togetherly+ покупается через lava.top. Поднимать
  // `flutter_rustore_billing` ради пустого списка товаров незачем — реализация
  // (`rustore_iap_service.dart`) остаётся на случай, когда биллинг заработает.
  return switch (kStore) {
    'play' => IapService(),
    _ => _DisabledCoinStore(),
  };
}

CoinStore? _shared;

/// Общий магазин на всё приложение.
///
/// Раньше каждый экран звал [createCoinStore] и получал свой экземпляр, а тот
/// подписывался на общий поток покупок Google Play и отписывался в `dispose`.
/// Стоило закрыть экран Togetherly+ (или свернуть приложение, пока человек
/// платит), и покупку становилось некому обработать: деньги списаны, роут
/// начисления не вызван, `iap_purchases` пуст. Ровно так 30 июля пропала
/// оплата Togetherly+ на 9,99 €.
///
/// Экземпляр один и живёт столько же, сколько приложение: незавершённые
/// покупки Google доставляет в поток при следующем запуске, и они доезжают до
/// сервера сами. Экраны его НЕ закрывают — `dispose` у общего магазина звать
/// нельзя.
CoinStore get sharedCoinStore => _shared ??= createCoinStore();

/// Магазин-заглушка для сборок без покупок (гитхаб): всё выключено, `buy`
/// сразу возвращает ошибку. UI покупки в такой сборке всё равно скрыт
/// ([kCoinsPurchasable]).
class _DisabledCoinStore extends CoinStore {
  @override
  bool get isAvailable => false;
  @override
  bool get isLoading => false;
  @override
  String? priceLabel(String productId) => null;
  @override
  Future<void> init({required GrantCoinsCallback onGrantCoins}) async {}
  @override
  Future<IapResult> buy(String productId) async =>
      const IapResult(IapStatus.error, error: 'disabled');
  @override
  Future<bool> ensureProduct(String productId) async => false;
  @override
  Future<void> restorePurchases() async {}
}
