// Одна очередь на всё сохранение: кадр, воспоминание, выбор, вся пара.
//
// Проверяется без телефона: загрузчик и галерея подменены, поэтому видно
// ровно поведение очереди — сколько файлов идёт разом, что происходит при
// обрыве, отмене и отказе в доступе к галерее.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/memory_media.dart';
import 'package:love_app/services/media_save_queue.dart';
import 'package:love_app/services/saved_media_ledger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Fetcher implements MediaFetcher {
  final Map<String, int> failFirst; // ключ → сколько раз упасть
  final Map<String, Completer<void>> gates = {};
  bool holdAll = false;
  int running = 0;
  int maxRunning = 0;
  final List<String> calls = [];

  _Fetcher({this.failFirst = const {}});

  @override
  Future<FetchedMedia> fetch(MediaFile f) async {
    calls.add(f.key);
    running++;
    if (running > maxRunning) maxRunning = running;
    try {
      if (holdAll) {
        final g = gates.putIfAbsent(f.key, () => Completer<void>());
        await g.future;
      }
      final left = failFirst[f.key] ?? 0;
      if (left > 0) {
        failFirst[f.key] = left - 1;
        throw const SocketException('обрыв');
      }
      final file = File('${Directory.systemTemp.path}/mq_${f.key.hashCode}');
      await file.writeAsString('x');
      return FetchedMedia(file, temporary: true);
    } finally {
      running--;
    }
  }

  void releaseAll() {
    for (final g in gates.values) {
      if (!g.isCompleted) g.complete();
    }
  }
}

class _Gallery implements GalleryTarget {
  final List<GallerySaveRequest> saved = [];
  bool deny = false;

  @override
  Future<String?> save(GallerySaveRequest r) async {
    if (deny) throw const GalleryAccessDenied();
    saved.add(r);
    return 'content://media/${saved.length}';
  }
}

/// Исполнитель вместо пары «загрузчик + галерея»: так устроена нативная
/// фоновая запись — очередь отдаёт файл и ждёт ответа.
class _Exec implements SaveExecutor {
  final List<String> cancelled = [];
  final Map<String, Completer<String?>> waiting = {};
  List<String> recovered = const [];

  @override
  int get concurrency => 100;

  @override
  Future<String?> run(SaveItem item, {required bool hidden, String title = ''}) =>
      waiting.putIfAbsent(item.file.key, () => Completer<String?>()).future;

  @override
  Future<void> cancel(Iterable<SaveItem> items) async {
    for (final i in items) {
      cancelled.add(i.file.key);
      waiting.remove(i.file.key)?.completeError(const SaveCancelled());
    }
  }

  @override
  Future<List<String>> recover() async => recovered;

  void finishAll() {
    for (final c in waiting.values) {
      if (!c.isCompleted) c.complete('content://x');
    }
    waiting.clear();
  }
}

SaveItem _item(String ref, {String memoryId = 'm1', int i = 0}) => SaveItem(
      memoryId: memoryId,
      takenAt: DateTime(2026, 9, 5, 13, 5),
      latitude: 46.9,
      longitude: 29.1,
      file: MediaFile(ref: ref, kind: SaveKind.photo, index: i),
    );

List<SaveItem> _items(int n, {String memoryId = 'm1'}) => [
      for (var i = 0; i < n; i++)
        _item('pb://media/$memoryId/f$i.webp', memoryId: memoryId, i: i),
    ];

Future<void> _settle(MediaSaveQueue q) async {
  for (var i = 0; i < 2000 && q.busy; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

/// Отпускать задержанные загрузки, пока очередь не опустеет: новые ожидания
/// появляются по мере того, как освобождаются места, и под нагрузкой полного
/// прогона их выпуск растягивается.
Future<void> _drain(MediaSaveQueue q, _Fetcher f) async {
  for (var i = 0; i < 2000 && q.busy; i++) {
    f.releaseAll();
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

void main() {
  late SavedMediaLedger ledger;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ledger = SavedMediaLedger.forTest();
    await ledger.load();
  });

  MediaSaveQueue queue(_Fetcher f, _Gallery g) => MediaSaveQueue(
        fetcher: f,
        target: g,
        ledger: ledger,
        retryDelays: const [Duration.zero, Duration.zero],
      );

  test('всё воспоминание уходит в галерею с датой, местом и папкой', () async {
    final f = _Fetcher(), g = _Gallery();
    final q = queue(f, g);
    final job = await q.enqueue('Лето на Днестре', _items(5));
    await _settle(q);

    expect(job!.done, 5);
    expect(job.finished, isTrue);
    expect(g.saved, hasLength(5));
    final r = g.saved.first;
    expect(r.takenAt, DateTime(2026, 9, 5, 13, 5));
    expect(r.latitude, 46.9);
    expect(r.album, 'Togetherly');
    expect(r.name, startsWith('Togetherly_20260905_130500_'));
    expect(ledger.contains('pb://media/m1/f3.webp'), isTrue);
    expect(q.lastFinished, same(job));
  });

  test('разом идёт не больше трёх файлов', () async {
    final f = _Fetcher()..holdAll = true;
    final q = queue(f, _Gallery());
    await q.enqueue('много', _items(10));
    await Future<void>.delayed(Duration.zero);
    expect(f.running, 3);
    await _drain(q, f);
    expect(f.maxRunning, 3);
    expect(q.lastFinished!.done, 10);
  });

  test('обрыв сети повторяется, а не теряет кадр', () async {
    final f = _Fetcher(failFirst: {'pb://media/m1/f1.webp': 2});
    final g = _Gallery();
    final q = queue(f, g);
    final job = await q.enqueue('обрыв', _items(3));
    await _settle(q);
    expect(job!.done, 3);
    expect(job.failed, 0);
    expect(f.calls.where((k) => k == 'pb://media/m1/f1.webp'), hasLength(3));
  });

  test('после всех повторов кадр считается несохранённым и его можно повторить',
      () async {
    final f = _Fetcher(failFirst: {'pb://media/m1/f0.webp': 3});
    final q = queue(f, _Gallery());
    final job = await q.enqueue('отказ', _items(2));
    await _settle(q);
    expect(job!.done, 1);
    expect(job.failed, 1);
    expect(job.finished, isTrue);

    q.retryFailed(job.id);
    await _settle(q);
    expect(job.done, 2);
    expect(job.failed, 0);
  });

  test('уже сохранённое не загружается второй раз', () async {
    await ledger.add('pb://media/m1/f0.webp');
    final f = _Fetcher();
    final q = queue(f, _Gallery());
    final job = await q.enqueue('повтор', _items(3));
    await _settle(q);
    expect(job!.total, 2);
    expect(f.calls, isNot(contains('pb://media/m1/f0.webp')));
  });

  test('когда сохранять нечего, задания нет', () async {
    await ledger.addAll(['pb://media/m1/f0.webp', 'pb://media/m1/f1.webp']);
    final q = queue(_Fetcher(), _Gallery());
    expect(await q.enqueue('всё есть', _items(2)), isNull);
  });

  test('отмена не начинает новых загрузок', () async {
    final f = _Fetcher()..holdAll = true;
    final g = _Gallery();
    final q = queue(f, g);
    final job = await q.enqueue('отмена', _items(8));
    await Future<void>.delayed(Duration.zero);
    q.cancel(job!.id);
    f.releaseAll();
    await _settle(q);
    expect(f.calls, hasLength(3));
    expect(job.cancelled, isTrue);
    expect(q.activeFor('m1'), isNull);
  });

  test('отказ в доступе к галерее останавливает всё задание', () async {
    final g = _Gallery()..deny = true;
    final q = queue(_Fetcher(), g);
    final job = await q.enqueue('нет доступа', _items(6));
    await _settle(q);
    expect(job!.accessDenied, isTrue);
    expect(job.finished, isTrue);
    expect(job.done, 0);
  });

  test('activeFor находит идущее задание по воспоминанию', () async {
    final f = _Fetcher()..holdAll = true;
    final q = queue(f, _Gallery());
    await q.enqueue('a', _items(2, memoryId: 'a'));
    await q.enqueue('b', _items(2, memoryId: 'b'));
    await Future<void>.delayed(Duration.zero);
    expect(q.activeFor('b')!.title, 'b');
    expect(q.activeFor('c'), isNull);
    await _drain(q, f);
  });

  test('ход по одной записи внутри общего задания и признак «в очереди»',
      () async {
    final f = _Fetcher()..holdAll = true;
    final q = queue(f, _Gallery());
    await q.enqueue('два воспоминания', [
      ..._items(3, memoryId: 'a'),
      ..._items(2, memoryId: 'b'),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(q.progressFor('b'), (0, 2));
    expect(q.isQueued('pb://media/b/f1.webp'), isTrue);
    expect(q.isQueued('pb://media/c/f1.webp'), isFalse);
    await _drain(q, f);
    expect(q.progressFor('b'), isNull);
    expect(q.isQueued('pb://media/b/f1.webp'), isFalse);
  });

  test('исполнитель берёт всё разом, отмена доходит до него', () async {
    final e = _Exec();
    final q = MediaSaveQueue(executor: e, ledger: ledger);
    final job = await q.enqueue('в фон', _items(8));
    await Future<void>.delayed(Duration.zero);
    expect(e.waiting, hasLength(8));
    q.cancel(job!.id);
    await _settle(q);
    expect(e.cancelled, hasLength(8));
    expect(job.cancelled, isTrue);
    expect(q.current, isNull);
  });

  test('«Остановить» в уведомлении гасит задание как отменённое', () async {
    final e = _Exec();
    final q = MediaSaveQueue(executor: e, ledger: ledger);
    final job = await q.enqueue('в фон', _items(3));
    await Future<void>.delayed(Duration.zero);
    for (final c in e.waiting.values) {
      c.completeError(const SaveCancelled());
    }
    e.waiting.clear();
    await _settle(q);
    expect(job!.cancelled, isTrue);
    expect(job.failed, 0);
  });

  test('при старте сперва забирается сделанное без приложения', () async {
    // Приложение закрыли посреди сохранения: натив доделал два файла сам.
    final first = _Exec();
    final q1 = MediaSaveQueue(executor: first, ledger: ledger);
    await q1.enqueue('Лето', _items(4));
    await Future<void>.delayed(Duration.zero);
    await q1.persistNow();

    final e = _Exec()
      ..recovered = ['pb://media/m1/f0.webp', 'pb://media/m1/f1.webp'];
    final q2 = MediaSaveQueue(executor: e, ledger: ledger);
    await q2.resume();
    await Future<void>.delayed(Duration.zero);
    expect(ledger.contains('pb://media/m1/f0.webp'), isTrue);
    expect(e.waiting.keys, ['pb://media/m1/f2.webp', 'pb://media/m1/f3.webp']);
    e.finishAll();
    await _settle(q2);
    expect(q2.lastFinished!.done, 2);
  });

  test('недоделанное задание переживает перезапуск приложения', () async {
    final f = _Fetcher()..holdAll = true;
    final q = queue(f, _Gallery());
    await q.enqueue('Лето на Днестре', _items(4));
    await Future<void>.delayed(Duration.zero);
    await q.persistNow();

    final f2 = _Fetcher();
    final g2 = _Gallery();
    final q2 = queue(f2, g2);
    await q2.resume();
    await _settle(q2);
    expect(g2.saved, hasLength(4));
    expect(q2.lastFinished!.title, 'Лето на Днестре');
    f.releaseAll();
  });
}
