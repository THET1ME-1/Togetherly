import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:love_app/models/gift.dart';
import 'package:love_app/screens/chest_screen.dart';
import 'package:love_app/services/chest_sound.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/pair_jar_service.dart';
import 'package:love_app/services/pocketbase_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// TOG-10: «первый подарок из сундука у меня не отобразился». Выбор
/// «Подарить» или «Оставить себе» жил только на экране: ушёл с него, не
/// выбрав, — подарок лёг в запас, и на экране сундука его больше не было
/// вовсе. Теперь неразобранный подарок ждёт выбора под своим сундуком.
void main() {
  late List<String> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory.systemTemp.path,
    );
    SharedPreferences.setMockInitialValues({'chest_sound': false});
    LocaleService.instance.setLanguage(AppLanguage.ru);
    PairJarService.instance.debugReset();
  });
  tearDown(() => PairJarService.instance.debugReset());

  void serverStash(List<Map<String, dynamic>> items) {
    PocketBaseService().debugUse(PocketBase(
      'https://togetherly.day',
      httpClientFactory: () => MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        if (req.url.path.endsWith('/chest_opens/records')) {
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'page': 1,
              'perPage': 100,
              'totalItems': items.length,
              'totalPages': 1,
              'items': [
                for (final i in items) {'collectionId': 'c', 'collectionName': 'chest_opens', 'state': 'stash', ...i},
              ],
            })),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('{"ok":true}', 200, headers: {'content-type': 'application/json'});
      }),
    ));
  }

  Future<void> pumpChest(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => ChestSound.instance.load());
    final t = buildAppTheme(kPalettes.firstWhere((p) => p.name == 'Розовая'), Brightness.light);
    await tester.pumpWidget(MaterialApp(
      theme: ProfileTheme.data(t.scheme!),
      home: ChestScreen(theme: t, groupId: 'g', debugSeasons: const []),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('неразобранный подарок ждёт выбора под сундуком', (tester) async {
    // Подарка нет в таблице шансов, поэтому его название на экране — только
    // надпись выигрыша. Сезон кончился: подарок встаёт под обычный сундук.
    GiftCatalog.registerSeasonal({
      'cocoa': const Gift(key: 'cocoa', price: 0, engine: GiftEngine.response, titleRu: 'Какао', titleEn: 'Cocoa'),
    });
    addTearDown(() => GiftCatalog.registerSeasonal(const {}));
    serverStash([
      {'id': 'aaaaaaaaaaaaaa1', 'prize': 'cocoa', 'day': 'hw|2026-10-20'},
    ]);
    await pumpChest(tester);

    expect(calls, contains('GET /api/collections/chest_opens/records'));
    expect(find.text('Подарок «Какао»'), findsOneWidget, reason: 'подарок из запаса не виден на экране сундука');
    expect(find.text('Подарить'), findsOneWidget);
    expect(find.text('Оставить себе'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('пустой запас — экран как раньше, с кнопкой открытия', (tester) async {
    serverStash(const []);
    await pumpChest(tester);

    expect(find.text('Подарить'), findsNothing);
    expect(find.text('Оставить себе'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });

  test('подарок кончившегося сезона ждёт под обычным сундуком', () {
    expect(stashSlotFor(const [null, 'hw'], 'hw'), 1);
    expect(stashSlotFor(const [null, 'hw'], null), 0);
    expect(stashSlotFor(const [null], 'hw'), 0, reason: 'сезон кончился, а подарок остался');
  });
}
