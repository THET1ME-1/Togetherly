import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

import 'package:love_app/services/offline/local_store.dart';
import 'package:love_app/services/offline/outbox_service.dart';

/// Операция, поставленная в очередь, пока идёт слив, не должна оставаться
/// лежать до следующего действия человека.
///
/// Одно настроение ставит в очередь сразу несколько операций подряд: первая
/// запускает `flush`, а остальные приходят, когда слив уже в полёте. Раньше
/// `flush` в этом случае молча выходил и повторный проход никто не назначал —
/// хвост висел со `attempts == 0`, счётчик «живых» операций не обнулялся, и
/// плашка «Синхронизация…» держалась до следующего действия.
Future<void> _waitDrained(OutboxService ob) async {
  for (var i = 0; i < 200; i++) {
    if (ob.pendingCount.value == 0) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late OutboxService ob;

  setUp(() async {
    await LocalStore.instance.initWith(databaseFactoryMemory, 'test_outbox.db');
    ob = OutboxService.instance;
    await ob.clear();
  });

  tearDown(() => ob.applyOverride = null);

  test('операция из середины слива уходит сама, без нового действия', () async {
    final gate = Completer<void>();
    final applied = <String>[];

    ob.applyOverride = (type, payload) async {
      applied.add('$type:${payload['id']}');
      if (applied.length == 1) await gate.future; // держим первую в полёте
      return true;
    };

    await ob.enqueue('chatUpsert', {'id': 'a', 'groupId': 'g'});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    // Пока первая операция висит в сети, приходит вторая — как второй enqueue
    // при отметке настроения.
    await ob.enqueue('chatUpsert', {'id': 'b', 'groupId': 'g'});
    gate.complete();

    await _waitDrained(ob);

    expect(applied, ['chatUpsert:a', 'chatUpsert:b']);
    expect(ob.pendingCount.value, 0);
    expect(ob.activeCount.value, 0);
  });

  test('очередь пустеет и когда операций сразу три', () async {
    final gate = Completer<void>();
    var seen = 0;

    ob.applyOverride = (type, payload) async {
      seen++;
      if (seen == 1) await gate.future;
      return true;
    };

    await ob.enqueue('chatUpsert', {'id': 'a', 'groupId': 'g'});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await ob.enqueue('moodUpsert', {
      'entry': {'id': 'm1'},
      'groupId': 'g',
    });
    await ob.enqueue('groupSetMemberMood', {'groupId': 'g', 'uid': 'u'});
    gate.complete();

    await _waitDrained(ob);

    expect(seen, 3);
    expect(ob.activeCount.value, 0);
  });
}
