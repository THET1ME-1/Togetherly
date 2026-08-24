/// Подарок Togetherly+ другому человеку из своей связи.
///
/// Всё, что здесь лежит, приходит с сервера (`GET /api/lava/gift`) и ничего не
/// считает само: цену, скидку и список получателей знает только хук, потому что
/// они зависят от кабинета lava.top и состава пар. Разбор вынесен из экрана
/// отдельным файлом, чтобы его можно было проверить тестом — цена и правило
/// «кому можно дарить» стоят слишком дорого, чтобы жить внутри `build`.
library;

/// Человек, которому можно подарить доступ.
class GiftRecipient {
  const GiftRecipient({
    required this.uid,
    required this.groupId,
    required this.name,
    this.avatarUrl = '',
    this.alreadyHasPlus = false,
  });

  final String uid;

  /// Связь, через которую он виден. Уходит в счёт: по ней сервер заново
  /// сверяет членство и берёт почту, а клиенту почта не показывается вовсе.
  final String groupId;

  final String name;
  final String avatarUrl;

  /// Togetherly+ у него уже есть — платить второй раз не за что.
  final bool alreadyHasPlus;

  static GiftRecipient? fromJson(Map<String, dynamic> json) {
    final uid = (json['uid'] as String? ?? '').trim();
    final groupId = (json['groupId'] as String? ?? '').trim();
    if (uid.isEmpty || groupId.isEmpty) return null;
    return GiftRecipient(
      uid: uid,
      groupId: groupId,
      name: (json['name'] as String? ?? '').trim(),
      avatarUrl: (json['avatar'] as String? ?? '').trim(),
      alreadyHasPlus: json['already'] == true,
    );
  }
}

/// Ответ сервера про подарок: кому, почём и со скидкой ли.
class PlusGiftOffer {
  const PlusGiftOffer({
    this.enabled = false,
    this.recipients = const [],
    this.currency = 'RUB',
    this.price = 0,
    this.basePrice = 0,
    this.discount = 0,
    this.plusPrice = 0,
    this.plusBasePrice = 0,
    this.plusDiscount = 0,
  });

  /// Подарок не спрашивали или сервер не ответил.
  static const PlusGiftOffer none = PlusGiftOffer();

  /// Включён ли подарок на сервере (`LAVA_PLUS_GIFT_ENABLED`).
  final bool enabled;

  /// Все, кому этот человек может подарить, — включая тех, у кого Плюс уже
  /// есть: в списке они видны приглушёнными, иначе пропажа знакомого имени
  /// читается как поломка.
  final List<GiftRecipient> recipients;

  final String currency;

  /// Сколько заплатит даритель.
  final double price;

  /// Обычная цена. Равна [price], когда скидки нет.
  final double basePrice;

  /// Размер скидки в процентах, 0 — скидки нет.
  ///
  /// Считает сервер: по второму тарифу lava или по переменной окружения при
  /// промокоде. Поэтому скидку включают без обновления приложения.
  final int discount;

  /// Сколько стоит Togetherly+ себе — в той же валюте, что и подарок.
  ///
  /// Цену называет сервер, читая её из каталога lava.top: в сборках с сайта
  /// магазина нет, и до этого человек узнавал сумму только на странице оплаты.
  /// Оттуда же приезжает распродажа, если её включили в кабинете.
  final double plusPrice;
  final double plusBasePrice;
  final int plusDiscount;

  factory PlusGiftOffer.fromJson(Map<String, dynamic> json) {
    if (json['ok'] != true) return none;
    final list = <GiftRecipient>[];
    final raw = json['partners'];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final parsed = GiftRecipient.fromJson(item.cast<String, dynamic>());
        if (parsed != null) list.add(parsed);
      }
    }
    final price = (json['price'] as num?)?.toDouble() ?? 0;
    final base = (json['basePrice'] as num?)?.toDouble() ?? 0;
    var discount = (json['discount'] as num?)?.toInt() ?? 0;
    if (discount < 0 || discount >= 100) discount = 0;
    final plusPrice = (json['plusPrice'] as num?)?.toDouble() ?? 0;
    final plusBase = (json['plusBasePrice'] as num?)?.toDouble() ?? 0;
    var plusDiscount = (json['plusDiscount'] as num?)?.toInt() ?? 0;
    if (plusDiscount < 0 || plusDiscount >= 100) plusDiscount = 0;
    return PlusGiftOffer(
      enabled: json['enabled'] != false,
      recipients: List.unmodifiable(list),
      currency: (json['currency'] as String? ?? 'RUB').toUpperCase(),
      price: price,
      basePrice: base < price ? price : base,
      discount: discount,
      plusPrice: plusPrice,
      plusBasePrice: plusBase < plusPrice ? plusPrice : plusBase,
      plusDiscount: plusDiscount,
    );
  }

  /// Показывать ли карточку подарка вообще.
  ///
  /// Одного «включено на сервере» мало: дарить некому — карточка предлагала бы
  /// действие, которое ничем не кончится.
  bool get visible => enabled && recipients.isNotEmpty;

  /// Есть ли хоть один, кому подарок ещё нужен.
  bool get hasAnyoneToGift =>
      recipients.any((r) => !r.alreadyHasPlus);

  /// Кому предложить первым: первый без Плюса, иначе первый в списке.
  GiftRecipient? get suggested {
    for (final r in recipients) {
      if (!r.alreadyHasPlus) return r;
    }
    return recipients.isEmpty ? null : recipients.first;
  }

  /// Цена подарка строкой; пусто — сервер цены не назвал.
  String get priceLabel => formatMoney(price, currency);

  /// Зачёркнутая цена рядом со скидкой. Пусто, когда скидки нет.
  String get baseLabel =>
      discount > 0 && basePrice > price ? formatMoney(basePrice, currency) : '';

  /// Цена самого Togetherly+ строкой — для кнопки «Купить».
  String get plusPriceLabel => formatMoney(plusPrice, currency);

  /// Зачёркнутая цена Плюса, когда идёт распродажа.
  String get plusBaseLabel => plusDiscount > 0 && plusBasePrice > plusPrice
      ? formatMoney(plusBasePrice, currency)
      : '';
}

/// Деньги для витрины: «720 ₽», «8 $», «7,50 €».
///
/// Копейки показываем ТОЛЬКО когда они есть: цена Плюса в рублях круглая
/// (900 ₽), а после скидки бывает и 719,4 — округление вверх врало бы о сумме,
/// которую человек увидит на странице оплаты.
String formatMoney(double value, String currency) {
  if (value <= 0) return '';
  final rounded = (value * 100).round() / 100;
  final whole = (rounded - rounded.roundToDouble()).abs() < 0.005;
  final number = whole
      ? rounded.round().toString()
      : rounded.toStringAsFixed(2).replaceAll('.', ',');
  switch (currency.toUpperCase()) {
    case 'USD':
      return '$number \$';
    case 'EUR':
      return '$number €';
    default:
      return '$number ₽';
  }
}
