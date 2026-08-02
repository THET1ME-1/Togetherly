import 'package:pocketbase/pocketbase.dart';

/// Категория желания: пять встроенных и сколько угодно своих.
///
/// Встроенные живут в коде и одинаковы у всех, свои заводит пара и хранит в
/// коллекции `wish_categories`. Отличаются только источником — экран работает
/// с ними одинаково, поэтому тип один.
class WishKind {
  const WishKind({
    required this.id,
    required this.symbol,
    this.titleRu = '',
    this.titleEn = '',
    this.note = '',
    this.custom = false,
    this.authorUid = '',
  });

  /// Для встроенной — ключ вроде `movie`, для своей — id записи в PB.
  final String id;

  /// Имя значка Material Symbols из подшитого шрифта.
  final String symbol;

  final String titleRu;
  final String titleEn;

  /// Примечание пары: зачем эта категория. Видно в списке категорий.
  final String note;

  final bool custom;
  final String authorUid;

  String title(bool ru) {
    if (custom) return titleRu;
    return ru ? titleRu : titleEn;
  }

  factory WishKind.fromPb(RecordModel rec) => WishKind(
        id: rec.id,
        symbol: rec.getStringValue('symbol').isEmpty
            ? 'star'
            : rec.getStringValue('symbol'),
        titleRu: rec.getStringValue('title'),
        titleEn: rec.getStringValue('title'),
        note: rec.getStringValue('note'),
        custom: true,
        authorUid: rec.getStringValue('author_uid'),
      );

  Map<String, dynamic> toMap({required String groupId}) => {
        'id': id,
        'group_id': groupId,
        'author_uid': authorUid,
        'title': titleRu,
        'symbol': symbol,
        if (note.isNotEmpty) 'note': note,
      };

  WishKind copyWith({String? title, String? symbol, String? note}) => WishKind(
        id: id,
        symbol: symbol ?? this.symbol,
        titleRu: title ?? titleRu,
        titleEn: title ?? titleEn,
        note: note ?? this.note,
        custom: custom,
        authorUid: authorUid,
      );
}

/// Пять встроенных категорий — тот же порядок, что в макете.
const List<WishKind> kBuiltinWishKinds = [
  WishKind(id: 'movie', symbol: 'movie', titleRu: 'Кино', titleEn: 'Movie'),
  WishKind(id: 'food', symbol: 'restaurant', titleRu: 'Еда', titleEn: 'Food'),
  WishKind(id: 'place', symbol: 'museum', titleRu: 'Место', titleEn: 'Place'),
  WishKind(id: 'trip', symbol: 'flight', titleRu: 'Поездка', titleEn: 'Trip'),
  WishKind(id: 'other', symbol: 'star', titleRu: 'Своё', titleEn: 'Other'),
];

/// Встроенная категория по ключу. null — ключа нет среди встроенных, значит
/// это своя категория пары (или запись от версии, которой у нас ещё нет).
WishKind? builtinWishKind(String? id) {
  for (final k in kBuiltinWishKinds) {
    if (k.id == id) return k;
  }
  return null;
}

/// Категория желания среди известных: сперва встроенные, потом свои.
///
/// Своя категория могла быть удалена, а желания с ней остаться — тогда
/// подставляем «Своё» с сохранённым значком, чтобы карточка не осталась пустой.
WishKind resolveWishKind({
  required String categoryId,
  required String symbol,
  required List<WishKind> custom,
}) {
  final builtin = builtinWishKind(categoryId);
  if (builtin != null) return builtin;
  for (final k in custom) {
    if (k.id == categoryId) return k;
  }
  final fallback = builtinWishKind('other')!;
  return symbol.isEmpty ? fallback : WishKind(
        id: fallback.id,
        symbol: symbol,
        titleRu: fallback.titleRu,
        titleEn: fallback.titleEn,
      );
}
