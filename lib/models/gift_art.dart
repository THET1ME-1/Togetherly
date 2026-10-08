/// Картинки подарка из серверного каталога (`catalog_items`, вид `gift`).
/// Тем же видом записи живут и отдельные картинки интерфейса (`art`), например
/// монета TY: ключ `coin`. Тем же видом записи, но своим видом `ailment`,
/// лежат значки самочувствия (ключ — id из `Ailment`).
///
/// Цена, действие и тексты подарка живут в [Gift]; сервер отдаёт только
/// рисунок: анимацию двух размеров и неподвижный кадр. Поэтому перерисованный
/// подарок доезжает до людей без обновления приложения, а без сети остаётся
/// неподвижный кадр из сборки.
class GiftArt {
  const GiftArt({
    required this.key,
    this.price,
    this.smUrl,
    this.lgUrl,
    this.xlUrl,
    this.stillUrl,
    this.set = '',
    this.rarity = 'common',
    this.titleRu = '',
    this.titleEn = '',
  });

  final String key;

  /// Набор сезонного сундука (`data.set`); пусто — обычный подарок. Подарок
  /// набора в коде приложения не описан: название и редкость берутся отсюда.
  final String set;
  final String rarity;
  final String titleRu;
  final String titleEn;

  /// Цена в монетах из каталога; null — берётся зашитая в сборку.
  final int? price;
  final String? smUrl;
  final String? lgUrl;
  final String? stillUrl;

  /// Крупная анимация 720 px — есть не у всех; сейчас только у монеты для
  /// листа «монета TY».
  final String? xlUrl;

  /// До 64 точек хватает маленькой анимации, крупнее — большая.
  String? urlFor(double logicalSize, {bool animated = true}) {
    if (!animated) return stillUrl ?? smUrl ?? lgUrl;
    if (logicalSize > 160 && xlUrl != null) return xlUrl;
    return logicalSize <= 64 ? (smUrl ?? lgUrl ?? stillUrl) : (lgUrl ?? smUrl ?? stillUrl);
  }

  /// Строка каталога → картинки. Чужой вид, выключенная запись, пустой ключ
  /// или ни одной ссылки — null: кривая запись не должна ломать магазин.
  static GiftArt? fromCatalog(Map<String, dynamic> row) {
    final kind = row['kind'];
    if ((kind != 'gift' && kind != 'art' && kind != 'ailment') || row['enabled'] == false) return null;
    final data = row['data'];
    if (data is! Map) return null;
    final key = '${data['key'] ?? ''}'.trim();
    if (key.isEmpty) return null;
    String? url(String k) {
      final v = data[k];
      return v is String && v.isNotEmpty ? v : null;
    }

    final p = row['price'];
    final art = GiftArt(
      key: key,
      price: p is num && p > 0 ? p.toInt() : null,
      smUrl: url('sm'),
      lgUrl: url('lg'),
      xlUrl: url('xl'),
      stillUrl: url('still'),
      set: '${data['set'] ?? ''}',
      rarity: '${data['rarity'] ?? 'common'}',
      titleRu: '${row['name_ru'] ?? ''}',
      titleEn: '${row['name_en'] ?? ''}',
    );
    if (art.smUrl == null && art.lgUrl == null && art.stillUrl == null) return null;
    return art;
  }
}
