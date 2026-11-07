import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:sembast/sembast_memory.dart';

import 'package:love_app/services/offline/local_store.dart';
import 'package:love_app/services/offline/outbox_service.dart';
import 'package:love_app/services/pocketbase_service.dart';

/// Плашка «Не сохранилось — повторить» висела после удаления сообщения (TOG-79).
///
/// Обращение 569 (iPhone, 02.11.2026): кружок не отправился, человек удалил его
/// из чата, а сверху так и висела красная плашка. Удаление ставило в очередь
/// правку, но сдавшуюся отправку той же записи из «отравленных» не снимало, а у
/// плашки было только «повторить» — убрать её было нельзя до выхода из аккаунта.
Future<void> _poisonCreate(String id) async {
  final db = (await LocalStore.instance.database())!;
  await intMapStoreFactory.store('outbox').add(db, {
    'type': 'chatUpsert',
    'payload': {
      'groupId': 'rc6d6b8c6c2e7a2',
      'id': id,
      'msg': {'uid': 'q1qcc9rrh6ggavi', 'text': 'кружок', 'ts': 1},
    },
    'attempts': 4,
  });
  await OutboxService.instance.flush();
}

void main() {
  late OutboxService ob;

  setUp(() async {
    await LocalStore.instance.initWith(databaseFactoryMemory, 'poison_drop.db');
    ob = OutboxService.instance;
    await ob.clear();
    // Сервер отвергает создание: так сообщение и уходит в «отравленные».
    PocketBaseService().debugUse(PocketBase(
      'https://togetherly.day',
      httpClientFactory: () => MockClient((req) async => http.Response.bytes(
            utf8.encode(jsonEncode({'code': 400, 'message': 'Failed to create record.', 'data': {}})),
            400,
            headers: {'content-type': 'application/json; charset=utf-8'},
          )),
    ));
  });

  test('удаление записи снимает её сдавшуюся отправку', () async {
    await _poisonCreate('aaaaaaaaaaaaaa1');
    await _poisonCreate('bbbbbbbbbbbbbb2');
    expect(ob.poisonCount.value, 2);

    await ob.dropPoisonFor('chat_messages', 'aaaaaaaaaaaaaa1');

    expect(ob.poisonCount.value, 1, reason: 'чужая сдавшаяся отправка остаётся');
    expect(ob.isPoisoned('chat_messages', 'aaaaaaaaaaaaaa1'), isFalse);
    expect(ob.isPoisoned('chat_messages', 'bbbbbbbbbbbbbb2'), isTrue);
  });

  test('«Убрать» с плашки выбрасывает все сдавшиеся отправки', () async {
    await _poisonCreate('aaaaaaaaaaaaaa1');
    await _poisonCreate('bbbbbbbbbbbbbb2');

    await ob.dropAllPoison();

    expect(ob.poisonCount.value, 0);
    expect(ob.isPoisoned('chat_messages', 'bbbbbbbbbbbbbb2'), isFalse);
  });

  test('удаление сообщения в чате снимает его сдавшуюся отправку', () {
    final src = File('lib/services/chat_service.dart').readAsStringSync();
    final delete = src.split('Future<void> delete(')[1].split('\n  }\n')[0];
    expect(delete, contains("dropPoisonFor('chat_messages', messageId)"));
  });
}
