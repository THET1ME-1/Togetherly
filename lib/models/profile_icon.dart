import '../services/catalog_service.dart';
import '../services/locale_service.dart';

/// Значок профиля, который человек покупает за монеты или получает наградой
/// и закрепляет рядом со своим именем.
///
/// Каталог СЕРВЕРНЫЙ: каждый значок — запись `catalog_items` вида `badge`
/// (заливает `pocketbase/upload_badges.py`), картинки — анимированный WebP двух
/// размеров и неподвижный кадр. Новый значок появляется у людей без
/// обновления приложения, цену при покупке сервер берёт из той же записи
/// (`/api/coins/purchase-icon`).
///
/// [id] — ключ значка (`Paw`, `Perfect Match`). Он лежит у людей в
/// `owned_icons`, `granted_badges` и `badge`, поэтому у существующего значка
/// не меняется никогда.
class ProfileIcon {
  const ProfileIcon({
    required this.id,
    required this.price,
    this.grantOnly = false,
    this.rarity = 'common',
    this.sort = 0,
    this.names = const {},
    this.descriptions = const {},
    this.smUrl,
    this.lgUrl,
    this.stillUrl,
  });

  final String id;

  /// Цена в монетах. 0 — не продаётся (наградной).
  final int price;

  /// Выдаётся только наградой (Sponsor, Helper, Fish): купить нельзя.
  final bool grantOnly;

  /// `common`, `rare`, `legendary` или `award`.
  final String rarity;
  final int sort;
  final Map<String, String> names;
  final Map<String, String> descriptions;

  /// Анимация 192 px — ник, списки, ячейки витрины.
  final String? smUrl;

  /// Анимация 384 px — лист покупки и крупный показ.
  final String? lgUrl;

  /// Неподвижный кадр — где анимация не нужна.
  final String? stillUrl;

  String get name => nameIn(LocaleService.instance.language.code);
  String get description => descriptionIn(LocaleService.instance.language.code);

  /// Название на языке [lang], иначе английское, иначе русское, иначе ключ.
  String nameIn(String lang) => _pick(names, lang) ?? id;
  String descriptionIn(String lang) => _pick(descriptions, lang) ?? '';

  static String? _pick(Map<String, String> m, String lang) {
    for (final l in [lang, 'en', 'ru']) {
      final v = m[l];
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  /// Адрес картинки под размер показа в логических точках. До 64 точек хватает
  /// маленькой анимации, крупнее — большая. Нужного размера нет — берём, какой есть.
  String? urlFor(double logicalSize, {bool animated = true}) {
    if (!animated) return stillUrl ?? smUrl ?? lgUrl;
    return logicalSize <= 64 ? (smUrl ?? lgUrl ?? stillUrl) : (lgUrl ?? smUrl ?? stillUrl);
  }

  /// Значок из строки каталога. Чужой вид, выключенная запись, пустой ключ или
  /// ни одной картинки — null: запись правят руками на сервере, и одна кривая
  /// строка не имеет права ронять витрину.
  static ProfileIcon? fromCatalog(Map<String, dynamic> row) {
    if (row['kind'] != 'badge') return null;
    if (row['enabled'] == false) return null;
    final data = row['data'];
    if (data is! Map) return null;
    final key = '${data['key'] ?? ''}'.trim();
    if (key.isEmpty) return null;
    String? url(String k) {
      final v = data[k];
      return v is String && v.isNotEmpty ? v : null;
    }

    final sm = url('sm'), lg = url('lg'), still = url('still');
    if (sm == null && lg == null && still == null) return null;
    Map<String, String> strMap(Object? v) => v is Map
        ? {for (final e in v.entries) '${e.key}': '${e.value}'}
        : const {};
    final grant = data['grantOnly'] == true;
    final price = row['price'];
    final sort = row['sort'];
    return ProfileIcon(
      id: key,
      price: grant ? 0 : (price is num ? price.toInt() : 0),
      grantOnly: grant,
      rarity: '${data['rarity'] ?? (grant ? 'award' : 'common')}',
      sort: sort is num ? sort.toInt() : 0,
      names: strMap(data['name']),
      descriptions: strMap(data['desc']),
      smUrl: sm,
      lgUrl: lg,
      stillUrl: still,
    );
  }

  /// Все значки из строк каталога, по полю `sort`.
  static List<ProfileIcon> parseCatalog(Iterable<Object?> rows) {
    final out = <ProfileIcon>[];
    for (final r in rows) {
      if (r is! Map) continue;
      final icon = fromCatalog(r.cast<String, dynamic>());
      if (icon != null) out.add(icon);
    }
    out.sort((a, b) => a.sort.compareTo(b.sort));
    return out;
  }

  // ── Каталог ────────────────────────────────────────────────────────────────

  /// Все значки, которые сейчас знает приложение (из кэша или свежего каталога).
  static List<ProfileIcon> get all => CatalogService.instance.badges;

  /// Значки, которые продаются (без наградных).
  static List<ProfileIcon> get purchasable =>
      all.where((i) => !i.grantOnly).toList(growable: false);

  /// Поиск по ключу. null — такого значка в каталоге нет (или он ещё не загружен).
  static ProfileIcon? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final icon in all) {
      if (icon.id == id) return icon;
    }
    return null;
  }
}
