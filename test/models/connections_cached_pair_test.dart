// TOG-24: при закрытом сервере главная показывала «Нет таймеров», виджет
// таймера стирался, а «Дней вместе» считал от даты соединения. Пара при этом
// лежала на телефоне: менеджер связей поднимал её из кэша, но объявлял о ней
// только после ответа сервера. На эмуляторе с закрытым адресом запрос пары
// висел 2 минуты 15 секунд, и всё это время главная считала, что пары нет, и
// не привязывала к ней таймеры.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:love_app/models/connections_manager.dart';
import 'package:love_app/services/pocketbase_service.dart';

String _token(String uid) {
  final exp =
      DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000;
  final body = base64Url.encode(utf8.encode(jsonEncode({'id': uid, 'exp': exp})));
  return 'header.$body.signature';
}

Map<String, Object> _cachedPair() => {
      'uid': 'me',
      'connections': jsonEncode([
        {'id': 'solo', 'isSolo': true},
        {
          'id': 'c1',
          'isPaired': true,
          'pairId': 'g1',
          'inviteCode': 'AB12CD',
          'partnerName': 'Аня',
          'startDate': '2026-08-05T00:00:00.000',
          'members': [
            {'uid': 'me', 'name': 'Я', 'avatar': ''},
            {'uid': 'p1', 'name': 'Аня', 'avatar': ''},
          ],
        },
      ]),
      'activeConnectionIndex': 1,
    };

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(_cachedPair());
    final store = AuthStore()..save(_token('me'), RecordModel({'id': 'me'}));
    // Сервер закрыт: запрос не отвечает и не обрывается, как у провайдера,
    // который глотает пакеты.
    PocketBaseService().debugUse(PocketBase(
      'https://togetherly.day',
      authStore: store,
      httpClientFactory: () =>
          MockClient((_) => Completer<http.Response>().future),
    ));
  });

  test('пара из кэша объявлена, пока сервер не ответил', () async {
    final manager = ConnectionsManager();
    final seen = <String>[];
    manager.addListener(() {
      final c = manager.activeConnection;
      seen.add('${c?.isPaired}:${c?.pairId}');
    });

    unawaited(manager.init(myName: 'Я'));
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(seen, contains('true:g1'),
        reason: 'по этому событию главная привязывает таймеры и виджеты к паре; '
            'без него до ответа сервера на экране «Нет таймеров»');
  });

  test('до чтения кэша «пары нет» не объявляется', () async {
    final manager = ConnectionsManager();
    final seen = <String>[];
    manager.addListener(() {
      final c = manager.activeConnection;
      seen.add('${c?.isPaired}:${c?.pairId}');
    });

    unawaited(manager.init(myName: 'Я'));
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(seen, everyElement('true:g1'),
        reason: 'главная читает пустое состояние как распад пары: стирает виджет '
            'таймера, убирает счётчик дней из шторки и выключает показ геопозиции');
  });

  test('пара пропала из списка, который её показывал, — партнёр вышел', () {
    expect(pairLeftList(pairId: 'g1', shown: {'g1'}, now: {}), isTrue);
    expect(pairLeftList(pairId: 'g1', shown: {'g1', 'g2'}, now: {'g2'}), isTrue);
  });

  test('список пару ещё не показывал или показывает — она на месте', () {
    expect(pairLeftList(pairId: 'g1', shown: {}, now: {}), isFalse);
    expect(pairLeftList(pairId: 'g1', shown: {'g1'}, now: {'g1'}), isFalse);
    expect(pairLeftList(pairId: '', shown: {''}, now: {}), isFalse);
  });

  test('пустой список групп из пустого кэша пару не распускает', () async {
    // Кэш групп пуст (переустановка с восстановлением настроек, сброс кэша), а
    // сервер недоступен: живой список отдаёт пустоту раньше сервера.
    PocketBaseService().debugUse(PocketBase(
      'https://togetherly.day',
      authStore: AuthStore()..save(_token('me'), RecordModel({'id': 'me'})),
      httpClientFactory: () => MockClient(
          (_) async => throw const SocketException('сеть не пускает к серверу')),
    ));
    final manager = ConnectionsManager();
    await manager.init(myName: 'Я');
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(manager.activeConnection?.pairId, 'g1',
        reason: 'список ещё ни разу не показывал эту пару: пустота в нём '
            'говорит о кэше, а не о распаде');
    expect(manager.activeConnection?.isPaired, isTrue);
  });
}
