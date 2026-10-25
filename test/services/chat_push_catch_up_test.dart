// TOG-36, отзыв в Google Play 23.10.2026 (Redmi 14C, 1.39.0): «иногда, когда
// половинка пишет, сообщение в чате появляется не сразу, а в уведомлении уже
// видно, надо ждать или перезайти».
//
// Вся цепочка в Dart: нативная часть шлёт в канал love_app/push_arrived вид
// пуша, открытый чат сразу дотягивает переписку с сервера. Живого канала здесь
// нет, как у сокета, умершего молча; опрос раз в 15 секунд до конца теста не
// наступает, так что принести сообщение может только пуш.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show SizedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:sembast/sembast_memory.dart' show databaseFactoryMemory;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:love_app/services/offline/local_store.dart';
import 'package:love_app/services/pb_realtime_service.dart';
import 'package:love_app/services/pocketbase_service.dart';
import 'package:love_app/services/push_arrivals.dart';

Map<String, dynamic> _message(String id, String text, int ts) => {
      'id': id,
      'collectionId': 'c',
      'collectionName': 'chat_messages',
      'group_id': 'g',
      'user_uid': 'partner',
      'text': text,
      'ts': ts,
      'created': '2026-10-25 10:00:0${ts ~/ 1000}.000Z',
      'updated': '2026-10-25 10:00:0${ts ~/ 1000}.000Z',
    };

void main() {
  late List<Map<String, dynamic>> rows;

  setUp(() async {
    await LocalStore.instance.initWith(databaseFactoryMemory, 'chat_push.db');
    SharedPreferences.setMockInitialValues({});
    rows = [_message('mmmmmmmmmmmmmm1', 'привет', 1000)];
    PocketBaseService().debugUse(PocketBase(
      'https://togetherly.day',
      authStore: AuthStore()..save('token', RecordModel({'id': 'me', 'collectionName': 'users'})),
      httpClientFactory: () => MockClient((req) async {
        // Пропуск Centrifugo не приходит вовсе: живого канала нет.
        if (req.url.path.startsWith('/api/centrifugo/')) {
          return Completer<http.Response>().future;
        }
        if (req.url.path == '/api/collections/chat_messages/records') {
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'page': 1,
              'perPage': 50,
              'totalItems': rows.length,
              'totalPages': 1,
              'items': rows,
            })),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('{"message":"нет"}', 400,
            headers: {'content-type': 'application/json'});
      }),
    ));
  });

  Future<void> nativeSays(String kind) async {
    const codec = StandardMethodCodec();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      PushArrivals.channelName,
      codec.encodeMethodCall(MethodCall('arrived', kind)),
      (_) {},
    );
  }

  testWidgets('пуш о сообщении при открытом чате сразу приносит его в переписку',
      (tester) async {
    final texts = <List<String>>[];
    final sub = PbRealtimeService().watchMessages('g', limit: 50).listen(
          (list) => texts.add([for (final r in list) r.data['text'] as String]),
        );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(texts.last, ['привет'], reason: 'чат не прочитал переписку с сервера');

    rows.add(_message('mmmmmmmmmmmmmm2', 'ты где?', 2000));
    await nativeSays('chat');
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(texts.last, ['привет', 'ты где?'],
        reason: 'уведомление пришло, а переписка ждёт сокет');

    // Отписка ждёт сеть: в поддельном времени её докручивает pump ниже.
    unawaited(sub.cancel());
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('пуш другого вида чат не дёргает', (tester) async {
    var fetches = 0;
    final sub = PbRealtimeService().watchMessages('g', limit: 50).listen((_) {});
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    PocketBaseService().debugUse(PocketBase(
      'https://togetherly.day',
      authStore: AuthStore()..save('token', RecordModel({'id': 'me', 'collectionName': 'users'})),
      httpClientFactory: () => MockClient((req) async {
        if (req.url.path == '/api/collections/chat_messages/records') fetches++;
        return Completer<http.Response>().future;
      }),
    ));
    await nativeSays('mood');
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(fetches, 0);
    unawaited(sub.cancel());
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });
}
