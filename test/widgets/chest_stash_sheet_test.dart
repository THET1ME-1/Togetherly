import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:love_app/models/gift.dart';
import 'package:love_app/services/chest_service.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/pocketbase_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/chest/chest_stash_lane.dart';
import 'package:love_app/widgets/chest/chest_stash_sheet.dart';
import 'package:pocketbase/pocketbase.dart';

/// Лист «Запас»: подарки из сундука, отложенные на потом (TOG-38, макет
/// «Звук, запас и фото из виджета», вариант А). Разбирают его по одному
/// подарку и когда угодно: лист ничего не навязывает и закрывается сам,
/// когда разбирать больше нечего.
void main() {
  late List<String> calls;
  late int failWith;

  setUp(() {
    calls = [];
    failWith = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory.systemTemp.path,
    );
    LocaleService.instance.setLanguage(AppLanguage.ru);
    GiftCatalog.registerSeasonal({
      'cocoa': const Gift(key: 'cocoa', price: 0, engine: GiftEngine.response, titleRu: 'Какао', titleEn: 'Cocoa'),
      'tea': const Gift(key: 'tea', price: 0, engine: GiftEngine.response, titleRu: 'Чай', titleEn: 'Tea'),
    });
    PocketBaseService().debugUse(PocketBase(
      'https://togetherly.day',
      httpClientFactory: () => MockClient((req) async {
        final body = req.body.isEmpty ? null : jsonDecode(req.body);
        final m = body is Map ? body : const {};
        calls.add('${req.method} ${req.url.path} ${m['openId'] ?? ''} ${m['groupId'] ?? ''}'.trim());
        if (failWith != 0) return http.Response('{"message":"boom"}', failWith);
        return http.Response('{"ok":true}', 200, headers: {'content-type': 'application/json'});
      }),
    ));
  });
  tearDown(() => GiftCatalog.registerSeasonal(const {}));

  const items = [
    ChestStashItem(openId: 'aaaaaaaaaaaaaa1', giftKey: 'cocoa'),
    ChestStashItem(openId: 'aaaaaaaaaaaaaa2', giftKey: 'tea', chest: 'hw'),
    ChestStashItem(openId: 'aaaaaaaaaaaaaa3', giftKey: 'cocoa'),
  ];

  /// Лист поверх пустого экрана. Возвращает флаг «лист закрылся».
  Future<ValueNotifier<bool>> open(
    WidgetTester tester, {
    List<ChestStashItem> stash = items,
    String? selected,
    Size size = const Size(412, 915),
    double textScale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final closed = ValueNotifier(false);
    final t = buildAppTheme(kPalettes.firstWhere((p) => p.name == 'Розовая'), brightness);
    final cs = t.scheme!;
    await tester.pumpWidget(MaterialApp(
      theme: ProfileTheme.data(cs),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                await showChestStashSheet(context, cs: cs, groupId: 'g', items: stash, selected: selected);
                closed.value = true;
              },
              child: const Text('открыть запас'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('открыть запас'));
    await tester.pumpAndSettle();
    return closed;
  }

  Future<void> done(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  Finder tile(String key) =>
      find.descendant(of: find.byKey(ValueKey('stash-tile-$key')), matching: find.text(GiftCatalog.byKey(key)!.title));

  testWidgets('подарки по видам, у повторов счётчик, первым выбран самый старый', (tester) async {
    await open(tester);

    expect(find.text('Запас · 3'), findsOneWidget);
    expect(find.text('×2'), findsOneWidget, reason: 'два «Какао» не сложились в одну плитку');
    expect(find.byKey(const ValueKey('stash-tile-cocoa')), findsOneWidget);
    expect(find.byKey(const ValueKey('stash-tile-tea')), findsOneWidget);
    final panel = find.byKey(const ValueKey('stash-actions'));
    expect(find.descendant(of: panel, matching: find.text('Какао')), findsOneWidget);
    expect(find.descendant(of: panel, matching: find.text('У тебя 2')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('stash-tile-tea')));
    await tester.pump();
    expect(find.descendant(of: panel, matching: find.text('Чай')), findsOneWidget);
    expect(find.descendant(of: panel, matching: find.textContaining('У тебя')), findsNothing);
    await done(tester);
  });

  testWidgets('лист открывается на подарке, по которому нажали', (tester) async {
    await open(tester, selected: 'tea');
    final panel = find.byKey(const ValueKey('stash-actions'));
    expect(find.descendant(of: panel, matching: find.text('Чай')), findsOneWidget);
    await done(tester);
  });

  testWidgets('«Подарить» спрашивает записку и отдаёт партнёру самый старый из повторов', (tester) async {
    await open(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Подарить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(LocaleService.current.giftNoteSkip));
    await tester.pumpAndSettle();

    expect(calls, contains('POST /api/chest/give aaaaaaaaaaaaaa1 g'));
    expect(find.text('Запас · 2'), findsOneWidget);
    expect(find.text('×2'), findsNothing);
    await done(tester);
  });

  testWidgets('отказ сервера: подарок остаётся в запасе', (tester) async {
    await open(tester);
    failWith = 500;

    await tester.tap(find.widgetWithText(FilledButton, 'Оставить себе'));
    await tester.pumpAndSettle();

    expect(calls, contains('POST /api/chest/keep aaaaaaaaaaaaaa1'));
    expect(find.text('Запас · 3'), findsOneWidget, reason: 'отказ сервера убрал подарок из запаса');
    expect(find.text('×2'), findsOneWidget);
    await done(tester);
  });

  testWidgets('последний разобранный подарок закрывает лист', (tester) async {
    final closed = await open(tester, stash: const [ChestStashItem(openId: 'aaaaaaaaaaaaaa2', giftKey: 'tea')]);

    await tester.tap(find.widgetWithText(FilledButton, 'Оставить себе'));
    await tester.pumpAndSettle();

    expect(calls, contains('POST /api/chest/keep aaaaaaaaaaaaaa2'));
    expect(closed.value, isTrue, reason: 'пустой запас держит лист открытым');
    expect(find.textContaining('Запас ·'), findsNothing);
    await done(tester);
  });

  testWidgets('касание по карточке ленты магазина открывает запас на этом подарке', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final t = buildAppTheme(kPalettes.firstWhere((p) => p.name == 'Розовая'), Brightness.light);
    await tester.pumpWidget(MaterialApp(
      theme: ProfileTheme.data(t.scheme!),
      home: const Scaffold(body: ChestStashLane(groupId: 'g', debugItems: items)),
    ));
    await tester.pump();

    await tester.tap(find.text('Чай'));
    await tester.pumpAndSettle();
    final panel = find.byKey(const ValueKey('stash-actions'));
    expect(find.descendant(of: panel, matching: find.text('Чай')), findsOneWidget);
    expect(find.descendant(of: panel, matching: find.widgetWithText(FilledButton, 'Оставить себе')), findsOneWidget,
        reason: 'из магазина подарок можно было только подарить');
    await done(tester);
  });

  for (final lang in AppLanguage.values) {
    for (final b in Brightness.values) {
      testWidgets('320 точек, шрифт 1,3, ${lang.name}, ${b.name}: лист влезает', (tester) async {
        LocaleService.instance.setLanguage(lang);
        await open(tester, size: const Size(320, 640), textScale: 1.3, brightness: b);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('stash-actions')), findsOneWidget);
        // Подпись подарка не рвётся посреди слова и не уходит за плитку.
        expect(tile('cocoa'), findsOneWidget);
        await done(tester);
      });
    }
  }
}
