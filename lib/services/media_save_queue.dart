import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/memory.dart';
import '../models/memory_media.dart';
import 'gallery_writer.dart';
import 'media_fetcher.dart';
import 'saved_media_ledger.dart';

/// Папка в галерее, куда ложится всё сохранённое из Togetherly.
///
/// Android — `Pictures/Togetherly` (и фото, и видео: одна папка, одна плитка
/// в галерее), iPhone — альбом «Togetherly». Просьба заказчика 19.09.2026.
const String kGalleryAlbum = 'Togetherly';

/// Файл, который загрузчик положил на диск.
class FetchedMedia {
  final File file;

  /// Временный файл удаляется после записи в галерею. Файл из кэша картинок и
  /// ещё не отправленный файл с телефона — нет: они нужны приложению дальше.
  final bool temporary;

  const FetchedMedia(this.file, {this.temporary = true});
}

/// Откуда очередь берёт байты файла.
abstract class MediaFetcher {
  Future<FetchedMedia> fetch(MediaFile f);
}

/// Куда очередь кладёт готовый файл.
abstract class GalleryTarget {
  /// Возвращает адрес файла в галерее (для «Открыть») или null.
  Future<String?> save(GallerySaveRequest r);
}

/// Галерея закрыта для приложения: человек отказал в доступе. Повторять
/// бессмысленно, задание останавливается целиком.
class GalleryAccessDenied implements Exception {
  const GalleryAccessDenied();
  @override
  String toString() => 'GalleryAccessDenied';
}

class GallerySaveRequest {
  final String path;
  final SaveKind kind;

  /// Дата воспоминания: в галерее кадр встанет на этот день, а не на день
  /// сохранения. Togetherly при загрузке срезает у снимков дату съёмки, и без
  /// неё 94 летних кадра легли бы «сегодня».
  final DateTime takenAt;
  final double? latitude;
  final double? longitude;
  final String name;
  final String album;

  /// Только iPhone: пометить скрытым (альбом «Скрытые» под Face ID).
  final bool hidden;

  const GallerySaveRequest({
    required this.path,
    required this.kind,
    required this.takenAt,
    required this.name,
    this.latitude,
    this.longitude,
    this.album = kGalleryAlbum,
    this.hidden = false,
  });
}

/// Один файл в очереди вместе с тем, что о нём нужно галерее.
class SaveItem {
  final String memoryId;
  final DateTime takenAt;
  final double? latitude;
  final double? longitude;
  final MediaFile file;

  const SaveItem({
    required this.memoryId,
    required this.takenAt,
    required this.file,
    this.latitude,
    this.longitude,
  });

  factory SaveItem.of(Memory m, MediaFile f) => SaveItem(
        memoryId: m.id,
        takenAt: m.createdAt,
        latitude: m.latitude,
        longitude: m.longitude,
        file: f,
      );

  Map<String, Object?> toJson() => {
        'm': memoryId,
        't': takenAt.millisecondsSinceEpoch,
        'la': latitude,
        'lo': longitude,
        'r': file.ref,
        'k': file.kind.name,
        'i': file.index,
      };

  static SaveItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    try {
      final kind = SaveKind.values.byName(raw['k'] as String);
      return SaveItem(
        memoryId: raw['m'] as String,
        takenAt: DateTime.fromMillisecondsSinceEpoch((raw['t'] as num).toInt()),
        latitude: (raw['la'] as num?)?.toDouble(),
        longitude: (raw['lo'] as num?)?.toDouble(),
        file: MediaFile(
          ref: raw['r'] as String,
          kind: kind,
          index: (raw['i'] as num).toInt(),
        ),
      );
    } catch (_) {
      return null;
    }
  }
}

enum _St { pending, running, done, failed }

/// Задание: всё, что человек отправил в галерею одним нажатием.
class SaveJob {
  SaveJob._(this.id, this.title, this.items, this.hidden)
      : _st = List<_St>.filled(items.length, _St.pending);

  final String id;

  /// Что подписывать в островке: название воспоминания или «Все кадры».
  final String title;
  final List<SaveItem> items;
  final bool hidden;
  final List<_St> _st;

  bool cancelled = false;
  bool accessDenied = false;

  /// Адрес последнего сохранённого файла — «Открыть» ведёт к нему.
  String? lastUri;

  int get total => items.length;
  int get done => _st.where((s) => s == _St.done).length;
  int get failed => _st.where((s) => s == _St.failed).length;
  int get _runningCount => _st.where((s) => s == _St.running).length;

  /// Задание кончилось: либо всё разобрано, либо его остановили и последние
  /// начатые файлы доехали.
  bool get finished {
    if (cancelled || accessDenied) return _runningCount == 0;
    return _st.every((s) => s == _St.done || s == _St.failed);
  }

  /// Доля готового для кольца.
  double get progress => total == 0 ? 1 : done / total;

  bool hasMemory(String memoryId) => items.any((i) => i.memoryId == memoryId);

  bool isDoneAt(int i) => _st[i] == _St.done;
  bool isRunningAt(int i) => _st[i] == _St.running;
  bool isFailedAt(int i) => _st[i] == _St.failed;
}

/// Одна очередь на всё сохранение в галерею: кадр, воспоминание, выбранные
/// кадры, несколько записей, вся пара.
///
/// Три файла одновременно — больше не даёт ни скорости (канал телефона один),
/// ни радости серверу; повтор при обрыве; отмена не рвёт начатые файлы, а не
/// начинает новых. Недоделанное задание переживает перезапуск приложения: при
/// следующем открытии ленты очередь доедет сама.
class MediaSaveQueue extends ChangeNotifier {
  MediaSaveQueue({
    required this.fetcher,
    required this.target,
    required this.ledger,
    this.concurrency = 3,
    this.retryDelays = const [Duration(seconds: 1), Duration(seconds: 3)],
  });

  static MediaSaveQueue? _instance;
  static MediaSaveQueue get instance => _instance ??= MediaSaveQueue(
        fetcher: HttpMediaFetcher(),
        target: GalleryWriter.instance,
        ledger: SavedMediaLedger.instance,
      );

  static const String prefsKey = 'media_save_queue_v1';

  final MediaFetcher fetcher;
  final GalleryTarget target;
  final SavedMediaLedger ledger;
  final int concurrency;
  final List<Duration> retryDelays;

  final List<SaveJob> _jobs = [];
  SaveJob? _lastFinished;
  int _running = 0;
  int _seq = 0;
  bool _resumed = false;

  List<SaveJob> get jobs => List.unmodifiable(_jobs);

  /// Идёт хоть что-то: загрузка или ожидание своей очереди.
  bool get busy => _running > 0 || _jobs.any((j) => !j.finished);

  /// Первое незаконченное задание — его показывает островок. Остановленное
  /// человеком сюда не попадает, даже пока доезжают три начатых файла: он
  /// нажал крестик и ждать их не обязан.
  SaveJob? get current {
    for (final j in _jobs) {
      if (!j.finished && !j.cancelled) return j;
    }
    return null;
  }

  /// Последнее законченное задание — для строки «В галерее: 94 · Открыть».
  SaveJob? get lastFinished => _lastFinished;

  void dismissFinished() {
    if (_lastFinished == null) return;
    final j = _lastFinished!;
    _lastFinished = null;
    _jobs.remove(j);
    notifyListeners();
  }

  /// Незаконченное задание, в котором есть файлы этого воспоминания.
  SaveJob? activeFor(String memoryId) {
    for (final j in _jobs) {
      if (!j.finished && !j.cancelled && j.hasMemory(memoryId)) return j;
    }
    return null;
  }

  /// Сколько файлов этого воспоминания готово из скольких — для разделённой
  /// кнопки, когда воспоминание едет в галерею внутри общего задания (выбор
  /// нескольких записей, вся пара). null — ничего не идёт.
  (int, int)? progressFor(String memoryId) {
    var done = 0, total = 0;
    for (final j in _jobs) {
      if (j.finished || j.cancelled) continue;
      for (var i = 0; i < j.items.length; i++) {
        if (j.items[i].memoryId != memoryId) continue;
        total++;
        if (j.isDoneAt(i)) done++;
      }
    }
    return total == 0 ? null : (done, total);
  }

  /// Файл ждёт или едет в галерею прямо сейчас.
  bool isQueued(String key) => _queuedKeys.contains(mediaKey(key));

  Set<String> get _queuedKeys => {
        for (final j in _jobs)
          if (!j.finished && !j.cancelled)
            for (var i = 0; i < j.items.length; i++)
              if (!j.isDoneAt(i) && !j.isFailedAt(i)) j.items[i].file.key,
      };

  /// Ставит файлы в очередь. Уже лежащее в галерее и уже стоящее в очереди
  /// пропускается; если сохранять нечего, задания нет.
  Future<SaveJob?> enqueue(
    String title,
    List<SaveItem> items, {
    bool hidden = false,
  }) async {
    await ledger.load();
    final queued = _queuedKeys;
    final seen = <String>{};
    final fresh = <SaveItem>[
      for (final it in items)
        if (!ledger.containsFile(it.file) &&
            !queued.contains(it.file.key) &&
            seen.add(it.file.key))
          it,
    ];
    if (fresh.isEmpty) return null;
    final job = SaveJob._(
      'j${++_seq}_${DateTime.now().millisecondsSinceEpoch}',
      title,
      fresh,
      hidden,
    );
    _jobs.add(job);
    notifyListeners();
    unawaited(persistNow());
    _pump();
    return job;
  }

  void cancel(String jobId) {
    final job = _byId(jobId);
    if (job == null || job.finished) return;
    job.cancelled = true;
    if (job.finished) _finish(job);
    notifyListeners();
    unawaited(persistNow());
  }

  /// Вернуть несохранённые файлы в очередь (кнопка «Повторить»).
  void retryFailed(String jobId) {
    final job = _byId(jobId);
    if (job == null) return;
    for (var i = 0; i < job._st.length; i++) {
      if (job._st[i] == _St.failed) job._st[i] = _St.pending;
    }
    job.cancelled = false;
    job.accessDenied = false;
    if (identical(_lastFinished, job)) _lastFinished = null;
    notifyListeners();
    unawaited(persistNow());
    _pump();
  }

  SaveJob? _byId(String id) {
    for (final j in _jobs) {
      if (j.id == id) return j;
    }
    return null;
  }

  (SaveJob, int)? _nextPending() {
    for (final j in _jobs) {
      if (j.cancelled || j.accessDenied) continue;
      final i = j._st.indexOf(_St.pending);
      if (i != -1) return (j, i);
    }
    return null;
  }

  void _pump() {
    while (_running < concurrency) {
      final next = _nextPending();
      if (next == null) break;
      final (job, i) = next;
      job._st[i] = _St.running;
      _running++;
      unawaited(_run(job, i));
    }
  }

  Future<void> _run(SaveJob job, int i) async {
    final item = job.items[i];
    FetchedMedia? got;
    try {
      String? uri;
      for (var attempt = 0;; attempt++) {
        try {
          got = await fetcher.fetch(item.file);
          uri = await target.save(GallerySaveRequest(
            path: got.file.path,
            kind: item.file.kind,
            takenAt: item.takenAt,
            latitude: item.latitude,
            longitude: item.longitude,
            name: galleryFileName(item.takenAt, item.file),
            hidden: job.hidden,
          ));
          break;
        } on GalleryAccessDenied {
          rethrow;
        } catch (e) {
          await _drop(got);
          got = null;
          if (attempt >= retryDelays.length || job.cancelled) rethrow;
          await Future<void>.delayed(retryDelays[attempt]);
        }
      }
      job._st[i] = _St.done;
      if (uri != null) job.lastUri = uri;
      await ledger.add(item.file.key);
    } on GalleryAccessDenied {
      job._st[i] = _St.failed;
      job.accessDenied = true;
    } catch (e) {
      job._st[i] = _St.failed;
      debugPrint('MediaSaveQueue: ${item.file.key} не сохранился: $e');
    } finally {
      await _drop(got);
      _running--;
      if (job.finished) _finish(job);
      notifyListeners();
      unawaited(persistNow());
      _pump();
    }
  }

  void _finish(SaveJob job) {
    _lastFinished = job;
    // Держим только идущие задания и последнее законченное: список живёт весь
    // сеанс, и копить в нём прошлые сохранения незачем.
    _jobs.removeWhere((j) => j.finished && !identical(j, job));
  }

  Future<void> _drop(FetchedMedia? got) async {
    if (got == null || !got.temporary) return;
    try {
      if (await got.file.exists()) await got.file.delete();
    } catch (_) {}
  }

  /// Записать недоделанное на диск: закрыли приложение — очередь доедет при
  /// следующем открытии ленты.
  @visibleForTesting
  Future<void> persistNow() async {
    final data = [
      for (final j in _jobs)
        if (!j.finished && !j.cancelled && !j.accessDenied)
          {
            'title': j.title,
            'hidden': j.hidden,
            'items': [
              for (var i = 0; i < j.items.length; i++)
                if (!j.isDoneAt(i) && !j.isFailedAt(i)) j.items[i].toJson(),
            ],
          },
    ];
    try {
      final prefs = await SharedPreferences.getInstance();
      if (data.isEmpty) {
        await prefs.remove(prefsKey);
      } else {
        await prefs.setString(prefsKey, jsonEncode(data));
      }
    } catch (e) {
      debugPrint('MediaSaveQueue.persist: $e');
    }
  }

  /// Подхватить задания, оборванные закрытием приложения. Зовётся один раз.
  Future<void> resume() async {
    if (_resumed) return;
    _resumed = true;
    String? raw;
    try {
      final prefs = await SharedPreferences.getInstance();
      raw = prefs.getString(prefsKey);
      await prefs.remove(prefsKey);
    } catch (_) {}
    if (raw == null || raw.isEmpty) return;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return;
    }
    if (decoded is! List) return;
    for (final j in decoded) {
      if (j is! Map) continue;
      final items = <SaveItem>[
        for (final r in (j['items'] as List? ?? const []))
          if (SaveItem.fromJson(r) case final SaveItem it) it,
      ];
      if (items.isEmpty) continue;
      await enqueue(
        (j['title'] as String?) ?? '',
        items,
        hidden: j['hidden'] == true,
      );
    }
  }
}
