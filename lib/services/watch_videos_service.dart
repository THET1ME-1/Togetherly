import 'package:flutter/foundation.dart';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';
import 'package:video_compress/video_compress.dart';

import 'pocketbase_service.dart';

/// Своё видео пары: либо загруженное во вкладке «Смотрим», либо ролик из
/// ленты воспоминаний.
class WatchVideo {
  final String id;
  final String title;
  final String url;

  /// Обложка ролика (кадр из видео). Пусто → плитка покажет play на фоне.
  final String thumbUrl;
  final int seconds;

  /// true — файл лежит в защищённом хранилище воспоминаний: приложение его
  /// откроет, а партнёр в браузере нет, там нет сессии.
  final bool appOnly;

  const WatchVideo({
    required this.id,
    required this.title,
    required this.url,
    required this.seconds,
    this.thumbUrl = '',
    this.appOnly = false,
  });
}

/// Свои видео: пара загружает ролик в приложение и смотрит его вместе.
///
/// Файл лежит у нас, поэтому обоим он отдаётся обычной прямой ссылкой — это
/// самая точная синхронизация из возможных, секунда в секунду. Ссылка работает
/// без сессии: комнату на сайте открывает анонимный гость.
class WatchVideosService {
  WatchVideosService._();

  static const String _col = 'watch_videos';

  /// Потолок для бесплатной версии. Ограничение стоит и в базе.
  static const int maxBytes = 100 * 1024 * 1024;

  /// Потолок с Togetherly+. Больше базы не просим: сервер отвергнет.
  static const int maxBytesPlus = 300 * 1024 * 1024;

  /// Сколько живёт ролик совместного просмотра.
  ///
  /// Его заливают, чтобы посмотреть вдвоём в этот вечер, а не хранить. Раньше
  /// такие файлы лежали вечно и молча занимали диск, за который платят каждый
  /// месяц.
  static const Duration lifetime = Duration(days: 30);

  /// Действующий потолок с учётом покупки.
  static int limitFor({required bool plus}) => plus ? maxBytesPlus : maxBytes;

  /// Форматы, которые играют у обоих. Комната пары показывает ролик обычным
  /// плеером браузера — а он берёт только эти контейнеры (см. `parseSource`
  /// в `pb_public/watch/room/room.js`). MKV или AVI загрузятся, но у партнёра
  /// останется пустой кадр, поэтому отсекаем их до загрузки.
  static const List<String> playableExtensions = [
    'mp4',
    'm4v',
    'mov',
    'webm',
    'ogv',
    'ogg',
  ];

  /// Проиграется ли файл с таким именем у обоих.
  static bool isPlayable(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return false;
    return playableExtensions.contains(fileName.substring(dot + 1).toLowerCase());
  }

  /// Убирает ролики старше [lifetime]. Зовётся при открытии раздела: отдельного
  /// планировщика ради уборки заводить незачем.
  static Future<void> purgeExpired(String groupId) async {
    if (groupId.isEmpty) return;
    try {
      final edge = DateTime.now().toUtc().subtract(lifetime);
      final list = await _pb.collection(_col).getFullList(
            filter: _pb.filter('group_id = {:g}', {'g': groupId}),
          );
      for (final rec in list) {
        final created = DateTime.tryParse(rec.created)?.toUtc();
        if (created == null || created.isAfter(edge)) continue;
        await _pb.collection(_col).delete(rec.id);
      }
    } catch (e) {
      debugPrint('WatchVideos.purgeExpired failed: $e');
    }
  }

  static PocketBase get _pb => PocketBaseService.instance.pb;

  static String _fileUrl(RecordModel r) {
    final file = (r.data['file'] ?? '').toString();
    if (file.isEmpty) return '';
    return '${PocketBaseService.baseUrl}/api/files/$_col/${r.id}/$file';
  }

  static String _thumbUrl(RecordModel r) {
    final file = (r.data['thumb'] ?? '').toString();
    if (file.isEmpty) return '';
    return '${PocketBaseService.baseUrl}/api/files/$_col/${r.id}/$file';
  }

  static WatchVideo _fromRecord(RecordModel r) => WatchVideo(
        id: r.id,
        title: (r.data['title'] ?? '').toString(),
        url: _fileUrl(r),
        thumbUrl: _thumbUrl(r),
        seconds: ((r.data['seconds'] ?? 0) as num).round(),
      );

  /// Все ролики пары: сначала загруженные во вкладке «Смотрим», затем видео из
  /// ленты воспоминаний — иначе люди не понимают, куда делись их записи.
  static Future<List<WatchVideo>> list(String groupId) async {
    if (groupId.isEmpty) return const [];
    final own = await _uploaded(groupId);
    final lane = await _fromMemoryLane(groupId);
    return [...own, ...lane];
  }

  static Future<List<WatchVideo>> _uploaded(String groupId) async {
    try {
      final res = await _pb.collection(_col).getList(
            page: 1,
            perPage: 30,
            filter: 'group_id = "$groupId"',
            sort: '-updated',
          );
      return res.items.map(_fromRecord).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Видео-воспоминания. Ссылка на файл в них своя (`pb://media/...`), фильтра
  /// по вложенному json в PocketBase нет, поэтому отбираем на клиенте.
  static Future<List<WatchVideo>> _fromMemoryLane(String groupId) async {
    try {
      final res = await _pb.collection('memories').getList(
            page: 1,
            perPage: 60,
            filter: 'group_id = "$groupId"',
            sort: '-created',
          );
      final out = <WatchVideo>[];
      for (final r in res.items) {
        final raw = r.data['data'];
        if (raw is! Map) continue;
        final url = (raw['videoUrl'] ?? '').toString();
        if (url.isEmpty) continue;
        out.add(WatchVideo(
          id: r.id,
          title: (raw['title'] ?? raw['text'] ?? '').toString(),
          url: url,
          thumbUrl: (raw['imageUrl'] ?? raw['thumbnailUrl'] ?? '').toString(),
          seconds: 0,
          appOnly: url.startsWith('pb://'),
        ));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Загружает ролик. Возвращает запись или null, если файл слишком большой
  /// либо сервер отказал. [plus] поднимает потолок до [maxBytesPlus] — тот же,
  /// что стоит в коллекции.
  static Future<WatchVideo?> upload({
    required String groupId,
    required File file,
    required String title,
    bool plus = false,
  }) async {
    if (groupId.isEmpty) return null;
    final size = await file.length();
    if (size > limitFor(plus: plus)) return null;

    try {
      final bytes = await file.readAsBytes();

      final files = <http.MultipartFile>[
        http.MultipartFile.fromBytes('file', bytes, filename: title),
      ];

      // Длительность для подписи на плитке. Не вышло — плитка обойдётся без
      // неё, загрузку из-за этого не роняем.
      int seconds = 0;
      try {
        final info = await VideoCompress.getMediaInfo(file.path)
            .timeout(const Duration(seconds: 20));
        seconds = ((info.duration ?? 0) / 1000).round();
      } catch (e) {
        debugPrint('WatchVideos.upload: длительность не прочиталась: $e');
      }

      // Обложка для карусели — первый информативный кадр. Таймаут обязателен:
      // getByteThumbnail на части кодеков виснет. При неудаче грузим без
      // превью (плитка покажет play на тональном фоне) — загрузку не рушим.
      try {
        final thumbBytes = await VideoCompress.getByteThumbnail(
          file.path,
          quality: 80,
          position: -1,
        ).timeout(const Duration(seconds: 30), onTimeout: () => null);
        if (thumbBytes != null && thumbBytes.isNotEmpty) {
          files.add(http.MultipartFile.fromBytes(
            'thumb',
            thumbBytes,
            filename: 'thumb.jpg',
          ));
        }
      } catch (_) {
        // Превью не обязательно — продолжаем без него.
      }

      final rec = await _pb
          .collection(_col)
          .create(
            body: {
              'group_id': groupId,
              'title': title,
              'seconds': seconds,
              'added_by': PocketBaseService().userId ?? '',
            },
            files: files,
          )
          // Сто мегабайт по мобильной сети идут долго: минутного таймаута,
          // как у фотографий, тут не хватает.
          .timeout(const Duration(minutes: 10));
      return _fromRecord(rec);
    } catch (e) {
      // Отказ сервера виден только здесь: экран покажет общую ошибку, а причину
      // (потолок размера, правила коллекции) без этой строки не найти.
      debugPrint('WatchVideos.upload failed: $e');
      return null;
    }
  }

  static Future<void> remove(String id) async {
    try {
      await _pb.collection(_col).delete(id);
    } catch (_) {
      // Удаление не критично: пусть остаётся, чем ронять экран.
    }
  }
}
