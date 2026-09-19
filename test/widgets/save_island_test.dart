// Островок над лентой: сохранение не держит человека на экране. Пока идёт —
// кольцо и «37/94», по окончании — «В галерее: 94 · Открыть», при неудаче —
// «Не сохранилось: 1 · Повторить».
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/memory_media.dart';
import 'package:love_app/services/media_save_queue.dart';
import 'package:love_app/services/saved_media_ledger.dart';
import 'package:love_app/widgets/memory_save/save_island.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Fetcher implements MediaFetcher {
  final Set<String> fail;
  Completer<void>? gate;
  _Fetcher({this.fail = const {}});

  @override
  Future<FetchedMedia> fetch(MediaFile f) async {
    if (gate != null) await gate!.future;
    if (fail.contains(f.key)) throw const SocketException('нет сети');
    return FetchedMedia(File('/dev/null'), temporary: false);
  }
}

class _Gallery implements GalleryTarget {
  @override
  Future<String?> save(GallerySaveRequest r) async => 'content://x';
}

List<SaveItem> _items(int n) => [
      for (var i = 0; i < n; i++)
        SaveItem(
          memoryId: 'm1',
          takenAt: DateTime(2026, 9, 5),
          file: MediaFile(
              ref: 'pb://media/m/f$i.webp', kind: SaveKind.photo, index: i),
        ),
    ];

Widget _host(MediaSaveQueue q) => MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          Positioned(left: 14, right: 14, bottom: 18, child: SaveIsland(queue: q)),
        ]),
      ),
    );

void main() {
  late SavedMediaLedger ledger;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ledger = SavedMediaLedger.forTest();
    await ledger.load();
  });

  testWidgets('пока идёт — название и счётчик, крестик отменяет', (t) async {
    final f = _Fetcher()..gate = Completer<void>();
    final q = MediaSaveQueue(
        fetcher: f, target: _Gallery(), ledger: ledger, retryDelays: const []);
    await t.pumpWidget(_host(q));
    await t.runAsync(() => q.enqueue('Лето на Днестре', _items(5)));
    await t.pump();
    expect(find.textContaining('Лето на Днестре'), findsOneWidget);
    expect(find.textContaining('0/5'), findsOneWidget);
    await t.tap(find.byKey(SaveIsland.closeKey));
    await t.pump();
    expect(q.current, isNull);
    f.gate!.complete();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump(const Duration(seconds: 7));
  });

  testWidgets('готово — «Открыть», потом островок уходит сам', (t) async {
    final q = MediaSaveQueue(
        fetcher: _Fetcher(), target: _Gallery(), ledger: ledger,
        retryDelays: const []);
    await t.pumpWidget(_host(q));
    await t.runAsync(() async {
      await q.enqueue('Лето', _items(3));
      for (var i = 0; i < 50 && q.busy; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    await t.pump();
    expect(find.byKey(SaveIsland.openKey), findsOneWidget);
    expect(find.textContaining('3'), findsWidgets);
    await t.pump(const Duration(seconds: 7));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byKey(SaveIsland.openKey), findsNothing);
  });

  testWidgets('неудача — «Повторить» и островок не уходит сам', (t) async {
    final q = MediaSaveQueue(
        fetcher: _Fetcher(fail: {'pb://media/m/f1.webp'}),
        target: _Gallery(),
        ledger: ledger,
        retryDelays: const []);
    await t.pumpWidget(_host(q));
    await t.runAsync(() async {
      await q.enqueue('Лето', _items(3));
      for (var i = 0; i < 50 && q.busy; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    await t.pump();
    expect(find.byKey(SaveIsland.retryKey), findsOneWidget);
    await t.pump(const Duration(seconds: 10));
    expect(find.byKey(SaveIsland.retryKey), findsOneWidget);
  });
}
