import '../services/catalog_service.dart';
import '../services/locale_service.dart';

/// Рамка вокруг аватарки: выпадает из сундука (за монеты не продаётся),
/// надевается одна, и её видят все, у кого на экране есть твоя аватарка (ты
/// сам и партнёр).
///
/// Каталог СЕРВЕРНЫЙ: каждая рамка — запись `catalog_items` вида `frame` с id
/// `frame_<ключ>` (заливает `pocketbase/upload_badges.py` по папке с
/// `frame.json`, инструмент — `publish_frames.py` в мастерской значков). В
/// записи редкость, названия и подписи на семи языках, анимация двух размеров и
/// неподвижный кадр. Сундук (`chest.pb.js`) читает каталог при каждом
/// открытии, поэтому новая рамка сразу появляется и в магазине, и в розыгрыше
/// без обновления приложения.
///
/// В сборке лежат только неподвижные кадры первых рамок
/// (`assets/images/frames/<ключ>.webp`) — заглушка на случай, когда сети нет и
/// в кэше пусто. У рамок, заведённых позже, заглушкой служит скачанный
/// неподвижный кадр из дискового кэша.
///
/// [key] лежит у людей в `users.frame` и в ключе владения
/// `frame:frame_<ключ>` (`owned_features`), поэтому у существующей рамки не
/// меняется никогда.
class AvatarFrame {
  const AvatarFrame({
    required this.key,
    this.rarity = 'common',
    this.sort = 0,
    this.names = const {},
    this.descriptions = const {},
    this.smUrl,
    this.lgUrl,
    this.stillUrl,
    this.hole = avatarR,
    this.set = '',
  });

  final String key;

  /// Набор сезонного сундука (`data.set`, «13» — Хэллоуин); пусто — обычный.
  final String set;

  /// `common`, `rare` или `legendary` — от неё зависит доля в сундуке.
  final String rarity;
  final int sort;
  final Map<String, String> names;
  final Map<String, String> descriptions;

  /// Анимация 192 px — аватарки в списках и шапках.
  final String? smUrl;

  /// Анимация 384 px — крупная аватарка и лист покупки.
  final String? lgUrl;

  /// Неподвижный кадр 448 px.
  final String? stillUrl;

  /// Радиус фото под рамкой в единицах холста 0..100 (`data.hole`). Рисунок
  /// рамки частью лежит внутри круга [avatarR], и фото целиком уходило под неё
  /// на треть площади. Фото ужимается до [hole], и его край прячется под
  /// внутренний контур; место в раскладке аватарка занимает прежнее.
  final double hole;

  /// Радиус фото, под который считан [scale].
  static const double avatarR = 31;

  /// Во сколько раз ужать фото под этой рамкой.
  double get photoScale => hole / avatarR;

  /// Радиусы рамок из сборки — на случай, когда каталога ещё нет.
  static const Map<String, double> bundledHole = {
    'wreath': 26.5, 'cloud': 27, 'ribbon': 27.5, 'hearts': 31, 'daisies': 30.5,
    'cat': 30.5, 'lights': 31, 'donut': 28, 'clock': 27.5,
  };

  /// Масштаб фото под рамкой [key]: из каталога, иначе из сборки.
  static double photoScaleFor(String key) =>
      (byKey(key)?.hole ?? bundledHole[key] ?? avatarR) / avatarR;

  /// Картинка рамки больше самой аватарки: фото занимает круг радиуса 31 на
  /// холсте 100, рамка выступает за его край.
  static const double scale = 100 / 62;

  /// Ключи рамок, чей неподвижный кадр лежит в сборке.
  static const Set<String> bundled = {
    'wreath', 'cloud', 'ribbon', 'hearts', 'daisies',
    'cat', 'lights', 'donut', 'clock',
  };

  /// Заглушка из сборки или null, если рамка заведена позже сборки.
  static String? assetFor(String key) =>
      bundled.contains(key) ? 'assets/images/frames/$key.webp' : null;

  /// Id записи каталога.
  String get catalogId => catalogIdOf(key);
  static String catalogIdOf(String key) => 'frame_$key';

  /// Ключ владения в `owned_features`.
  String get featureKey => featureKeyOf(key);
  static String featureKeyOf(String key) => 'frame:${catalogIdOf(key)}';

  String get name => nameIn(LocaleService.instance.language.code);
  String get description => descriptionIn(LocaleService.instance.language.code);

  String nameIn(String lang) => _pick(names, lang) ?? key;
  String descriptionIn(String lang) => _pick(descriptions, lang) ?? '';

  static String? _pick(Map<String, String> m, String lang) {
    for (final l in [lang, 'en', 'ru']) {
      final v = m[l];
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  /// Адрес картинки под сторону РАМКИ на экране в логических точках.
  String? urlFor(double logicalSide, {bool animated = true}) {
    if (!animated) return stillUrl ?? smUrl ?? lgUrl;
    return logicalSide <= 110
        ? (smUrl ?? lgUrl ?? stillUrl)
        : (lgUrl ?? smUrl ?? stillUrl);
  }

  /// Рамка из строки каталога. Чужой вид, выключенная запись, пустой ключ
  /// или ни одной картинки — null: одна кривая строка, заведённая
  /// руками на сервере, не имеет права ронять магазин.
  static AvatarFrame? fromCatalog(Map<String, dynamic> row) {
    if (row['kind'] != 'frame') return null;
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
    final sort = row['sort'];
    final rawHole = data['hole'];
    final hole = rawHole is num ? rawHole.toDouble().clamp(18.0, avatarR) : (bundledHole[key] ?? avatarR);
    return AvatarFrame(
      key: key,
      rarity: '${data['rarity'] ?? 'common'}',
      sort: sort is num ? sort.toInt() : 0,
      names: strMap(data['name']),
      descriptions: strMap(data['desc']),
      smUrl: sm,
      lgUrl: lg,
      stillUrl: still,
      hole: hole,
      set: '${data['set'] ?? ''}',
    );
  }

  /// Все рамки из строк каталога, по полю `sort`.
  static List<AvatarFrame> parseCatalog(Iterable<Object?> rows) {
    final out = <AvatarFrame>[];
    for (final r in rows) {
      if (r is! Map) continue;
      final f = fromCatalog(r.cast<String, dynamic>());
      if (f != null) out.add(f);
    }
    out.sort((a, b) => a.sort.compareTo(b.sort));
    return out;
  }

  /// Все рамки, которые сейчас знает приложение (кэш или свежий каталог).
  static List<AvatarFrame> get all => CatalogService.instance.frames;

  static AvatarFrame? byKey(String? key) {
    if (key == null || key.isEmpty) return null;
    for (final f in all) {
      if (f.key == key) return f;
    }
    return null;
  }
}
