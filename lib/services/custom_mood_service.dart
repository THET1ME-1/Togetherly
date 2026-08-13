import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/custom_mood.dart';
import 'pb_realtime_service.dart';
import 'pocketbase_service.dart';

/// Свои настроения пары (Togetherly+).
///
/// Набор общий: завёл один — пользуются оба. Поэтому и поток, и правила
/// коллекции идут по группе, а не по автору; удалять и править может тот, кто
/// завёл.
///
/// Картинка лежит в самой записи открытым файлом — так же, как у каталожных
/// паков. Прятать её за сессией нельзя: адрес читают виджеты рабочего стола, а
/// там PocketBase-сессии нет вовсе.
class CustomMoodService {
  CustomMoodService._();
  static final CustomMoodService instance = CustomMoodService._();
  factory CustomMoodService() => instance;

  static const String collection = 'custom_moods';

  /// Сколько своих настроений держит пара. Предел не про место на диске, а про
  /// сетку выбора: дальше третьего десятка её перестаёт быть видно целиком.
  static const int limit = 24;

  final PbRealtimeService _rt = PbRealtimeService();

  /// Последний снимок — им пользуются экраны, которым поток не нужен (лист дня,
  /// виджеты), чтобы не поднимать вторую подписку ради одного чтения.
  List<CustomMood> _snapshot = const [];
  List<CustomMood> get snapshot => _snapshot;

  String _fileUrl(String recordId, String file) =>
      '${PocketBaseService().pb.baseURL}/api/files/$collection/$recordId/$file';

  /// Живой набор пары.
  Stream<List<CustomMood>> watch(String groupId) {
    if (groupId.isEmpty) return Stream.value(const []);
    return _rt.watchCustomMoods(groupId).map((recs) {
      final list = [
        for (final r in recs)
          CustomMood.fromMap({...r.data, 'id': r.id}, fileUrl: _fileUrl),
      ];
      _snapshot = list;
      return list;
    });
  }

  /// Разовая загрузка — для экранов без подписки.
  Future<List<CustomMood>> load(String groupId) async {
    if (groupId.isEmpty) return const [];
    try {
      final recs = await PocketBaseService().pb.collection(collection).getFullList(
            filter: PocketBaseService().pb.filter(
              'group_id = {:g}',
              {'g': groupId},
            ),
            sort: 'sort',
          );
      final list = [
        for (final r in recs)
          CustomMood.fromMap({...r.data, 'id': r.id}, fileUrl: _fileUrl),
      ];
      _snapshot = list;
      return list;
    } catch (e) {
      debugPrint('CustomMoodService: набор не загрузился — $e');
      return const [];
    }
  }

  /// Заводит своё настроение. [png] — готовая картинка 512×512: эмодзи,
  /// обрезанная фотография или рисунок, разницы для хранения нет.
  Future<CustomMood?> create({
    required String groupId,
    required String label,
    required int score,
    required Uint8List png,
    String emoji = '',
  }) async {
    final uid = PocketBaseService().userId ?? '';
    if (groupId.isEmpty || uid.isEmpty) return null;
    final moodId = CustomMood.newMoodId();
    try {
      final rec = await PocketBaseService().pb.collection(collection).create(
        body: {
          'group_id': groupId,
          'author_uid': uid,
          'mood_id': moodId,
          'label': label.trim(),
          'emoji': emoji,
          'score': CustomMood.clampScore(score),
          'sort': _snapshot.length,
        },
        files: [
          http.MultipartFile.fromBytes('image', png, filename: '$moodId.png'),
        ],
      ).timeout(const Duration(seconds: 60));
      return CustomMood.fromMap({...rec.data, 'id': rec.id}, fileUrl: _fileUrl);
    } catch (e) {
      debugPrint('CustomMoodService: настроение не завелось — $e');
      return null;
    }
  }

  /// Правит подпись и балл. Картинку не трогаем: чтобы её сменить, проще
  /// завести новое настроение — прежние отметки ссылаются на старый файл.
  Future<bool> rename({
    required String recordId,
    required String label,
    required int score,
  }) async {
    try {
      await PocketBaseService().pb.collection(collection).update(recordId, body: {
        'label': label.trim(),
        'score': CustomMood.clampScore(score),
      });
      return true;
    } catch (e) {
      debugPrint('CustomMoodService: правка не прошла — $e');
      return false;
    }
  }

  /// Убирает настроение из набора.
  ///
  /// Прошлые отметки этим не портятся: в самой отметке лежат и подпись, и
  /// адрес картинки, поэтому календарь и статистика остаются как были.
  Future<bool> remove(String recordId) async {
    try {
      await PocketBaseService().pb.collection(collection).delete(recordId);
      return true;
    } catch (e) {
      debugPrint('CustomMoodService: настроение не удалилось — $e');
      return false;
    }
  }
}
