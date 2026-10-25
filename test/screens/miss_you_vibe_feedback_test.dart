import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:sembast/sembast_memory.dart' show databaseFactoryMemory;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:love_app/screens/miss_you_screen.dart';
import 'package:love_app/services/offline/local_store.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/pocketbase_service.dart';
import 'package:love_app/theme/app_theme.dart';

/// TOG-40, обращение 377 (iPhone, 25.10.2026): «Думаю о тебе» и «Хочу
/// обнять» уходили, но «нету анимации, только после перехода засчитывается».
/// У человека не было живого канала (1.39 из Украины), и подтверждение не
/// приходило вовсе: число стояло, пока не выйдешь с экрана.
///
/// Здесь живого канала тоже нет: сервер подменён, а рассылки нет никакой.
void main() {
  late List<Map<String, dynamic>> rows;
  late List<String> calls;

  setUp(() async {
    // Записи «Скучаю» идут через офлайн-кэш: без открытого хранилища подписка
    // так и ждала бы его и ничего не спрашивала у сервера.
    await LocalStore.instance.initWith(databaseFactoryMemory, 'miss_you_vibe.db');
    SharedPreferences.setMockInitialValues({});
    LocaleService.instance.setLanguage(AppLanguage.ru);
    calls = [];
    rows = [
      {
        'id': 'mmmmmmmmmmmmmm1',
        'collectionId': 'c',
        'collectionName': 'miss_you',
        'group_id': 'g',
        'user_uid': 'me',
        'count': 10,
        'by_vibe': {'thinking_of_you': 3, 'miss_you': 7},
      },
      {
        'id': 'mmmmmmmmmmmmmm2',
        'collectionId': 'c',
        'collectionName': 'miss_you',
        'group_id': 'g',
        'user_uid': 'partner',
        'count': 12,
        'by_vibe': {'thinking_of_you': 5, 'miss_you': 7},
      },
    ];
    PocketBaseService().debugUse(PocketBase(
      'https://togetherly.day',
      authStore: AuthStore()..save('token', RecordModel({'id': 'me', 'collectionName': 'users'})),
      httpClientFactory: () => MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        // Живого канала нет, как у человека из обращения: пропуск Centrifugo
        // не приходит вовсе. Мгновенный отказ закрутил бы переподключение
        // таймерами, которые переживают тест.
        if (req.url.path.startsWith('/api/centrifugo/')) return Completer<http.Response>().future;
        if (req.url.path == '/api/collections/miss_you/records') {
          return http.Response.bytes(
            utf8.encode(jsonEncode({'page': 1, 'perPage': 500, 'totalItems': rows.length, 'totalPages': 1, 'items': rows})),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (req.url.path == '/api/group/miss-you') {
          final body = jsonDecode(req.body) as Map;
          if (body['history'] == true) {
            return http.Response('{"ok":true,"events":[]}', 200, headers: {'content-type': 'application/json'});
          }
          final vibe = body['vibe'] as String;
          final me = rows.first;
          me['count'] = (me['count'] as int) + 1;
          final byVibe = Map<String, dynamic>.from(me['by_vibe'] as Map);
          byVibe[vibe] = ((byVibe[vibe] as int?) ?? 0) + 1;
          me['by_vibe'] = byVibe;
          return http.Response('{"ok":true,"count":${me['count']}}', 200, headers: {'content-type': 'application/json'});
        }
        // Остальное, и пропуск Centrifugo тоже, отказывает, как в обычной
        // тестовой среде: живого канала здесь нет, ровно как у человека.
        return http.Response('{"message":"нет"}', 400, headers: {'content-type': 'application/json'});
      }),
    ));
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(393, 1400)),
      child: MaterialApp(
        home: MissYouScreen(
          theme: AppThemes.byIndex(7),
          groupId: 'g',
          myUid: 'me',
          partnerUid: 'partner',
          partnerName: 'Аня',
        ),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Число внутри плитки с подписью [label].
  Finder inChip(String label, String text) => find.descendant(
    of: find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first,
    matching: find.text(text),
  );

  testWidgets('нажатие сразу прибавляет у плитки и в общем счёте, и число держится', (tester) async {
    await pumpScreen(tester);
    expect(inChip('Думаю о тебе', '3'), findsOneWidget, reason: 'экран не прочитал счёт с сервера');
    expect(find.text('10'), findsOneWidget);

    await tester.tap(find.text('Думаю о тебе'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(inChip('Думаю о тебе', '4'), findsOneWidget, reason: 'плитка не отозвалась на нажатие');
    // Число в пилюле «Ты» набегает за 420 мс.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('11'), findsOneWidget, reason: 'общий счёт не сдвинулся, а сервер считает любой импульс');

    // Живого канала нет: подтверждение экран берёт сам, перечитав записи.
    for (var i = 0; i < 150; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(inChip('Думаю о тебе', '4'), findsOneWidget, reason: 'надбавка протухла, а подтверждения так и не было');
    expect(find.text('11'), findsOneWidget);
    expect(calls.where((c) => c == 'GET /api/collections/miss_you/records').length, greaterThan(1),
        reason: 'после отправки экран не перечитал записи');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });
}
