import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../dict_strings.dart';
import '../models/memory_media.dart';
import 'media_save_queue.dart';
import 'offline/media_view_cache.dart';
import 'pb_media_service.dart';

/// Нативная фоновая запись в галерею.
///
/// Dart отдаёт файл и ждёт ответа, а качает и кладёт в галерею натив:
///
/// * Android — `MediaSaveService.kt`: своя служба переднего плана с
///   уведомлением «Сохраняю в галерею · Лето на Днестре · 37/94» и кнопкой
///   «Остановить». Работает, когда приложение свёрнуто и даже смахнуто из
///   недавних: служба живёт отдельно от экрана.
/// * iPhone — фоновая сессия `URLSession` в `AppDelegate.swift`: система
///   докачивает файлы и в свёрнутом, и в выгруженном приложении, а по
///   окончании натив присылает уведомление «В галерее: 94».
///
/// Натив держит свою очередь по ключу файла и переживает смерть Dart: повторная
/// постановка того же ключа ничего не удваивает, а готовое лежит у натива,
/// пока Dart его не подтвердит (`engineAck`). Пока приложение открыто, Dart
/// опрашивает готовое раз в [pollEvery]; свёрнутое iPhone опрос замораживает —
/// натив тем временем работает, и первый же опрос после возвращения забирает
/// всё разом.
class NativeSaveExecutor implements SaveExecutor {
  NativeSaveExecutor({
    MethodChannel? channel,
    this.pollEvery = const Duration(milliseconds: 800),
    Future<Map<String, Object?>> Function(MediaFile f)? sourceOf,
  })  : channel = channel ?? const MethodChannel('love_app/gallery'),
        _sourceOf = sourceOf ?? defaultSource;

  static final NativeSaveExecutor instance = NativeSaveExecutor();

  final MethodChannel channel;
  final Duration pollEvery;
  final Future<Map<String, Object?>> Function(MediaFile f) _sourceOf;

  final Map<String, Completer<String?>> _waiting = {};
  Timer? _timer;
  bool _ticking = false;

  /// Отдаём всё разом: сколько качать одновременно, решает натив (три потока
  /// на Android, сама система на iPhone). Иначе в фоне продолжили бы только
  /// три файла, отданные до сворачивания.
  @override
  int get concurrency => 100000;

  /// Откуда натив возьмёт байты: путь, если файл уже на телефоне (ещё не
  /// отправленный или открытый кадр в кэше картинок), иначе ссылка с файловым
  /// токеном. Токен живёт сутки — фоновой загрузке хватает с запасом.
  static Future<Map<String, Object?>> defaultSource(MediaFile f) async {
    final ref = f.ref.trim();
    if (ref.startsWith('localfile://')) {
      return {'path': ref.substring('localfile://'.length)};
    }
    if (f.kind == SaveKind.photo) {
      try {
        final info =
            await OfflineImageCacheManager.instance.getFileFromCache('v2|$ref');
        final file = info?.file;
        if (file != null && await file.exists() && await file.length() > 1024) {
          // Копия, а не сам файл кэша: кэш вправе вытеснить его раньше, чем
          // натив до него доберётся.
          final copy = File('${file.parent.path}/save_${f.key.hashCode}.${f.ext}');
          await file.copy(copy.path);
          return {'path': copy.path, 'deleteAfter': true};
        }
      } catch (_) {}
    }
    final url = await PbMediaService().resolveUrlAuthed(ref) ?? ref;
    return {'url': url};
  }

  static Map<String, String> get _labels => {
        'saving': trKey('islandSaving'),
        'done': trKey('islandDone'),
        'failed': trKey('islandFailed'),
        'stop': trKey('notifStop'),
      };

  @override
  Future<String?> run(SaveItem item,
      {required bool hidden, String title = ''}) async {
    final key = item.file.key;
    final source = await _sourceOf(item.file);
    final c = _waiting.putIfAbsent(key, () => Completer<String?>());
    try {
      await channel.invokeMethod<void>('engineSubmit', <String, Object?>{
        'key': key,
        ...source,
        'kind': item.file.kind.name,
        'takenAt': item.takenAt.millisecondsSinceEpoch,
        'offsetMinutes': item.takenAt.timeZoneOffset.inMinutes,
        'latitude': item.latitude,
        'longitude': item.longitude,
        'name': galleryFileName(item.takenAt, item.file),
        'album': kGalleryAlbum,
        'hidden': hidden,
        'title': title,
        'labels': _labels,
      });
    } catch (e) {
      _waiting.remove(key);
      rethrow;
    }
    _ensurePolling();
    return c.future;
  }

  void _ensurePolling() {
    if (_timer != null) return;
    _timer = Timer.periodic(pollEvery, (_) => _tick());
  }

  Future<void> _tick() async {
    if (_ticking) return;
    _ticking = true;
    try {
      final res =
          await channel.invokeMapMethod<String, Object?>('engineStatus');
      final results = (res?['results'] as List?) ?? const [];
      final acks = <String>[];
      for (final raw in results) {
        if (raw is! Map) continue;
        final key = raw['key'] as String?;
        if (key == null) continue;
        final c = _waiting.remove(key);
        // Чужое готовое (поставленное до перезапуска) не трогаем: его заберёт
        // [recover] при следующем старте очереди.
        if (c == null) continue;
        acks.add(key);
        switch (raw['code']) {
          case 'OK':
            c.complete(raw['uri'] as String?);
          case 'ACCESS_DENIED':
            c.completeError(const GalleryAccessDenied());
          case 'CANCELLED':
            c.completeError(const SaveCancelled());
          default:
            c.completeError(
                Exception(raw['error'] as String? ?? 'не сохранилось'));
        }
      }
      if (acks.isNotEmpty) {
        await channel.invokeMethod<void>('engineAck', {'keys': acks});
      }
    } catch (e) {
      debugPrint('NativeSaveExecutor.tick: $e');
    } finally {
      _ticking = false;
      if (_waiting.isEmpty) {
        _timer?.cancel();
        _timer = null;
      }
    }
  }

  @override
  Future<void> cancel(Iterable<SaveItem> items) async {
    final keys = [for (final i in items) i.file.key];
    if (keys.isEmpty) return;
    for (final k in keys) {
      _waiting.remove(k)?.completeError(const SaveCancelled());
    }
    try {
      await channel.invokeMethod<void>('engineCancel', {'keys': keys});
    } catch (e) {
      debugPrint('NativeSaveExecutor.cancel: $e');
    }
  }

  @override
  Future<List<String>> recover() async {
    try {
      final res =
          await channel.invokeMapMethod<String, Object?>('engineStatus');
      final results = (res?['results'] as List?) ?? const [];
      final done = <String>[];
      final all = <String>[];
      for (final raw in results) {
        if (raw is! Map) continue;
        final key = raw['key'] as String?;
        if (key == null || _waiting.containsKey(key)) continue;
        all.add(key);
        if (raw['code'] == 'OK') done.add(key);
      }
      if (all.isNotEmpty) {
        await channel.invokeMethod<void>('engineAck', {'keys': all});
      }
      return done;
    } catch (e) {
      debugPrint('NativeSaveExecutor.recover: $e');
      return const [];
    }
  }
}
