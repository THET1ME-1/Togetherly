import 'package:pocketbase/pocketbase.dart';

import 'wish_category.dart';

/// Общее желание пары: фильм, который ждут, место, куда хотят, или что-то своё.
///
/// Запись одна на двоих и живёт в группе, поэтому отметить сбывшимся может
/// любой из пары — [doneBy] помнит, кто это сделал. Править и удалять
/// оставлено автору: чужую запись легко снести по ошибке, а восстановить её
/// неоткуда.
class Wish {
  const Wish({
    required this.id,
    required this.title,
    this.note = '',
    this.categoryId = 'other',
    this.symbol = '',
    this.authorUid = '',
    this.done = false,
    this.doneAt,
    this.doneBy = '',
    this.doneNote = '',
    this.isItem = false,
    this.price = 0,
    this.currency = '',
    this.url = '',
    this.image = '',
    this.shop = '',
    required this.createdAt,
  });

  final String id;
  final String title;

  /// Необязательное уточнение: «только IMAX», «когда зацветёт сакура».
  final String note;

  /// Встроенный ключ (`movie`, `food`, …) или id своей категории пары.
  final String categoryId;

  /// Значок Material Symbols, снятый в момент создания.
  ///
  /// Хранится прямо в желании, а не берётся из категории: карточка на главной
  /// и список рисуются раньше, чем догрузятся свои категории, а удалённая
  /// категория иначе оставила бы желание без значка вовсе.
  final String symbol;

  /// Кто добавил.
  final String authorUid;

  final bool done;

  /// Когда сбылось. Пусто, пока желание в «мечтаем».
  final DateTime? doneAt;

  /// Кто отметил. Не обязательно автор — в этом и смысл общего списка.
  final String doneBy;

  /// Заметка «как прошло», её предлагают в снекбаре сразу после отметки.
  final String doneNote;

  // ── Вещь, а не дело ──
  /// Желание-товар: у него есть картинка, цена и ссылка на магазин. Дела
  /// («сходить в горы») и вещи («эта куртка») живут в одном списке: пара так их
  /// и держит в голове, а два раздельных экрана заставляли бы выбирать, куда
  /// класть «билеты на концерт».
  final bool isItem;

  /// Цена в целых единицах валюты. 0 — не указана.
  final int price;

  /// Код валюты как показываем: `₽`, `$`, `€`.
  final String currency;

  /// Ссылка на товар.
  final String url;

  /// Картинка: `pb://media/...` или прямая ссылка из карточки магазина.
  final String image;

  /// Название магазина из ссылки — подпись под ценой.
  final String shop;

  bool get hasPrice => price > 0;

  /// Цена как в карточке: «12 990 ₽».
  String get priceLabel {
    if (price <= 0) return '';
    final digits = price.toString();
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write('\u00A0');
      buf.write(digits[i]);
    }
    return currency.isEmpty ? buf.toString() : '$buf\u00A0$currency';
  }

  final DateTime createdAt;

  /// Значок для отрисовки: свой, а если его нет (записи первых сборок) —
  /// значок встроенной категории.
  String get iconName {
    if (symbol.isNotEmpty) return symbol;
    return builtinWishKind(categoryId)?.symbol ?? 'star';
  }

  /// Мечты: сверху то, что задумали недавно.
  static List<Wish> dreaming(Iterable<Wish> all) {
    final list = all.where((w) => !w.done).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// Сбывшееся: сверху последнее. У записей, приехавших из старых версий,
  /// даты отметки может не быть — они уходят вниз, а не роняют сортировку.
  static List<Wish> fulfilled(Iterable<Wish> all) {
    final list = all.where((w) => w.done).toList();
    list.sort((a, b) {
      final ad = a.doneAt, bd = b.doneAt;
      if (ad == null && bd == null) return b.createdAt.compareTo(a.createdAt);
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });
    return list;
  }

  static DateTime? _date(Object? raw) {
    if (raw is DateTime) return raw;
    final s = raw?.toString() ?? '';
    if (s.isEmpty) return null;
    return DateTime.tryParse(s)?.toLocal();
  }

  factory Wish.fromPb(RecordModel rec) => Wish(
        id: rec.id,
        title: rec.getStringValue('title'),
        note: rec.getStringValue('note'),
        categoryId: rec.getStringValue('category').isEmpty
            ? 'other'
            : rec.getStringValue('category'),
        symbol: rec.getStringValue('symbol'),
        authorUid: rec.getStringValue('author_uid'),
        done: rec.getBoolValue('done'),
        doneAt: _date(rec.getStringValue('done_at')),
        doneBy: rec.getStringValue('done_by'),
        doneNote: rec.getStringValue('done_note'),
        isItem: rec.getStringValue('kind') == 'item',
        price: rec.getIntValue('price'),
        currency: rec.getStringValue('currency'),
        url: rec.getStringValue('url'),
        image: rec.getStringValue('image'),
        shop: rec.getStringValue('shop'),
        createdAt: _date(rec.getStringValue('created')) ?? DateTime.now(),
      );

  factory Wish.fromMap(Map<String, dynamic> map) => Wish(
        id: (map['id'] ?? '') as String,
        title: (map['title'] ?? '') as String,
        note: (map['note'] ?? '') as String,
        categoryId: ((map['category'] ?? '') as String).isEmpty
            ? 'other'
            : map['category'] as String,
        symbol: (map['symbol'] ?? '') as String,
        authorUid: (map['author_uid'] ?? '') as String,
        done: (map['done'] as bool?) ?? false,
        doneAt: _date(map['done_at']),
        doneBy: (map['done_by'] ?? '') as String,
        doneNote: (map['done_note'] ?? '') as String,
        isItem: (map['kind'] ?? '') == 'item',
        price: (map['price'] as num?)?.toInt() ?? 0,
        currency: (map['currency'] ?? '') as String,
        url: (map['url'] ?? '') as String,
        image: (map['image'] ?? '') as String,
        shop: (map['shop'] ?? '') as String,
        createdAt: _date(map['created']) ?? DateTime.now(),
      );

  Map<String, dynamic> toMap({required String groupId}) => {
        'id': id,
        'group_id': groupId,
        'author_uid': authorUid,
        'title': title,
        if (note.isNotEmpty) 'note': note,
        'category': categoryId,
        if (symbol.isNotEmpty) 'symbol': symbol,
        'done': done,
        if (doneAt != null) 'done_at': doneAt!.toIso8601String(),
        if (doneBy.isNotEmpty) 'done_by': doneBy,
        if (doneNote.isNotEmpty) 'done_note': doneNote,
        'kind': isItem ? 'item' : 'deed',
        if (price > 0) 'price': price,
        if (currency.isNotEmpty) 'currency': currency,
        if (url.isNotEmpty) 'url': url,
        if (image.isNotEmpty) 'image': image,
        if (shop.isNotEmpty) 'shop': shop,
        'created': createdAt.toIso8601String(),
      };

  Wish copyWith({
    String? title,
    String? note,
    String? categoryId,
    String? symbol,
    bool? done,
    DateTime? doneAt,
    String? doneBy,
    String? doneNote,
    bool? isItem,
    int? price,
    String? currency,
    String? url,
    String? image,
    String? shop,
  }) =>
      Wish(
        id: id,
        title: title ?? this.title,
        note: note ?? this.note,
        categoryId: categoryId ?? this.categoryId,
        symbol: symbol ?? this.symbol,
        authorUid: authorUid,
        done: done ?? this.done,
        doneAt: doneAt ?? this.doneAt,
        doneBy: doneBy ?? this.doneBy,
        doneNote: doneNote ?? this.doneNote,
        isItem: isItem ?? this.isItem,
        price: price ?? this.price,
        currency: currency ?? this.currency,
        url: url ?? this.url,
        image: image ?? this.image,
        shop: shop ?? this.shop,
        createdAt: createdAt,
      );

  Wish markDone({required String by, DateTime? at}) => copyWith(
        done: true,
        doneAt: at ?? DateTime.now(),
        doneBy: by,
      );

  /// Промах по чекбоксу отменяют кнопкой в снекбаре — след отметки стирается
  /// целиком, иначе в архиве останется чужое имя и дата.
  Wish undone() => Wish(
        id: id,
        title: title,
        note: note,
        categoryId: categoryId,
        symbol: symbol,
        authorUid: authorUid,
        done: false,
        doneAt: null,
        doneBy: '',
        doneNote: '',
        createdAt: createdAt,
      );
}
