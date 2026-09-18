import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:love_app/screens/wallet_wait_screen.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/wallet_teaser.dart';
import 'package:love_app/theme/app_palettes.dart';

/// Стена ожидания Togetherly Wallet («Чек»): помещается на 320 dp при крупном
/// шрифте в обеих темах, записывает в очередь и сама уводит в Wallet, если он
/// уже вышел.
void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    LocaleService.instance.setLanguage(AppLanguage.ru);
  });

  const waiting = WaitlistState(
      count: 2418, joined: false, place: 0, links: WalletLinks());
  const joined = WaitlistState(
      count: 2419, joined: true, place: 2419, links: WalletLinks());

  Future<void> render(
    WidgetTester tester, {
    required Brightness brightness,
    double width = 320,
    double scale = 1.3,
    Future<WaitlistState?> Function()? load,
    Future<WaitlistState?> Function()? join,
    Future<bool> Function()? open,
  }) async {
    tester.view.physicalSize = Size(width * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final theme = buildAppTheme(kPalettes[0], brightness);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 640),
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: WalletWaitScreen(
          theme: theme,
          load: load ?? () async => waiting,
          join: join ?? () async => joined,
          openWallet: open ?? () async => true,
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  for (final b in Brightness.values) {
    testWidgets('Чек помещается на 320 dp при шрифте 1.3, тема ${b.name}',
        (tester) async {
      await render(tester, brightness: b);
      expect(tester.takeException(), isNull);
      expect(find.text('Добавить в ожидание'), findsOneWidget);
      expect(find.text('Общий бюджет'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('wallet-join')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      expect(find.text('Вы в списке ожидания'), findsOneWidget);
      expect(find.text('№ 2 419'), findsOneWidget,
          reason: 'на чеке нет печати с местом в очереди');
    });
  }

  testWidgets('Немецкий на 320 dp тоже без переполнений', (tester) async {
    // Язык меняется синхронно, а сохранение в настройки ждать нельзя: внутри
    // поддельного времени виджет-теста оно не завершается, и тест висит.
    LocaleService.instance.setLanguage(AppLanguage.de);
    addTearDown(() {
      LocaleService.instance.setLanguage(AppLanguage.ru);
    });
    await render(tester, brightness: Brightness.light);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Сеть упала при записи — человек видит, что делать', (tester) async {
    await render(tester,
        brightness: Brightness.light, join: () async => null);
    await tester.tap(find.byKey(const ValueKey('wallet-join')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('Проверьте связь'), findsOneWidget);
    expect(find.text('Добавить в ожидание'), findsOneWidget);
  });

  testWidgets('Если Wallet уже вышел, стена уводит в него сама', (tester) async {
    var opened = false;
    await render(
      tester,
      brightness: Brightness.light,
      load: () async => WaitlistState(
        count: 5000,
        joined: true,
        place: 12,
        links: WalletLinks.fromJson({'android': true, 'ios': true}),
      ),
      open: () async => opened = true,
    );
    expect(opened, isTrue);
  });
}
