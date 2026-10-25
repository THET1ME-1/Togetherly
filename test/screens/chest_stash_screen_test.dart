import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:love_app/models/gift.dart';
import 'package:love_app/screens/chest_screen.dart';
import 'package:love_app/services/chest_service.dart';
import 'package:love_app/services/chest_sound.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/pair_jar_service.dart';
import 'package:love_app/services/pocketbase_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Подарки из сундука, которые ждут решения, на экране сундука.
///
/// TOG-10 (21.10.2026): «первый подарок из сундука у меня не отобразился» —
/// подарок, оставленный без выбора, пропадал с экрана сундука. Тогда его
/// поставили выбором вместо кнопки «Открыть».
///
/// TOG-38, обращение 480 (25.10.2026): «Меня насильно заставляют выбирать и не
/// дают выбрать позже… А если отправить, то заставляет отправлять следующий
/// неотправленный». Выбор из запаса стоял под обоими сундуками при каждом
/// заходе, и открыть сундук было нельзя, пока не разберёшь весь запас.
/// Теперь запас — строка «В запасе: N» под кнопкой, разбирают его листом,
/// когда захочется, а свежий подарок можно отложить кнопкой «Позже».
void main() {
  late List<String> calls;
  late List<Map<String, dynamic>> stash;

  setUp(() {
    calls = [];
    stash = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory.systemTemp.path,
    );
    SharedPreferences.setMockInitialValues({'chest_sound': false});
    LocaleService.instance.setLanguage(AppLanguage.ru);
    PairJarService.instance.debugReset();
    GiftCatalog.registerSeasonal({
      'cocoa': const Gift(key: 'cocoa', price: 0, engine: GiftEngine.response, titleRu: 'Какао', titleEn: 'Cocoa'),
      'tea': const Gift(key: 'tea', price: 0, engine: GiftEngine.response, titleRu: 'Чай', titleEn: 'Tea'),
    });
    PocketBaseService().debugUse(PocketBase(
      'https://togetherly.day',
      httpClientFactory: () => MockClient((req) async {
        final body = req.body.isEmpty ? null : jsonDecode(req.body);
        final openId = body is Map ? body['openId'] : null;
        calls.add('${req.method} ${req.url.path}${openId == null ? '' : ' $openId'}');
        if (req.url.path.endsWith('/chest_opens/records')) {
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'page': 1,
              'perPage': 100,
              'totalItems': stash.length,
              'totalPages': 1,
              'items': [
                for (final i in stash) {'collectionId': 'c', 'collectionName': 'chest_opens', 'state': 'stash', ...i},
              ],
            })),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (req.url.path == '/api/chest/keep' || req.url.path == '/api/chest/give') {
          stash.removeWhere((i) => i['id'] == openId);
        }
        return http.Response('{"ok":true}', 200, headers: {'content-type': 'application/json'});
      }),
    ));
  });
  tearDown(() {
    PairJarService.instance.debugReset();
    GiftCatalog.registerSeasonal(const {});
  });

  Map<String, dynamic> item(String id, String prize) => {'id': id, 'prize': prize, 'day': 'hw|2026-10-20'};

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpChest(
    WidgetTester tester, {
    ChestStashItem? choice,
    Size size = const Size(412, 915),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => ChestSound.instance.load());
    final t = buildAppTheme(kPalettes.firstWhere((p) => p.name == 'Розовая'), Brightness.light);
    await tester.pumpWidget(MaterialApp(
      theme: ProfileTheme.data(t.scheme!),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: ChestScreen(theme: t, groupId: 'g', partnerName: 'Аня', debugSeasons: const [], debugChoice: choice),
    ));
    await settle(tester);
  }

  Future<void> done(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  }

  Finder openButton() => find.textContaining('Открыть');

  testWidgets('подарок из запаса не занимает место кнопки «Открыть»', (tester) async {
    stash = [item('aaaaaaaaaaaaaa1', 'cocoa')];
    await pumpChest(tester);

    expect(calls, contains('GET /api/collections/chest_opens/records'));
    expect(find.text('Подарить'), findsNothing, reason: 'подарок из запаса снова требует выбора вместо открытия');
    expect(find.text('Оставить себе'), findsNothing);
    expect(openButton(), findsOneWidget, reason: 'сундук нельзя открыть, пока ждёт подарок из запаса');
    expect(find.text('В запасе: 1'), findsOneWidget, reason: 'подарок из запаса не виден на экране сундука (TOG-10)');
    await done(tester);
  });

  testWidgets('запас открывается листом, и подарок оттуда уходит на полку', (tester) async {
    stash = [item('aaaaaaaaaaaaaa1', 'cocoa'), item('aaaaaaaaaaaaaa2', 'tea')];
    await pumpChest(tester);

    await tester.tap(find.text('В запасе: 2'));
    await settle(tester);
    expect(find.text('Запас · 2'), findsOneWidget);

    await tester.tap(find.text('Чай'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Оставить себе'));
    await settle(tester);
    expect(calls, contains('POST /api/chest/keep aaaaaaaaaaaaaa2'));
    expect(find.text('Запас · 1'), findsOneWidget, reason: 'решённый подарок остался в запасе');
    expect(find.text('Чай'), findsNothing);

    // Последний решённый подарок закрывает лист, строки запаса больше нет.
    await tester.tap(find.widgetWithText(FilledButton, 'Оставить себе'));
    await settle(tester);
    expect(calls, contains('POST /api/chest/keep aaaaaaaaaaaaaa1'));
    expect(find.textContaining('Запас ·'), findsNothing, reason: 'пустой запас держит лист открытым');
    expect(find.textContaining('В запасе'), findsNothing);
    expect(openButton(), findsOneWidget);
    await done(tester);
  });

  testWidgets('свежий подарок откладывают кнопкой «Позже»', (tester) async {
    stash = [item('aaaaaaaaaaaaaa1', 'cocoa'), item('aaaaaaaaaaaaaa2', 'tea')];
    await pumpChest(tester, choice: const ChestStashItem(openId: 'aaaaaaaaaaaaaa1', giftKey: 'cocoa'));

    expect(find.text('Подарить'), findsOneWidget);
    expect(find.text('Позже'), findsOneWidget, reason: 'свежий подарок нельзя отложить');
    // Свой стиль кнопки заменяет стиль темы целиком: без шрифта надпись
    // уходила в системный, на превью она вышла квадратиками.
    final later = tester.renderObject<RenderParagraph>(find.text('Позже'));
    expect(later.text.style?.fontFamily, 'Onest', reason: '«Позже» нарисована не шрифтом приложения');
    expect(find.text('В запасе: 1'), findsOneWidget, reason: 'свежий подарок стоит и в выборе, и в запасе');

    await tester.tap(find.text('Позже'));
    await settle(tester);
    expect(find.text('Подарить'), findsNothing);
    expect(openButton(), findsOneWidget, reason: '«Позже» не вернул кнопку открытия');
    expect(find.text('В запасе: 2'), findsOneWidget, reason: 'отложенный подарок не лёг в запас');
    expect(calls.where((c) => c.startsWith('POST /api/chest/')), isEmpty, reason: '«Позже» ничего не решает на сервере');
    await done(tester);
  });

  testWidgets('решённый подарок не ставит на своё место следующий из запаса', (tester) async {
    stash = [item('aaaaaaaaaaaaaa1', 'cocoa'), item('aaaaaaaaaaaaaa2', 'tea')];
    await pumpChest(tester, choice: const ChestStashItem(openId: 'aaaaaaaaaaaaaa1', giftKey: 'cocoa'));

    await tester.tap(find.text('Оставить себе'));
    await settle(tester);
    expect(calls, contains('POST /api/chest/keep aaaaaaaaaaaaaa1'));
    expect(find.text('Подарить'), findsNothing, reason: 'следующий подарок из запаса снова требует выбора');
    expect(openButton(), findsOneWidget);
    expect(find.text('В запасе: 1'), findsOneWidget);
    await done(tester);
  });

  testWidgets('пустой запас — экран как раньше, с кнопкой открытия', (tester) async {
    await pumpChest(tester);

    expect(find.textContaining('В запасе'), findsNothing);
    expect(find.text('Подарить'), findsNothing);
    expect(openButton(), findsOneWidget);
    await done(tester);
  });

  for (final lang in [AppLanguage.ru, AppLanguage.de, AppLanguage.uk]) {
    testWidgets('320 точек, шрифт 1,3, ${lang.name}: выбор, «Позже» и строка запаса влезают', (tester) async {
      LocaleService.instance.setLanguage(lang);
      stash = [item('aaaaaaaaaaaaaa1', 'cocoa'), item('aaaaaaaaaaaaaa2', 'tea'), item('aaaaaaaaaaaaaa3', 'tea')];
      await pumpChest(
        tester,
        choice: const ChestStashItem(openId: 'aaaaaaaaaaaaaa1', giftKey: 'cocoa'),
        size: const Size(320, 1400),
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('chest-stash-bar')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('chest-stash-bar')));
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('chest-stash-sheet')), findsOneWidget);
      await done(tester);
    });
  }
}
