import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:sembast/sembast_memory.dart' show databaseFactoryMemory;

import 'package:love_app/services/mascot_repository.dart';
import 'package:love_app/services/offline/local_store.dart';
import 'package:love_app/services/pocketbase_service.dart';

/// TOG-26: после возврата серии за ролик сегодняшний заход не пропадает.
///
/// Свой сегодняшний заход человек мог уже отдать вчерашнему ожиданию: сервер
/// считает соседний день общим и в таком случае ничего не пишет. Возврат
/// ставит последним общим днём вчера, вчерашнее ожидание становится
/// устаревшим, и сегодняшний день ждал, пока человек снова откроет
/// приложение. Поэтому после возврата заход отмечается заново.
void main() {
  late List<Map<String, dynamic>> calls;

  setUp(() async {
    await LocalStore.instance.initWith(databaseFactoryMemory, 'streak_restore_today.db');
    calls = [];
    PocketBaseService().debugUse(PocketBase(
      'https://togetherly.day',
      authStore: AuthStore()..save('token', RecordModel({'id': 'me', 'collectionName': 'users'})),
      httpClientFactory: () => MockClient((req) async {
        if (req.url.path == '/api/group/record-activity') {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          calls.add(body);
          final reply = body['restore'] == true
              ? {
                  'ok': true,
                  'streak': 12,
                  'mascot_streaks': {'m': {'s': 12, 'd': '2026-10-24'}},
                  'streak_days': 12,
                  'streak_last_opened_date': '2026-10-24',
                }
              : {'ok': true, 'pending': true};
          return http.Response(jsonEncode(reply), 200,
              headers: {'content-type': 'application/json'});
        }
        return http.Response('{}', 404, headers: {'content-type': 'application/json'});
      }),
    ));
  });

  test('удачный возврат следом отмечает сегодняшний заход', () async {
    final ok = await MascotRepository().restoreStreak('gggggggggggggg1');
    expect(ok, isTrue);
    expect(calls.map((c) => c['restore'] == true ? 'возврат' : 'заход').toList(),
        ['возврат', 'заход'],
        reason: 'сегодняшний заход остался съеденным вчерашним ожиданием');
    expect(calls.last['uid'], 'me');
  });

  test('отказ в возврате заход не дёргает', () async {
    PocketBaseService().debugUse(PocketBase(
      'https://togetherly.day',
      authStore: AuthStore()..save('token', RecordModel({'id': 'me', 'collectionName': 'users'})),
      httpClientFactory: () => MockClient((req) async {
        calls.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response('{"ok":false,"error":"nothing_to_restore"}', 409,
            headers: {'content-type': 'application/json'});
      }),
    ));
    expect(await MascotRepository().restoreStreak('gggggggggggggg1'), isFalse);
    expect(calls, hasLength(1));
  });
}
