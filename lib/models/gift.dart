import '../l10n/zh/gifts.dart';
import '../services/catalog_service.dart';
import '../services/locale_service.dart';

/// Движок подарка — что подарок делает, когда долетел до партнёра.
///
/// Пока реализован один: подарок приходит мгновенно, живёт сутки и просит
/// ответа. Ответил — часть монет возвращается дарителю, поэтому дарение
/// работает как обмен, а не как трата. Остальные движки (ждёт действия,
/// меняет приложение, зовёт вместе, копится, насовсем) — следующие фазы.
enum GiftEngine { response }

/// Что получатель делает с подарком. Действие определяет и анимацию, и текст
/// подсказки, и то, чем считается «ответ» — задутой свечой или простым тапом.
enum GiftAction {
  /// Просто нажать в ответ.
  tap,

  /// Задуть свечу: подарок ждёт, пока пламя не погаснет.
  blow,

  /// Открыть коробку — внутри записка от дарителя.
  open,

  /// Разломить печенье и прочитать предсказание.
  crack,

  /// Поймать: значок убегает по экрану.
  catchIt,

  /// Полить: без внимания подарок вянет раньше срока.
  water,

  /// Принять двойным касанием — как лайк в переписке.
  doubleTap,

  /// Обнять в ответ: успел за минуту — бонус обоим.
  hugBack,

  /// Загадать желание и отправить его текстом дарителю.
  wish,

  /// Салют: разворачивается сразу, без ожидания действия.
  blast,

  /// Срочный зов: уведомление проходит поверх тихого режима.
  urgent,

  /// Перевод монет партнёру.
  transfer,

  /// Приглашение: принял — открывается общий экран, отказался — монеты назад.
  invite,

  /// Бросок монетки: кому платить, кому идти.
  coinFlip,

  /// Чокнуться экранами.
  clink,

  /// Открыть партнёру секретные записи на сутки.
  unlock,

  /// Общий будильник на двоих.
  alarm,
}

/// Куда ведёт принятое приглашение.
enum GiftOpens { none, chat, callTimer, watchTogether, map, addPhoto, calendar }

/// Подсказка получателю на русском. Английский текст живёт в [actionHintEn].
String actionHintRu(GiftAction action) => switch (action) {
      GiftAction.doubleTap => 'Коснись дважды',
      GiftAction.hugBack => 'Обними в ответ',
      GiftAction.wish => 'Загадай желание',
      GiftAction.blast => 'Смотри салют',
      GiftAction.urgent => 'Ответь скорее',
      GiftAction.transfer => 'Забери монеты',
      GiftAction.invite => 'Принимаешь?',
      GiftAction.coinFlip => 'Бросай монетку',
      GiftAction.clink => 'Чокнись экраном',
      GiftAction.unlock => 'Забери ключ',
      GiftAction.alarm => 'Ставим будильник',
      GiftAction.blow => 'Задуй свечу',
      GiftAction.open => 'Открой коробку',
      GiftAction.crack => 'Разломи печенье',
      GiftAction.catchIt => 'Поймай зайчика',
      GiftAction.water => 'Полей букет',
      GiftAction.tap => 'Нажми в ответ',
    };

String actionHintEn(GiftAction action) => switch (action) {
      GiftAction.doubleTap => 'Double tap',
      GiftAction.hugBack => 'Hug back',
      GiftAction.wish => 'Make a wish',
      GiftAction.blast => 'Enjoy the fireworks',
      GiftAction.urgent => 'Answer soon',
      GiftAction.transfer => 'Take the coins',
      GiftAction.invite => 'Accept?',
      GiftAction.coinFlip => 'Flip the coin',
      GiftAction.clink => 'Clink screens',
      GiftAction.unlock => 'Take the key',
      GiftAction.alarm => 'Set the alarm',
      GiftAction.blow => 'Blow out the candle',
      GiftAction.open => 'Open the box',
      GiftAction.crack => 'Crack it open',
      GiftAction.catchIt => 'Catch the bunny',
      GiftAction.water => 'Water the flowers',
      GiftAction.tap => 'Tap back',
    };

class Gift {
  const Gift({
    required this.key,
    required this.price,
    required this.engine,
    required this.titleRu,
    required this.titleEn,
    this.action = GiftAction.tap,
    this.carriesNote = true,
    this.carriesPhoto = false,
    this.wantsReply = false,
    this.keepsForever = false,
    this.transfersCoins = false,
    this.mutualBonus = 0,
    this.opens = GiftOpens.none,
    this.refundsOnDecline = false,
    this.deliverAfter,
    this.deliversAtMorning = false,
    this.carriesDate = false,
    this.carriesPlace = false,
    this.piercesQuietHours = false,
    this.writesToFeed = false,
    this.life = const Duration(hours: 24),
  });

  /// Совпадает с ключом в серверной прайс-таблице (`pb_hooks/gifts.pb.js`).
  final String key;

  /// Цена для витрины. Списывает сервер по своей таблице — клиентскому числу
  /// тут никто не верит.
  final int price;

  final GiftEngine engine;

  /// Названия хранятся здесь, а не в [LocaleService]: тридцать четыре подарка
  /// дали бы шестьдесят восемь геттеров, которые правятся всегда вместе с
  /// каталогом. Общие строки экрана остались в локали.
  final String titleRu;
  final String titleEn;

  /// Что делает получатель, чтобы подарок «сработал».
  final GiftAction action;

  /// Даритель может вложить текст: записку, предсказание, письмо, посвящение.
  /// С 08.10.2026 подпись есть у любого подарка (обращение 244), поэтому по
  /// умолчанию true; сервер хранит `note` у всех ключей одинаково.
  final bool carriesNote;

  /// Даритель может приложить свой снимок. Просьба из поддержки (обращение
  /// 20, 07.09.2026): «Кадр» просил фото у партнёра, а приложить своё было
  /// нельзя, хотя к «Песне» текст прикладывается.
  final bool carriesPhoto;

  /// Получатель пишет ответ, и он возвращается дарителю (желание на звезду).
  final bool wantsReply;

  /// Не расходуется, а остаётся в профиле пары навсегда. Видят только двое.
  final bool keepsForever;

  /// Цена уходит не в никуда, а на баланс партнёра.
  final bool transfersCoins;

  /// Можно ли подарить за рекламу. Копилке нельзя: она передаёт партнёру свою
  /// цену, а у подарка за рекламу цена нулевая. Зеркало `NO_AD` в
  /// `gifts.pb.js`, расхождение ловит `gift_catalog_test.dart`.
  bool get giftableByAd => !transfersCoins;

  /// Монет обоим, если ответ пришёл в первую минуту.
  final int mutualBonus;

  /// Какой экран открыть, когда приглашение принято.
  final GiftOpens opens;

  /// Отказ возвращает дарителю всю цену: иначе звать страшно.
  final bool refundsOnDecline;

  /// Подарок доходит не сразу, а спустя это время.
  final Duration? deliverAfter;

  /// Подарок доходит к восьми утра — завтрак не будят ночью.
  final bool deliversAtMorning;

  /// Даритель выбирает дату: до неё пойдёт обратный отсчёт.
  final bool carriesDate;

  /// Подарок несёт место отправителя — след на карте.
  final bool carriesPlace;

  /// Уведомление проходит даже сквозь подаренную тихую ночь.
  final bool piercesQuietHours;

  /// Оставляет запись в общей ленте пары.
  final bool writesToFeed;

  /// Сколько подарок ждёт отклика, прежде чем истечёт.
  final Duration life;

  String get asset => 'assets/images/gifts/$key.webp';

  /// Цена, которую сейчас спишет сервер: из каталога, иначе зашитая [price].
  int get currentPrice => CatalogService.instance.giftArt(key)?.price ?? price;

  String get title => switch (LocaleService.instance.language) {
        AppLanguage.ru => titleRu,
        AppLanguage.zh => kGiftTitlesZh[key] ?? titleEn,
        _ => titleEn,
      };
}

class GiftCatalog {
  const GiftCatalog._();

  /// Порядок = порядок на витрине: от дешёвых повседневных к дорогим событиям.
  static const List<Gift> all = [
    // Каждый день — 10-15 монет, покрываются дневным бонусом
    Gift(key: 'heart', price: 10, engine: GiftEngine.response, titleRu: 'Сердце', titleEn: 'Heart',
        action: GiftAction.doubleTap),
    Gift(key: 'star', price: 10, engine: GiftEngine.response, titleRu: 'Звезда', titleEn: 'Star',
        action: GiftAction.wish, wantsReply: true),
    Gift(key: 'fire', price: 10, engine: GiftEngine.response, titleRu: 'Огонёк', titleEn: 'Spark'),
    Gift(key: 'sun', price: 10, engine: GiftEngine.response, titleRu: 'Солнце', titleEn: 'Sun'),
    Gift(key: 'hug', price: 15, engine: GiftEngine.response, titleRu: 'Обнимашка', titleEn: 'Hug',
        action: GiftAction.hugBack, mutualBonus: 5),
    Gift(key: 'night', price: 15, engine: GiftEngine.response, titleRu: 'Сладких снов', titleEn: 'Good night'),
    Gift(key: 'cookie', price: 15, engine: GiftEngine.response, titleRu: 'Печенье', titleEn: 'Cookie',
        action: GiftAction.crack, carriesNote: true),
    Gift(key: 'bunny', price: 15, engine: GiftEngine.response, titleRu: 'Зайчик', titleEn: 'Bunny',
        action: GiftAction.catchIt),
    Gift(key: 'paw', price: 15, engine: GiftEngine.response, titleRu: 'Лапка', titleEn: 'Paw', carriesPlace: true),
    Gift(key: 'spa', price: 15, engine: GiftEngine.response, titleRu: 'Отдых', titleEn: 'Spa'),

    // По поводу — 20-30 монет
    Gift(key: 'coffee', price: 20, engine: GiftEngine.response, titleRu: 'Кофе', titleEn: 'Coffee',
        action: GiftAction.invite, opens: GiftOpens.callTimer, refundsOnDecline: true),
    Gift(key: 'tea', price: 20, engine: GiftEngine.response, titleRu: 'Чай', titleEn: 'Tea',
        action: GiftAction.invite, opens: GiftOpens.chat, refundsOnDecline: true),
    Gift(key: 'croissant', price: 20, engine: GiftEngine.response, titleRu: 'Завтрак', titleEn: 'Breakfast',
        carriesNote: true, deliversAtMorning: true),
    Gift(key: 'pizza', price: 20, engine: GiftEngine.response, titleRu: 'Пицца', titleEn: 'Pizza', action: GiftAction.coinFlip),
    Gift(key: 'wine', price: 20, engine: GiftEngine.response, titleRu: 'Бокал', titleEn: 'Wine', action: GiftAction.clink),
    Gift(key: 'cocktail', price: 20, engine: GiftEngine.response, titleRu: 'Коктейль', titleEn: 'Cocktail',
        action: GiftAction.invite, opens: GiftOpens.chat, refundsOnDecline: true,
        carriesNote: true),
    Gift(key: 'song', price: 20, engine: GiftEngine.response, titleRu: 'Песня', titleEn: 'Song', carriesNote: true),
    Gift(key: 'photo', price: 20, engine: GiftEngine.response, titleRu: 'Кадр', titleEn: 'Photo',
        action: GiftAction.invite, opens: GiftOpens.addPhoto, refundsOnDecline: true,
        carriesPhoto: true),
    Gift(key: 'piggy', price: 20, engine: GiftEngine.response, titleRu: 'Копилка', titleEn: 'Piggy bank',
        action: GiftAction.transfer, transfersCoins: true),
    Gift(key: 'bouquet', price: 25, engine: GiftEngine.response, titleRu: 'Букет', titleEn: 'Bouquet',
        action: GiftAction.water, life: Duration(days: 3)),
    Gift(key: 'park', price: 25, engine: GiftEngine.response, titleRu: 'Прогулка', titleEn: 'Walk',
        action: GiftAction.invite, opens: GiftOpens.map, refundsOnDecline: true),
    Gift(key: 'ramen', price: 25, engine: GiftEngine.response, titleRu: 'Ужин вдвоём', titleEn: 'Dinner',
        action: GiftAction.invite, opens: GiftOpens.calendar, refundsOnDecline: true,
        carriesDate: true),
    Gift(key: 'bed', price: 25, engine: GiftEngine.response, titleRu: 'Сон', titleEn: 'Sleep', action: GiftAction.alarm),
    Gift(key: 'beach', price: 25, engine: GiftEngine.response, titleRu: 'Отпуск', titleEn: 'Vacation', carriesDate: true),
    Gift(key: 'giftbox', price: 30, engine: GiftEngine.response, titleRu: 'Коробка', titleEn: 'Gift box',
        action: GiftAction.open, carriesNote: true),
    Gift(key: 'letter', price: 30, engine: GiftEngine.response, titleRu: 'Письмо', titleEn: 'Letter',
        action: GiftAction.open, carriesNote: true,
        deliverAfter: Duration(hours: 24)),
    Gift(key: 'movie', price: 30, engine: GiftEngine.response, titleRu: 'Кино', titleEn: 'Movie',
        action: GiftAction.invite, opens: GiftOpens.watchTogether, refundsOnDecline: true),
    Gift(key: 'salute', price: 30, engine: GiftEngine.response, titleRu: 'Салют', titleEn: 'Fireworks',
        action: GiftAction.blast, writesToFeed: true),

    // Событие — 40-60 монет, за неделю бесплатно не накопить
    Gift(key: 'cake', price: 40, engine: GiftEngine.response, titleRu: 'Торт', titleEn: 'Cake',
        action: GiftAction.blow),
    Gift(key: 'flight', price: 40, engine: GiftEngine.response, titleRu: 'Билет', titleEn: 'Ticket', carriesDate: true),
    Gift(key: 'key', price: 40, engine: GiftEngine.response, titleRu: 'Ключик', titleEn: 'Key', action: GiftAction.unlock),
    Gift(key: 'medal', price: 50, engine: GiftEngine.response, titleRu: 'Медаль', titleEn: 'Medal',
        carriesNote: true, keepsForever: true),
    Gift(key: 'rocket', price: 50, engine: GiftEngine.response, titleRu: 'Ракета', titleEn: 'Rocket',
        action: GiftAction.urgent, piercesQuietHours: true),
    Gift(key: 'diamond', price: 60, engine: GiftEngine.response, titleRu: 'Кольцо', titleEn: 'Ring',
        carriesNote: true, keepsForever: true),
  ];

  /// Подарки сундука недели. В витрине их нет, купить или подарить их
  /// нельзя: они только выпадают из сундука и ложатся на полку. Сервер их
  /// ключей в прайсе `gifts.pb.js` не знает, а разыгрывает `chest.pb.js`.
  static const List<Gift> chest = [
    Gift(key: 'cookieheart', price: 0, engine: GiftEngine.response, titleRu: 'Печенье-сердечко', titleEn: 'Heart cookie'),
    Gift(key: 'teddy', price: 0, engine: GiftEngine.response, titleRu: 'Мишка', titleEn: 'Teddy bear'),
    Gift(key: 'potion', price: 0, engine: GiftEngine.response, titleRu: 'Любовное зелье', titleEn: 'Love potion'),
    Gift(key: 'throne', price: 0, engine: GiftEngine.response, titleRu: 'Царский трон', titleEn: 'Royal throne'),
    Gift(key: 'champagne', price: 0, engine: GiftEngine.response, titleRu: 'Шампанское', titleEn: 'Champagne'),
    Gift(key: 'snowglobe', price: 0, engine: GiftEngine.response, titleRu: 'Снежный шар', titleEn: 'Snow globe'),
    Gift(key: 'rose', price: 0, engine: GiftEngine.response, titleRu: 'Вечная роза', titleEn: 'Eternal rose'),
    Gift(key: 'perfume', price: 0, engine: GiftEngine.response, titleRu: 'Духи', titleEn: 'Perfume'),
    Gift(key: 'record', price: 0, engine: GiftEngine.response, titleRu: 'Пластинка', titleEn: 'Record'),
    Gift(key: 'locket', price: 0, engine: GiftEngine.response, titleRu: 'Медальон', titleEn: 'Locket'),
    Gift(key: 'rings', price: 0, engine: GiftEngine.response, titleRu: 'Парные кольца', titleEn: 'Matching rings'),
  ];

  /// Подарки сезонных сундуков: в коде их нет, их заводит сервер записью
  /// каталога с набором (`data.set`) — название берётся оттуда же. Как и
  /// подарки обычного сундука, они только выпадают и ложатся на полку.
  /// Список ставит [CatalogService] при разборе каталога.
  static Map<String, Gift> _seasonal = const {};

  static void registerSeasonal(Map<String, Gift> gifts) => _seasonal = Map.unmodifiable(gifts);

  static Gift? byKey(String key) {
    for (final g in all) {
      if (g.key == key) return g;
    }
    for (final g in chest) {
      if (g.key == key) return g;
    }
    return _seasonal[key];
  }
}
