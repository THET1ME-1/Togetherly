import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:sembast/sembast_memory.dart';

import 'package:love_app/models/scope_reconcile.dart';
import 'package:love_app/services/offline/local_store.dart';
import 'package:love_app/services/offline/record_scope.dart';

/// Воспоминание удаляется с сервера НАСОВСЕМ (очередь шлёт `hard: true`), и
/// надгробия после него не остаётся: на проде ни одной записи `deleted = true`
/// при 109 069 живых. Значит партнёр, чей телефон в ту секунду не держал
/// сокет, не узнает об удалении никогда — инкремент по `updated` удалённую
/// строку не приносит, и она живёт в его кэше вечно. Жалоба 19 августа 2026:
/// «он удалил, у меня осталось, и удалить не могу».
void main() {
  late LocalStore store;

  RecordModel memory(String id, {required String group}) => RecordModel({
        'id': id,
        'collectionName': 'memories',
        'group_id': group,
        'deleted': false,
        'created_at': '2026-08-19 07:00:00.000Z',
        'updated': '2026-08-19 07:00:00.000Z',
      });

  setUp(() async {
    store = LocalStore.instance;
    await store.initWith(databaseFactoryMemory, 'test_reconcile.db');
    await store.clearAll();
  });

  test('сверка убирает из кэша то, чего на сервере уже нет', () async {
    const scope = RecordScope(
      'memories:g=g1',
      equals: {'group_id': 'g1', 'deleted': false},
    );
    await store.upsert('memories', memory('m1', group: 'g1'));
    await store.upsert('memories', memory('m2', group: 'g1'));
    // Чужая пара в ту же коллекцию: сверка одной области её не трогает.
    await store.upsert('memories', memory('m9', group: 'g2'));

    await store.reconcileScope('memories', scope, [memory('m1', group: 'g1')]);

    final left = await store.getScope('memories', scope);
    expect(left.map((r) => r.id), ['m1']);
    expect(await store.getRecord('memories', 'm9'), isNotNull);
  });

  test('неотправленное своё не сносим', () async {
    const scope = RecordScope(
      'memories:g=g1',
      equals: {'group_id': 'g1', 'deleted': false},
    );
    await store.upsert('memories', memory('mine', group: 'g1'));

    // Записи ещё нет на сервере: она лежит в очереди отправки.
    await store.reconcileScope('memories', scope, const [],
        protectIds: {'mine'});

    expect(await store.getRecord('memories', 'mine'), isNotNull);
  });

  group('mayReconcileScope', () {
    const now = 1786000000000;

    test('первый заход за запуск сверяет', () {
      expect(mayReconcileScope(nowMs: now, lastAtMs: 0), isTrue);
    });

    test('сразу следом — нет', () {
      expect(mayReconcileScope(nowMs: now, lastAtMs: now - 60000), isFalse);
    });

    test('через положенное время — снова да', () {
      expect(
        mayReconcileScope(nowMs: now, lastAtMs: now - kScopeReconcileGapMs),
        isTrue,
      );
    });

    test('отметка из будущего не открывает сверку', () {
      expect(mayReconcileScope(nowMs: now, lastAtMs: now + 60000), isFalse);
    });
  });
}
