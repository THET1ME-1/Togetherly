import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
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
import 'package:love_app/widgets/unfold/unfold_route.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// TOG-38: экран сундука с подарком, который ждёт решения, обязан отпускать.
///
/// Обращение 480 (Android, 25.10.2026): «после нажатия назад ничего не
/// происходит», и после перезапуска «на секунду появляются сундуки и снова
/// появляется выбор». Стрелка экран закрывала, но каждый новый заход ставил
/// выбор из запаса на место кнопки «Открыть», и со стороны выглядело так,
/// будто экран не отпускает. Здесь проверяется сам уход: стрелкой и
/// системным «назад», с главной обоими переходами.
void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory.systemTemp.path,
    );
    SharedPreferences.setMockInitialValues({'chest_sound': false});
    LocaleService.instance.setLanguage(AppLanguage.ru);
    PairJarService.instance.debugReset();
    GiftCatalog.registerSeasonal({
      'cocoa': const Gift(key: 'cocoa', price: 0, engine: GiftEngine.response, titleRu: 'Какао', titleEn: 'Cocoa'),
    });
    PocketBaseService().debugUse(PocketBase(
      'https://togetherly.day',
      httpClientFactory: () => MockClient((req) async {
        if (req.url.path.endsWith('/chest_opens/records')) {
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'page': 1,
              'perPage': 100,
              'totalItems': 1,
              'totalPages': 1,
              'items': [
                {
                  'collectionId': 'c',
                  'collectionName': 'chest_opens',
                  'state': 'stash',
                  'id': 'aaaaaaaaaaaaaa1',
                  'prize': 'cocoa',
                  'day': '2026-10-25',
                },
              ],
            })),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('{"ok":true}', 200, headers: {'content-type': 'application/json'});
      }),
    ));
  });
  tearDown(() {
    PairJarService.instance.debugReset();
    GiftCatalog.registerSeasonal(const {});
  });

  Future<void> openFromHome(WidgetTester tester, {required bool unfold, ChestStashItem? choice}) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => ChestSound.instance.load());
    final t = buildAppTheme(kPalettes.firstWhere((p) => p.name == 'Розовая'), Brightness.light);
    Widget chest(BuildContext _) => ChestScreen(theme: t, groupId: 'g', debugSeasons: const [], debugChoice: choice);
    await tester.pumpWidget(MaterialApp(
      theme: ProfileTheme.data(t.scheme!),
      home: Scaffold(
        body: Center(
          child: UnfoldSource(
            fill: t.scheme!.primaryContainer,
            radius: 28,
            builder: (context, source) => TextButton(
              onPressed: () => Navigator.of(context).push(
                unfold ? unfoldFrom<void>(source, chest) : MaterialPageRoute<void>(builder: chest),
              ),
              child: const Text('сундук на главной'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('сундук на главной'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(ChestScreen), findsOneWidget);
  }

  Future<void> expectLeft(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(ChestScreen), findsNothing, reason: '«назад» не увёл с экрана сундука');
    expect(find.text('сундук на главной'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  }

  for (final unfold in [false, true]) {
    final how = unfold ? 'экран вырос из карточки главной' : 'обычный переход';
    const fresh = ChestStashItem(openId: 'aaaaaaaaaaaaaa1', giftKey: 'cocoa');

    testWidgets('$how, подарок ждёт в запасе: стрелка уводит', (tester) async {
      await openFromHome(tester, unfold: unfold);
      expect(find.text('В запасе: 1'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await expectLeft(tester);
    });

    testWidgets('$how, свежий подарок не разобран: стрелка уводит', (tester) async {
      await openFromHome(tester, unfold: unfold, choice: fresh);
      expect(find.text('Подарить'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await expectLeft(tester);
    });

    testWidgets('$how, свежий подарок не разобран: системное «назад» уводит', (tester) async {
      await openFromHome(tester, unfold: unfold, choice: fresh);
      await tester.binding.handlePopRoute();
      await expectLeft(tester);
    });
  }
}
