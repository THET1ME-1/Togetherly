/// Эмблема звания из каталога: запись вида `rank`, id `rank_<номер>`
/// (выкладывает `upload_badges.py` из мастерской значков, `export.py ranks`).
/// Холст тот же, что у значков: 176 точек, рисунок 144 в центре.
class RankArt {
  const RankArt({required this.index, this.smUrl, this.lgUrl, this.stillUrl});

  final int index;
  final String? smUrl;
  final String? lgUrl;
  final String? stillUrl;

  /// Как у значков: до 64 точек — маленькая анимация, крупнее — большая.
  String? urlFor(double logicalSize, {bool animated = true}) {
    if (!animated) return stillUrl ?? smUrl ?? lgUrl;
    return logicalSize <= 64
        ? (smUrl ?? lgUrl ?? stillUrl)
        : (lgUrl ?? smUrl ?? stillUrl);
  }

  /// Чужой вид, выключенная запись или ни одной картинки — null: одна кривая
  /// строка каталога не должна ронять лист званий.
  static RankArt? fromCatalog(Map<String, dynamic> row) {
    if (row['kind'] != 'rank' || row['enabled'] == false) return null;
    final data = row['data'];
    if (data is! Map) return null;
    final index = data['index'];
    final files = data['files'];
    if (index is! num || files is! Map) return null;
    String? url(String k) {
      final v = files[k];
      return v is String && v.isNotEmpty ? v : null;
    }

    final art = RankArt(
      index: index.toInt(),
      smUrl: url('sm'),
      lgUrl: url('lg'),
      stillUrl: url('still'),
    );
    return art.smUrl == null && art.lgUrl == null && art.stillUrl == null
        ? null
        : art;
  }
}
