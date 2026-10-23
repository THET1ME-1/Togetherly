// TOG-24: пара теперь поднимается из кэша сразу, и таймеры привязываются к ней
// раньше, чем сервер ответит на загрузку соло-таймеров. Ответ, пришедший после
// привязки, не имеет права лечь в таймеры пары: он подменил бы их на главной и
// записался бы на диск под ключом пары.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:love_app/models/timer_item.dart';
import 'package:love_app/services/pocketbase_service.dart';
import 'package:love_app/services/timer_service.dart';

String _token(String uid) {
  final exp =
      DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000;
  final body = base64Url.encode(utf8.encode(jsonEncode({'id': uid, 'exp': exp})));
  return 'header.$body.signature';
}

http.Response _json(Object body) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('соло-таймеры, пришедшие после привязки к паре, в пару не попадают', () async {
    final pairTimers = [
      TimerItem(
        id: 'system',
        title: 'Влюблённые',
        startDate: DateTime(2026, 8, 5),
        isDefault: true,
        isSystem: true,
      ),
    ];
    SharedPreferences.setMockInitialValues({
      'user_timers_me_g1': TimerItem.encodeList(pairTimers),
    });

    final soloAnswer = Completer<http.Response>();
    final store = AuthStore()..save(_token('me'), RecordModel({'id': 'me'}));
    PocketBaseService().debugUse(PocketBase(
      'https://togetherly.day',
      authStore: store,
      httpClientFactory: () => MockClient((req) {
        if (req.url.path == '/api/collections/users/records/me') {
          return soloAnswer.future;
        }
        return Completer<http.Response>().future;
      }),
    ));

    final service = TimerService();
    final init = service.init();
    await Future<void>.delayed(Duration.zero);
    await service.bindToGroup('g1');
    expect(service.timers.map((t) => t.id), ['system']);

    soloAnswer.complete(_json({
      'id': 'me',
      'solo_timers': [
        {
          'id': 'solo1',
          'title': 'Отпуск',
          'startDate': '2026-01-01T00:00:00.000',
          'isDefault': true,
        },
      ],
    }));
    await init;

    expect(service.timers.map((t) => t.id), ['system'],
        reason: 'на главной у пары должны остаться её таймеры');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('user_timers_me_g1'), contains('"system"'));
    expect(prefs.getString('user_timers_me_g1'), isNot(contains('solo1')),
        reason: 'соло-таймер лёг бы на диск под ключом пары');
  });
}
