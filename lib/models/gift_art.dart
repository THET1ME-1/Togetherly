/// Картинки подарка из серверного каталога (`catalog_items`, вид `gift`).
///
/// Цена, действие и тексты подарка живут в [Gift]; сервер отдаёт только
/// рисунок: анимацию двух размеров и неподвижный кадр. Поэтому перерисованный
/// подарок доезжает до людей без обновления приложения, а без сети остаётся
/// неподвижный кадр из сборки.
class GiftArt {
  const GiftArt({required this.key, this.price, this.smUrl, this.lgUrl, this.stillUrl});

  final String key;

  /// Цена в монетах из каталога; null — берётся зашитая в сборку.
  final int? price;
  final String? smUrl;
  final String? lgUrl;
  final String? stillUrl;

  /// До 64 точек хватает маленькой анимации, крупнее — большая.
  String? urlFor(double logicalSize, {bool animated = true}) {
    if (!animated) return stillUrl ?? smUrl ?? lgUrl;
    return logicalSize <= 64 ? (smUrl ?? lgUrl ?? stillUrl) : (lgUrl ?? smUrl ?? stillUrl);
  }

  /// Строка каталога → картинки. Чужой вид, выключенная запись, пустой ключ
  /// или ни одной ссылки — null: кривая запись не должна ломать магазин.
  static GiftArt? fromCatalog(Map<String, dynamic> row) {
    if (row['kind'] != 'gift' || row['enabled'] == false) return null;
    final data = row['data'];
    if (data is! Map) return null;
    final key = '${data['key'] ?? ''}'.trim();
    if (key.isEmpty) return null;
    String? url(String k) {
      final v = data[k];
      return v is String && v.isNotEmpty ? v : null;
    }

    final p = row['price'];
    final art = GiftArt(key: key, price: p is num && p > 0 ? p.toInt() : null, smUrl: url('sm'), lgUrl: url('lg'), stillUrl: url('still'));
    if (art.smUrl == null && art.lgUrl == null && art.stillUrl == null) return null;
    return art;
  }
}
