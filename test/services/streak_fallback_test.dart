import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';

import 'package:love_app/services/pb_data_service.dart';
import 'package:love_app/services/pocketbase_service.dart';
import 'package:love_app/utils/calendar_day.dart';

/// TOG-26: серия пары, где оба заходят каждый день, не должна рваться.
///
/// Когда маршрут отметки дня отвечает отказом (404 или иным 4xx), приложение
/// отмечает день само, чтением и записью пары. Сервер засчитывает день и
/// тогда, когда второй пришёл назавтра по своим часам, а запасной путь видел
/// во вчерашнем ожидании партнёра просто «не сегодня» и затирал его своим:
/// вчерашний заход партнёра пропадал, и серия рвалась.
void main() {
  String day(int shift) {
    final d = calendarDay(DateTime.now(), shift);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  late List<Map<String, dynamic>> patches;

  void serve(Map<String, dynamic> group) {
    patches = [];
    PocketBaseService().debugUse(PocketBase(
      'https://togetherly.day',
      authStore: AuthStore()..save('token', RecordModel({'id': 'me', 'collectionName': 'users'})),
      httpClientFactory: () => MockClient((req) async {
        if (req.url.path == '/api/group/record-activity') {
          return http.Response('{"message":"нет"}', 404,
              headers: {'content-type': 'application/json'});
        }
        if (req.url.path == '/api/collections/groups/records' && req.method == 'GET') {
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'page': 1, 'perPage': 1, 'totalItems': 1, 'totalPages': 1,
              'items': [group],
            })),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (req.url.path.startsWith('/api/collections/groups/records/') && req.method == 'PATCH') {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          patches.add(body);
          return http.Response.bytes(utf8.encode(jsonEncode({...group, ...body})), 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }
        return http.Response('{}', 404, headers: {'content-type': 'application/json'});
      }),
    ));
  }

  Map<String, dynamic> group({required String pendingDate, required String pendingUid}) => {
        'id': 'gggggggggggggg1',
        'collectionId': 'c',
        'collectionName': 'groups',
        'members': ['me', 'partner'],
        'streak_days': 5,
        'streak_last_opened_date': day(-2),
        'streak_pending_date': pendingDate,
        'streak_pending_uid': pendingUid,
        'active_mascot_id': '',
        'mascot_streaks': <String, dynamic>{},
      };

  test('вчерашнее ожидание партнёра запасной путь не затирает', () async {
    serve(group(pendingDate: day(-1), pendingUid: 'partner'));
    await PbDataService().recordGroupActivity('gggggggggggggg1', 'me');
    expect(
      patches.where((p) => p['streak_pending_uid'] == 'me'),
      isEmpty,
      reason: 'вчерашний заход партнёра пропал бы, и серия порвалась',
    );
  });

  test('своё вчерашнее ожидание сменяется сегодняшним, как и раньше', () async {
    serve(group(pendingDate: day(-1), pendingUid: 'me'));
    await PbDataService().recordGroupActivity('gggggggggggggg1', 'me');
    expect(patches.single['streak_pending_date'], day(0));
  });

  test('давнее ожидание партнёра (позавчера) уже не спасти — место свободно', () async {
    serve(group(pendingDate: day(-3), pendingUid: 'partner'));
    await PbDataService().recordGroupActivity('gggggggggggggg1', 'me');
    expect(patches.single['streak_pending_uid'], 'me');
  });

  test('сегодняшний заход партнёра засчитывает день, как и раньше', () async {
    serve(group(pendingDate: day(0), pendingUid: 'partner'));
    await PbDataService().recordGroupActivity('gggggggggggggg1', 'me');
    expect(patches.single['streak_last_opened_date'], day(0));
  });
}
