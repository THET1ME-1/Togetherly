import 'dart:async';

import '../models/comment.dart';
import '../models/memory.dart';
import 'analytics_service.dart';
import 'level_service.dart';
import 'pb_auth_service.dart';
import 'pb_data_service.dart';
import 'pb_media_service.dart';
import 'pb_realtime_service.dart';
import 'pocketbase_service.dart';

/// Репозиторий «Воспоминаний» поверх PocketBase (миграция Firebase→PB, §3).
///
/// Доменная обёртка над [PbDataService] (CRUD) и [PbRealtimeService] (live SSE):
/// экраны работают с моделями [Memory]/[MemoryComment], а не с `RecordModel`.
/// Чтения на self-hosted PB БЕСПЛАТНЫ → лента целиком live, БЕЗ лимитов/пагинации
/// и ручных кнопок «обновить» (директива пользователя, memory
/// `togetherly_pb_realtime_no_limits`).
///
/// Медиа на §3 ещё грузятся вызывающим (Firebase Storage); §4 переведёт на
/// [PbMediaService]. Здесь мы лишь чистим уже-PB-ссылки (`pb://`) при удалении.
class MemoryRepository {
  MemoryRepository._();
  static final MemoryRepository instance = MemoryRepository._();
  factory MemoryRepository() => instance;

  final PbDataService _data = PbDataService();
  final PbRealtimeService _rt = PbRealtimeService();

  String? get _uid => PocketBaseService().userId;

  // ── Лента ────────────────────────────────────────────────────────────────
  /// Живая лента группы (новые сверху), soft-deleted скрыты.
  Stream<List<Memory>> watch(String groupId) =>
      _rt.watchMemories(groupId).map((recs) => recs.map(Memory.fromPb).toList());

  /// Точечное чтение пина (deep-link из чата), если его нет в live-списке.
  Future<Memory?> getById(String memoryId) async {
    final rec = await _data.loadMemoryById(memoryId);
    return rec == null ? null : Memory.fromPb(rec);
  }

  // ── Запись ───────────────────────────────────────────────────────────────
  /// Создаёт воспоминание (id генерит сервер). Медиа-URL уже загружены
  /// вызывающим. Возвращает модель с серверным id или null.
  Future<Memory?> add({
    required String groupId,
    required String authorName,
    required String authorAvatar,
    required MemoryType type,
    String? imageUrl,
    List<String>? imageUrls,
    String? videoUrl,
    String? title,
    String? caption,
    String? locationName,
    double? latitude,
    double? longitude,
    String? musicTitle,
    String? musicArtist,
    String? musicUrl,
    String? musicCoverUrl,
    String? bookAuthor,
    String? bookCoverUrl,
    String? bookYear,
    String? bookPublisher,
    String? bookInfoUrl,
    String? movieOriginalTitle,
    String? moviePosterUrl,
    String? movieYear,
    String? movieKind,
    String? movieGenres,
    String? movieCountry,
    String? movieRatingKp,
    String? movieInfoUrl,
    int? rating,
    bool isAdult = false,
    DateTime? customDate,
  }) async {
    final uid = _uid;
    if (uid == null || groupId.isEmpty) return null;
    final draft = Memory(
      id: '',
      groupId: groupId,
      authorUid: uid,
      authorName: authorName,
      authorAvatar: authorAvatar,
      type: type,
      createdAt: customDate ?? DateTime.now(),
      imageUrl: imageUrl,
      imageUrls: imageUrls,
      videoUrl: videoUrl,
      title: title,
      caption: caption,
      locationName: locationName,
      latitude: latitude,
      longitude: longitude,
      musicTitle: musicTitle,
      musicArtist: musicArtist,
      musicUrl: musicUrl,
      musicCoverUrl: musicCoverUrl,
      bookAuthor: bookAuthor,
      bookCoverUrl: bookCoverUrl,
      bookYear: bookYear,
      bookPublisher: bookPublisher,
      bookInfoUrl: bookInfoUrl,
      movieOriginalTitle: movieOriginalTitle,
      moviePosterUrl: moviePosterUrl,
      movieYear: movieYear,
      movieKind: movieKind,
      movieGenres: movieGenres,
      movieCountry: movieCountry,
      movieRatingKp: movieRatingKp,
      movieInfoUrl: movieInfoUrl,
      // 0 = «без оценки» (как в update()): нормализуем в null, чтобы оба пути
      // записи трактовали 0 одинаково.
      rating: rating == 0 ? null : rating,
      isAdult: isAdult,
    );
    final rec = await _data.createMemory(groupId, draft.toJson());
    if (rec == null) return null;
    unawaited(_data.incrementGroupCounter(groupId, 'memories_count', 1));
    // Паритет с прежним FirebaseService.addMemory: начисляем XP паре за действие
    // и логируем аналитику (Analytics остаётся на Firebase до §7).
    unawaited(LevelService.instance.award(XpAction.addMemory));
    unawaited(AnalyticsService.instance.logMemoryAdded(type: type.name));
    return Memory.fromPb(rec);
  }

  /// Частичное редактирование (RMW по json-полю `data`): читаем текущую карту,
  /// меняем переданные поля, пишем целиком + синк индексированных колонок.
  Future<void> update({
    required String groupId,
    required String memoryId,
    String? title,
    String? caption,
    String? locationName,
    double? latitude,
    double? longitude,
    String? musicTitle,
    String? musicArtist,
    String? bookAuthor,
    int? rating,
    String? imageUrl,
    bool? isPinned,
    bool? isAdult,
    DateTime? customDate,
  }) async {
    final rec = await _data.loadMemoryById(memoryId);
    if (rec == null) return;
    final raw = rec.data['data'];
    final map =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    void put(String k, dynamic v) {
      if (v != null) map[k] = v;
    }

    put('title', title);
    put('caption', caption);
    put('locationName', locationName);
    put('latitude', latitude);
    put('longitude', longitude);
    put('musicTitle', musicTitle);
    put('musicArtist', musicArtist);
    put('bookAuthor', bookAuthor);
    if (rating != null) map['rating'] = rating == 0 ? null : rating;
    put('imageUrl', imageUrl);
    if (isPinned != null) map['isPinned'] = isPinned;
    if (isAdult != null) map['isAdult'] = isAdult;
    if (customDate != null) map['createdAt'] = customDate.toIso8601String();
    map['editedAt'] = DateTime.now().toIso8601String();
    await _data.upsertMemory(groupId, memoryId, map);
  }

  Future<void> togglePin({
    required String groupId,
    required String memoryId,
    required bool isPinned,
  }) =>
      update(groupId: groupId, memoryId: memoryId, isPinned: isPinned);

  /// Переключает закладку «Избранное» для ТЕКУЩЕГО пользователя (персонально).
  /// RMW по списку `savedBy` в json-поле `data`.
  Future<void> toggleSaved({
    required String groupId,
    required String memoryId,
  }) async {
    final uid = _uid;
    if (uid == null || uid.isEmpty) return;
    final rec = await _data.loadMemoryById(memoryId);
    if (rec == null) return;
    final raw = rec.data['data'];
    final map =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final saved = (map['savedBy'] is List)
        ? List<String>.from((map['savedBy'] as List).map((e) => e.toString()))
        : <String>[];
    if (saved.contains(uid)) {
      saved.remove(uid);
    } else {
      saved.add(uid);
    }
    map['savedBy'] = saved;
    await _data.upsertMemory(groupId, memoryId, map);
  }

  /// Удаляет воспоминание (hard) + связанные PB-медиа (`pb://`). Не-PB URL
  /// (Firebase http) на §3 не трогаем — чистка такого медиа уедет в §4.
  Future<void> delete({
    required String groupId,
    required String memoryId,
    String? imageUrl,
    String? videoUrl,
    String? musicUrl,
    String? musicCoverUrl,
  }) async {
    final media = PbMediaService();
    for (final url in [imageUrl, videoUrl, musicUrl, musicCoverUrl]) {
      if (url != null && media.isPbRef(url)) unawaited(media.delete(url));
    }
    final ok = await _data.deleteMemory(memoryId, hard: true);
    if (ok) {
      unawaited(_data.incrementGroupCounter(groupId, 'memories_count', -1));
    }
  }

  // ── Комментарии ──────────────────────────────────────────────────────────
  /// Живые комментарии воспоминания (старые сверху).
  Stream<List<MemoryComment>> watchComments(String memoryId) => _rt
      .watchComments(memoryId)
      .map((recs) => recs.map(MemoryComment.fromPb).toList());

  /// Добавляет комментарий. Имя/аватар автора по умолчанию берутся из профиля
  /// текущего пользователя PB ([PbAuthService.currentProfile]) — вызывающему не
  /// нужно их прокидывать.
  Future<void> addComment({
    required String groupId,
    required String memoryId,
    required String text,
    String? authorName,
    String? authorAvatar,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    final profile = PbAuthService().currentProfile();
    final name = authorName ?? (profile?['displayName'] as String? ?? '');
    await _data.createComment(groupId, memoryId, {
      'authorUid': uid,
      // Паритет с прежним поведением: пустое имя → плейсхолдер 'User'.
      'authorName': name.isNotEmpty ? name : 'User',
      'authorAvatar': authorAvatar ?? (profile?['avatarUrl'] as String? ?? ''),
      'text': text,
      'createdAt': DateTime.now().toIso8601String(),
    });
    // Кэш-счётчик комментов в самом воспоминании — для бейджа в ленте (чтобы не
    // держать SSE-подписку на комментарии каждой карточки). RMW по json `data`.
    try {
      final rec = await _data.loadMemoryById(memoryId);
      if (rec != null) {
        final raw = rec.data['data'];
        final map =
            raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
        map['commentsCount'] =
            ((map['commentsCount'] as num?)?.toInt() ?? 0) + 1;
        await _data.upsertMemory(groupId, memoryId, map);
      }
    } catch (_) {}
  }

  Future<void> deleteComment(String commentId) =>
      _data.deleteComment(commentId);
}
