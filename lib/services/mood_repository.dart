import 'dart:async';

import '../models/mood_entry.dart';
import 'pb_data_service.dart';
import 'pb_realtime_service.dart';
import 'pocketbase_service.dart';

/// Репозиторий настроений (mood calendar) поверх PocketBase (миграция §3).
///
/// Доменная обёртка над [PbDataService] (CRUD) и [PbRealtimeService] (live SSE):
/// [MoodService] работает с моделями [MoodEntry], а не с `RecordModel`.
///
/// ВАЖНО: на self-hosted PB чтения БЕСПЛАТНЫ → плоская коллекция `mood_entries`
/// читается ЦЕЛИКОМ по (group, uid) live, без месячных документов, legacy-
/// fallback'а, одноразовой миграции и rollover-таймера, которые были нужны
/// ТОЛЬКО ради экономии чтений Firestore. Запись на ЛЮБУЮ дату появляется через
/// SSE сразу (старый live-слушатель покрывал лишь текущий месяц → нужен был
/// оптимистичный _applyLocalAdd; теперь не нужен).
class MoodRepository {
  MoodRepository._();
  static final MoodRepository instance = MoodRepository._();
  factory MoodRepository() => instance;

  final PbDataService _data = PbDataService();
  final PbRealtimeService _rt = PbRealtimeService();

  String? get _uid => PocketBaseService().userId;

  /// Живой список настроений [uid] в группе (новые сверху — сортировка в
  /// [PbRealtimeService.watchMoods] по timestamp DESC).
  Stream<List<MoodEntry>> watch(String groupId, String uid) =>
      _rt.watchMoods(groupId, uid).map((recs) => recs.map(MoodEntry.fromPb).toList());

  /// Разовая загрузка настроений [uid] (для нестриминговых путей при нужде).
  Future<List<MoodEntry>> load(String groupId, String uid) async {
    final recs = await _data.loadMoods(groupId, uid);
    return recs.map(MoodEntry.fromPb).toList();
  }

  /// Создаёт запись настроения (id генерит сервер). Личность — текущий PB-юзер.
  /// Возвращает модель с серверным id или null.
  Future<MoodEntry?> add({
    required String groupId,
    required String moodId,
    required String imagePath,
    required String label,
    required DateTime timestamp,
  }) async {
    final uid = _uid;
    if (uid == null || groupId.isEmpty) return null;
    final rec = await _data.createMood(groupId, uid, {
      'moodId': moodId,
      'imagePath': imagePath,
      'label': label,
      'timestamp': timestamp.toIso8601String(),
    });
    return rec == null ? null : MoodEntry.fromPb(rec);
  }

  /// Удаляет запись настроения по id (= id PB-записи из [MoodEntry.fromPb]).
  Future<void> delete(String entryId) => _data.deleteMood(entryId);
}
