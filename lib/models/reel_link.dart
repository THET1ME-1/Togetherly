/// Ролик совместной ленты как ссылка: куда она ведёт и что о нём рассказать.
///
/// Ключ ролика — «площадка:номер» (`reels.js`), номер без площадки читается
/// как Shorts: так шлют сборки до 04.10.2026. Те же адреса строит страница
/// (`watchUrl` в `reels.js`) — разъедутся, и «Отправить» с «Сохранить»
/// поведут в разные места.
library;

class ReelLink {
  const ReelLink(this.source, this.id);

  /// `shorts`, `tiktok`, `rutube`, `vk`, `dzen`.
  final String source;
  final String id;

  static const Set<String> sources = {'shorts', 'tiktok', 'rutube', 'vk', 'dzen'};

  /// null — ключ битый или площадка незнакомая.
  static ReelLink? parse(String key) {
    final k = key.trim();
    final at = k.indexOf(':');
    final source = at > 0 ? k.substring(0, at) : 'shorts';
    final id = at > 0 ? k.substring(at + 1) : k;
    if (!sources.contains(source)) return null;
    if (!RegExp(r'^-?[A-Za-z0-9_-]{6,80}$').hasMatch(id)) return null;
    if (source == 'vk' && id.split('_').length < 2) return null;
    return ReelLink(source, id);
  }

  String get key => '$source:$id';

  /// Адрес, который откроется у человека в браузере или в приложении площадки.
  String get url => switch (source) {
        'tiktok' => 'https://www.tiktok.com/@/video/$id',
        'rutube' => 'https://rutube.ru/shorts/$id/',
        'vk' => () {
            final p = id.split('_');
            return 'https://vk.com/clip${p[0]}_${p[1]}';
          }(),
        // У Дзена в ленте только номер видео, страницы публикации по нему
        // нет; плеер открывается и сам по себе.
        'dzen' => 'https://dzen.ru/embed/$id',
        _ => 'https://youtube.com/shorts/$id',
      };

  /// Обложка, которую можно назвать без запроса. У остальных её приносят
  /// данные площадки ([ReelMeta]) или её нет вовсе.
  String? get knownThumb => source == 'shorts' ? 'https://i.ytimg.com/vi/$id/hqdefault.jpg' : null;

  /// Где спросить название и автора. null — площадка этого не отдаёт.
  Uri? get metaUri => switch (source) {
        'shorts' => Uri.https('www.youtube.com', '/oembed', {'url': url, 'format': 'json'}),
        'tiktok' => Uri.https('www.tiktok.com', '/oembed', {'url': url}),
        'rutube' => Uri.https('rutube.ru', '/api/video/$id/', {'format': 'json'}),
        _ => null,
      };

  /// Подпись площадки в карточке воспоминания.
  String get platform => switch (source) {
        'tiktok' => 'TikTok',
        'rutube' => 'Rutube',
        'vk' => 'VK',
        'dzen' => 'Дзен',
        _ => 'YouTube',
      };
}

/// Название, автор и обложка ролика из ответа площадки.
class ReelMeta {
  const ReelMeta({this.title, this.author, this.thumb});

  final String? title;
  final String? author;
  final String? thumb;

  static const empty = ReelMeta();

  /// Ответ oEmbed (YouTube, TikTok) или `api/video` Rutube. Чужая форма ответа
  /// даёт пустые поля, а не исключение: ролик сохраняется и без них.
  factory ReelMeta.fromJson(Object? json) {
    if (json is! Map) return empty;
    String? str(Object? v) {
      final s = v is String ? v.trim() : '';
      return s.isEmpty ? null : s;
    }

    final author = json['author'];
    return ReelMeta(
      title: str(json['title']),
      author: str(json['author_name']) ?? (author is Map ? str(author['name']) : null),
      thumb: str(json['thumbnail_url']),
    );
  }
}
