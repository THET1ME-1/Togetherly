import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:sembast/sembast_memory.dart';

import 'package:love_app/services/offline/local_store.dart';
import 'package:love_app/services/offline/outbox_service.dart';
import 'package:love_app/services/offline/record_scope.dart';
import 'package:love_app/services/offline/scope_reconciler.dart';

/// Воспоминание пропадало с телефона автора, хотя на сервере лежало целым
/// (14.10.2026: «Рыцари семи королевств», три фото и подпись, в ленте пусто).
///
/// Сверка состава снимала список с сервера, пока очередь ещё везла запись, а
/// «своё неотправленное» считала уже после ответа. К этому моменту очередь
/// успевала запись довезти и вычеркнуть, и сверка удаляла её из кэша как
/// лишнюю. Вернуть её было нечем: инкремент по `updated` её уже видел.
Future<void> _waitDrained(OutboxService ob) async {
  for (var i = 0; i < 200; i++) {
    if (ob.pendingCount.value == 0) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late LocalStore store;
  late OutboxService ob;
  const scope = RecordScope(
    'memories:g=g1',
    equals: {'group_id': 'g1', 'deleted': false},
  );

  RecordModel memory(String id) => RecordModel({
        'id': id,
        'collectionName': 'memories',
        'group_id': 'g1',
        'deleted': false,
        'created_at': '2026-10-14 12:49:24.296Z',
        'updated': '2026-10-14 12:49:24.878Z',
      });

  setUp(() async {
    store = LocalStore.instance;
    await store.initWith(databaseFactoryMemory, 'test_reconcile_fresh.db');
    await store.clearAll();
    ob = OutboxService.instance;
    await ob.clear();
  });

  tearDown(() => ob.applyOverride = null);

  test('запись, которую очередь довезла во время сверки, остаётся', () async {
    final server = Completer<void>();
    ob.applyOverride = (type, payload) async {
      await server.future; // создание висит в сети
      return true;
    };

    // Как MemoryRepository.add: строка в кэше и операция в очереди.
    await store.upsert('memories', memory('old'));
    await store.upsert('memories', memory('knights'));
    await ob.enqueue(
        'memoryUpsert', {'groupId': 'g1', 'id': 'knights', 'data': {}});

    await reconcileWithServer(
      store: store,
      outbox: ob,
      collection: 'memories',
      scope: scope,
      fetchServer: () async {
        // Сервер ответил списком, где записи ещё нет…
        final snapshot = [memory('old')];
        // …а пока ответ шёл, очередь довезла её и вычеркнула.
        server.complete();
        await _waitDrained(ob);
        return snapshot;
      },
    );

    expect(await store.getRecord('memories', 'knights'), isNotNull);
  });

  test('запись, созданная и отправленная прямо во время сверки, остаётся',
      () async {
    ob.applyOverride = (type, payload) async => true;
    await store.upsert('memories', memory('old'));

    await reconcileWithServer(
      store: store,
      outbox: ob,
      collection: 'memories',
      scope: scope,
      fetchServer: () async {
        final snapshot = [memory('old')];
        await store.upsert('memories', memory('fresh'));
        await ob.enqueue(
            'memoryUpsert', {'groupId': 'g1', 'id': 'fresh', 'data': {}});
        await _waitDrained(ob);
        return snapshot;
      },
    );

    expect(await store.getRecord('memories', 'fresh'), isNotNull);
  });

  test('удалённое на сервере по-прежнему уходит из кэша', () async {
    await store.upsert('memories', memory('old'));
    await store.upsert('memories', memory('gone'));

    await reconcileWithServer(
      store: store,
      outbox: ob,
      collection: 'memories',
      scope: scope,
      fetchServer: () async => [memory('old')],
    );

    expect(await store.getRecord('memories', 'gone'), isNull);
    expect(await store.getRecord('memories', 'old'), isNotNull);
  });

  test('отменённая сверка ничего не трогает', () async {
    await store.upsert('memories', memory('gone'));

    final done = await reconcileWithServer(
      store: store,
      outbox: ob,
      collection: 'memories',
      scope: scope,
      fetchServer: () async => null,
    );

    expect(done, isFalse);
    expect(await store.getRecord('memories', 'gone'), isNotNull);
  });
}
