import 'package:pocketbase/pocketbase.dart';
import 'mood_entry.dart';

/// Данные, которые пользователь делится через парный виджет.
///
/// Firestore path: `groups/{groupId}/widgetData/{uid}`
class WidgetData {
  final String uid;
  final String displayName;
  final String avatarUrl;

  // ── Слоты контента ──
  String status; // текстовый статус
  String moodEmoji; // путь к изображению emoji (из MoodOption)
  String moodLabel; // текстовая метка настроения
  String message; // короткое сообщение / love note
  String? photoUrl; // URL фотографии (для парного виджета)
  String? photoForPartnerUrl; // Фото, которое увидит партнёр в photo-widget
  List<String> photoForPartnerUrls; // Карусель фото для партнёра
  int photoGridCount; // 1, 2 или 4
  List<String> photoGridUrls; // URL фото для сетки
  String? musicTitle; // название песни
  String? musicArtist; // исполнитель
  String? musicUrl; // ссылка на трек
  String? musicCoverUrl; // обложка альбома
  String gender; // 'male' or 'female'
  DateTime? updatedAt;

  /// Куплен ли Togetherly+ у владельца карточки.
  ///
  /// Живёт здесь, а не в `users`: правила той коллекции пускают человека
  /// только к своей записи, и чужой флаг приложению не виден. В `widget_data`
  /// его проставляет сервер на каждом сохранении (`widget_plus.pb.js`),
  /// поэтому дорисовать себе значок нельзя.
  final bool plus;

  WidgetData({
    required this.uid,
    this.displayName = '',
    this.avatarUrl = '',
    this.status = '',
    this.moodEmoji = '',
    this.moodLabel = '',
    this.message = '',
    this.photoUrl,
    this.photoForPartnerUrl,
    this.photoForPartnerUrls = const [],
    this.photoGridCount = 1,
    this.photoGridUrls = const [],

    this.musicTitle,
    this.musicArtist,
    this.musicUrl,
    this.musicCoverUrl,
    this.gender = '',
    this.updatedAt,
    this.plus = false,
  });

  /// Есть ли хоть какой-то контент
  bool get isEmpty =>
      status.isEmpty &&
      moodEmoji.isEmpty &&
      message.isEmpty &&
      photoUrl == null &&
      musicTitle == null;

  bool get hasStatus => status.isNotEmpty;
  bool get hasMood => moodEmoji.isNotEmpty;
  bool get hasMessage => message.isNotEmpty;

  /// Метка настроения на текущем языке (берётся по imagePath из MoodOption).
  String get localizedMoodLabel {
    if (moodEmoji.isEmpty) return moodLabel;
    return MoodOption.byImagePath(moodEmoji)?.localizedLabel ?? moodLabel;
  }

  bool get hasPhoto => photoUrl != null && photoUrl!.isNotEmpty;
  bool get hasMusic => musicTitle != null && musicTitle!.isNotEmpty;

  /// PocketBase-запись (коллекция `widget_data`) → модель. Плоские snake_case
  /// колонки; uid = `user_uid`. Пустые text-поля PB отдаёт как `''` → nullable
  /// слоты (photo/music) коэрсим в null, чтобы `hasPhoto`/`hasMusic` не врали.
  factory WidgetData.fromPb(RecordModel rec) {
    final d = rec.data;
    String? nz(dynamic v) =>
        (v == null || (v is String && v.isEmpty)) ? null : v.toString();
    List<String> strList(dynamic v) =>
        v is List ? v.map((e) => e.toString()).toList() : const <String>[];
    return WidgetData(
      uid: (d['user_uid'] ?? '').toString(),
      displayName: (d['display_name'] ?? '').toString(),
      avatarUrl: (d['avatar_url'] ?? '').toString(),
      status: (d['status'] ?? '').toString(),
      moodEmoji: (d['mood_emoji'] ?? '').toString(),
      moodLabel: (d['mood_label'] ?? '').toString(),
      message: (d['message'] ?? '').toString(),
      photoUrl: nz(d['photo_url']),
      photoForPartnerUrl: nz(d['photo_for_partner_url']),
      photoForPartnerUrls: strList(d['photo_for_partner_urls']),
      photoGridCount: (d['photo_grid_count'] as num?)?.toInt() ?? 1,
      photoGridUrls: strList(d['photo_grid_urls']),
      musicTitle: nz(d['music_title']),
      musicArtist: nz(d['music_artist']),
      musicUrl: nz(d['music_url']),
      musicCoverUrl: nz(d['music_cover_url']),
      gender: (d['gender'] ?? '').toString(),
      updatedAt: DateTime.tryParse((d['updated_at'] ?? '').toString()),
      plus: d['plus'] == true || d['plus'] == 1,
    );
  }

  /// Карточка с применёнными полями записи — теми же camelCase-именами, что
  /// уходят в `upsertWidget`.
  ///
  /// Нужна ради одного шага: запись на сервер и обновление рабочего стола идут
  /// подряд, а локальная копия своих данных живёт на SSE-событии. Пока её не
  /// догоняли здесь, на виджет уезжал ПРЕЖНИЙ снимок, и новый появлялся только
  /// когда долетит событие — а оно долетает не всегда (оборванный сокет,
  /// убитый процесс). Жалоба звучала как «поставил фото, в приложении видно, в
  /// виджете нет» (01.09.2026).
  ///
  /// Незнакомые ключи молча пропускаем: карта полей растёт, и падать на новом
  /// имени тут нельзя — виджет важнее.
  WidgetData withFields(Map<String, dynamic> fields) {
    if (fields.isEmpty) return this;
    String str(String key, String fallback) {
      final v = fields[key];
      return v == null ? fallback : v.toString();
    }

    // null здесь значит «поле не пришло», а не «сотри»: `upsertWidget`
    // выбрасывает null-поля ради частичного апдейта, и локальная копия обязана
    // отвечать так же — иначе она разойдётся с записью на сервере. Убирают
    // поле пустой строкой (`clearMusic`, `clearPairPhotoFields`).
    String? nullable(String key, String? fallback) {
      final v = fields[key];
      return v == null ? fallback : v.toString();
    }

    List<String> list(String key, List<String> fallback) {
      final v = fields[key];
      if (v is! List) return fallback;
      return v.map((e) => e.toString()).toList();
    }

    return WidgetData(
      uid: uid,
      displayName: str('displayName', displayName),
      avatarUrl: str('avatarUrl', avatarUrl),
      status: str('status', status),
      moodEmoji: str('moodEmoji', moodEmoji),
      moodLabel: str('moodLabel', moodLabel),
      message: str('message', message),
      photoUrl: nullable('photoUrl', photoUrl),
      photoForPartnerUrl: nullable('photoForPartnerUrl', photoForPartnerUrl),
      photoForPartnerUrls: list('photoForPartnerUrls', photoForPartnerUrls),
      photoGridCount:
          (fields['photoGridCount'] as num?)?.toInt() ?? photoGridCount,
      photoGridUrls: list('photoGridUrls', photoGridUrls),
      musicTitle: nullable('musicTitle', musicTitle),
      musicArtist: nullable('musicArtist', musicArtist),
      musicUrl: nullable('musicUrl', musicUrl),
      musicCoverUrl: nullable('musicCoverUrl', musicCoverUrl),
      gender: str('gender', gender),
      updatedAt: DateTime.now(),
      plus: plus,
    );
  }

  WidgetData copyWith({
    String? uid,
    String? displayName,
    String? avatarUrl,
    String? status,
    String? moodEmoji,
    String? moodLabel,
    String? message,
    String? photoUrl,
    String? photoForPartnerUrl,
    List<String>? photoForPartnerUrls,
    String? musicTitle,
    String? musicArtist,
    String? musicUrl,
    String? musicCoverUrl,
    String? gender,
    int? photoGridCount,
    List<String>? photoGridUrls,
    DateTime? updatedAt,
  }) {
    return WidgetData(
      uid: uid ?? this.uid,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      status: status ?? this.status,
      moodEmoji: moodEmoji ?? this.moodEmoji,
      moodLabel: moodLabel ?? this.moodLabel,
      message: message ?? this.message,
      photoUrl: photoUrl ?? this.photoUrl,
      photoForPartnerUrl: photoForPartnerUrl ?? this.photoForPartnerUrl,
      photoForPartnerUrls:
          photoForPartnerUrls ?? this.photoForPartnerUrls,
      photoGridCount: photoGridCount ?? this.photoGridCount,
      photoGridUrls: photoGridUrls ?? this.photoGridUrls,
      musicTitle: musicTitle ?? this.musicTitle,
      musicArtist: musicArtist ?? this.musicArtist,
      musicUrl: musicUrl ?? this.musicUrl,
      musicCoverUrl: musicCoverUrl ?? this.musicCoverUrl,
      gender: gender ?? this.gender,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
