import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:sembast/sembast_memory.dart';

import 'package:love_app/services/offline/local_store.dart';
import 'package:love_app/services/pb_data_service.dart';
import 'package:love_app/services/pocketbase_service.dart';

/// Обращение 409, 21.10.2026: «ваш бот сам за меня отвечает». «Окей»,
/// написанное без сети в 11:27, очередь довезла в 13:12, и сервер поставил
/// ему время доставки: сообщение встало ответом на другое. По одному `ts`
/// сервер не отличит сбитые часы от поздней доставки, поэтому рядом с временем
/// написания уходят часы телефона в момент отправки (`sent_at`): их разница с
/// серверными и есть сдвиг часов, и сервер ставит время написания.
void main() {
  late List<Map<String, dynamic>> created;

  http.Response json(Object body, int status) => http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  setUp(() async {
    created = [];
    await LocalStore.instance.initWith(databaseFactoryMemory, 'chat_sent_at.db');
  });

  final composed = DateTime.now().millisecondsSinceEpoch - 2 * 3600 * 1000;
  final msg = {'uid': 'katya', 'name': 'Катя', 'text': 'окей', 'ts': composed};

  void expectSentAtNow(Map<String, dynamic> body) {
    expect(body['ts'], composed, reason: 'время написания уходит как было');
    final sentAt = body['sent_at'];
    expect(sentAt, isA<int>(), reason: 'без часов отправки сервер не отличит офлайн от сбитых часов');
    final drift = (DateTime.now().millisecondsSinceEpoch - (sentAt as int)).abs();
    expect(drift, lessThan(10000), reason: 'часы телефона — в момент отправки, а не написания');
  }

  test('прямое создание несёт часы отправки', () async {
    PocketBaseService().debugUse(PocketBase(
      'https://togetherly.day',
      httpClientFactory: () => MockClient((req) async {
        if (req.method == 'POST') {
          final body = Map<String, dynamic>.from(jsonDecode(req.body) as Map);
          created.add(body);
          return json({...body, 'collectionId': 'c', 'collectionName': 'chat_messages'}, 200);
        }
        return json({'code': 404, 'message': 'not found', 'data': {}}, 404);
      }),
    ));

    final rec = await PbDataService().chatSendRecord('group', 'abcdefghijklmno', msg);

    expect(rec, isNotNull);
    expect(created, hasLength(1));
    expectSentAtNow(created.single);
  });

  test('запасной путь после обрыва тоже несёт часы отправки', () async {
    var posts = 0;
    PocketBaseService().debugUse(PocketBase(
      'https://togetherly.day',
      httpClientFactory: () => MockClient((req) async {
        if (req.method == 'POST') {
          posts++;
          // Первая попытка — обрыв сети, дальше очередь идёт прежним путём.
          if (posts == 1) throw const SocketException('сеть пропала');
          final body = Map<String, dynamic>.from(jsonDecode(req.body) as Map);
          created.add(body);
          return json({...body, 'collectionId': 'c', 'collectionName': 'chat_messages'}, 200);
        }
        return json({'code': 404, 'message': 'not found', 'data': {}}, 404);
      }),
    ));

    final ok = await PbDataService().chatSend('group', 'abcdefghijklmno', msg);

    expect(ok, isTrue);
    expect(created, isNotEmpty);
    expectSentAtNow(created.last);
  });
}
