import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:sembast/sembast_memory.dart';

import 'package:love_app/services/offline/local_store.dart';
import 'package:love_app/services/offline/outbox_service.dart';
import 'package:love_app/services/pb_data_service.dart';
import 'package:love_app/services/pocketbase_service.dart';

/// Правка сообщения, которого нет на сервере, крутилась в очереди без конца.
///
/// Обращение 336 (19.10.2026, iPhone, 1.37.0): плашка «Не сохранилось —
/// повторить» не уходила, нажатие на неё через полминуты возвращало её назад.
/// В очереди лежала правка сообщения `zuhg5864cftyb1u`, а на сервере такого
/// сообщения не было вовсе. Правка уходила PATCH-ем, получала 404, и
/// `_upsertById` пытался СОЗДАТЬ сообщение из её полей. В правке только
/// изменённые поля, без пары и автора, — сервер отвечал 400, и после пяти
/// попыток операция падала в «отравленные».
http.Response _json(Object body, int code) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      code,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

final _notFound = _json({
  'code': 404,
  'message': "The requested resource wasn't found.",
  'data': {},
}, 404);

final _createRefused = _json({
  'code': 400,
  'message': 'Failed to create record.',
  'data': {},
}, 400);

Future<void> _waitDrained(OutboxService ob) async {
  for (var i = 0; i < 200; i++) {
    if (ob.pendingCount.value == 0) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late OutboxService ob;
  late List<String> calls;

  /// Сервер, на котором сообщения нет: правка — 404, создание — 400.
  void serverWithoutMessage() {
    calls = [];
    PocketBaseService().debugUse(PocketBase(
      'https://togetherly.day',
      httpClientFactory: () => MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        if (req.method == 'POST') return _createRefused;
        return _notFound;
      }),
    ));
  }

  setUp(() async {
    await LocalStore.instance.initWith(databaseFactoryMemory, 'chat_update_missing.db');
    ob = OutboxService.instance;
    await ob.clear();
    serverWithoutMessage();
  });

  test('правка пропавшего сообщения не встаёт в «Не сохранилось»', () async {
    await ob.enqueue('chatUpdate', {
      'id': 'zuhg5864cftyb1u',
      'fields': {'deleted': true, 'text': ''},
    });
    await _waitDrained(ob);

    expect(ob.pendingCount.value, 0,
        reason: 'Править нечего — операция выполнена, а не ждёт повтора');
    expect(ob.poisonCount.value, 0);
    expect(calls.where((c) => c.startsWith('POST')), isEmpty,
        reason: 'Из полей правки сообщение не создать: в них нет ни пары, ни автора');
  });

  test('реакция на пропавшее сообщение тоже не крутится в очереди', () async {
    await ob.enqueue('chatSetReaction', {
      'id': 'zuhg5864cftyb1u',
      'uid': 'q1qcc9rrh6ggavi',
      'emoji': '❤️',
    });
    await _waitDrained(ob);

    expect(ob.pendingCount.value, 0);
    expect(ob.poisonCount.value, 0);
  });

  test('правка ждёт, пока своего повтора ждёт создание сообщения', () async {
    // Сообщение не доехало до сервера и лежит в «отравленных». Повтор вернёт
    // в очередь и создание, и правку, — правку нельзя терять раньше.
    final ok = await PbDataService().chatUpdate(
      'zuhg5864cftyb1u',
      {'text': 'исправила'},
      missingIsDone: false,
    );

    expect(ok, isFalse);
    expect(calls.where((c) => c.startsWith('POST')), isEmpty);
  });

  test('правка не теряется, когда создание сдаётся в том же проходе', () async {
    // Сообщение уже четыре раза не создалось. Пятый отказ уводит его в
    // «отравленные», и тем же проходом очередь доходит до правки.
    final db = (await LocalStore.instance.database())!;
    final outbox = intMapStoreFactory.store('outbox');
    await outbox.add(db, {
      'type': 'chatUpsert',
      'payload': {
        'groupId': 'rc6d6b8c6c2e7a2',
        'id': 'zuhg5864cftyb1u',
        'msg': {'uid': 'q1qcc9rrh6ggavi', 'text': 'привет', 'ts': 1},
      },
      'attempts': 4,
    });
    await outbox.add(db, {
      'type': 'chatUpdate',
      'payload': {
        'id': 'zuhg5864cftyb1u',
        'fields': {'text': 'привет!'},
      },
      'attempts': 0,
    });

    await ob.flush();

    expect(ob.poisonCount.value, 1);
    expect(ob.pendingCount.value, 1,
        reason: 'Правка ждёт повтора вместе с созданием, а не выброшена');
  });

  test('правка живого сообщения уходит как раньше', () async {
    calls = [];
    PocketBaseService().debugUse(PocketBase(
      'https://togetherly.day',
      httpClientFactory: () => MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        return _json({'id': 'abc123def456ghi', 'text': 'исправила'}, 200);
      }),
    ));

    final ok = await PbDataService().chatUpdate('abc123def456ghi', {'text': 'исправила'});

    expect(ok, isTrue);
    expect(calls, ['PATCH /api/collections/chat_messages/records/abc123def456ghi']);
  });
}
