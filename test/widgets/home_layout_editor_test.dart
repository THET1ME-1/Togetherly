import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/home_layout.dart';
import 'package:love_app/screens/home/home_bottom_nav.dart';
import 'package:love_app/services/home_layout_service.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/plus_service.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/widgets/home_layout_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Раздел «Главный экран» в настройках: на экране 320 dp при шрифте 1.3
/// ничего не переполняется, с Плюсом строку блока зажимают и перетаскивают,
/// тумблер прячет блок. Панель без спрятанных вкладок тоже помещается.
void main() {
  setUpAll(() => LocaleService.instance.setLanguage(AppLanguage.ru));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> render(WidgetTester tester, Widget child,
      {double width = 320, double scale = 1.3}) async {
    tester.view.physicalSize = Size(width * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 1400),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(body: child),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('без Плюса раздел помещается и стоит под замком', (tester) async {
    HomeLayoutService.instance.debugSet(const HomeLayout());
    await render(
      tester,
      ListView(children: const [HomeLayoutSettingsSection()]),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Открыть с Togetherly+'), findsOneWidget);
    expect(find.text('Карта «Где мы»'), findsOneWidget);
    expect(find.byIcon(Icons.drag_indicator_rounded), findsNothing);
  });

  group('с Плюсом', () {
    setUp(() => PlusService.instance.setTrialUntil(
        DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch));
    tearDown(() => PlusService.instance.setTrialUntil(0));

    testWidgets('строку зажали и перетащили — порядок поменялся',
        (tester) async {
      HomeLayoutService.instance.debugSet(const HomeLayout());
      await render(
        tester,
        ListView(children: const [HomeLayoutSettingsSection()]),
        scale: 1,
        width: 400,
      );
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.drag_indicator_rounded), findsNWidgets(6));

      final chest = find.text('Сундук недели');
      final lane = find.text('Лента воспоминаний');
      final g = await tester.startGesture(tester.getCenter(chest));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      final dy = tester.getCenter(lane).dy - tester.getCenter(chest).dy + 40;
      for (var i = 0; i < 20; i++) {
        await g.moveBy(Offset(0, dy / 20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pumpAndSettle();

      final order = HomeLayoutService.instance.saved.order;
      expect(order.last, HomeBlock.chest, reason: '$order');
      expect(order.first, HomeBlock.mascot);
    });

    testWidgets('тумблер прячет блок', (tester) async {
      HomeLayoutService.instance.debugSet(const HomeLayout());
      await render(
        tester,
        ListView(children: const [HomeLayoutSettingsSection()]),
        scale: 1,
        width: 400,
      );
      final row = find.ancestor(
        of: find.text('Карта «Где мы»'),
        matching: find.byType(Row),
      );
      await tester.tap(
          find.descendant(of: row.first, matching: find.byType(Switch)));
      await tester.pumpAndSettle();
      expect(HomeLayoutService.instance.saved.showsBlock(HomeBlock.map),
          isFalse);
      expect(find.text('Вернуть как было'), findsOneWidget);
    });

    testWidgets('раздел помещается на узком экране', (tester) async {
      HomeLayoutService.instance.debugSet(
        const HomeLayout().withBlock(HomeBlock.map, shown: false),
      );
      await render(
        tester,
        ListView(children: const [HomeLayoutSettingsSection()]),
      );
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('панель без «Виджетов» и «Смотрим» рисует три пункта',
      (tester) async {
    await render(
      tester,
      Align(
        alignment: Alignment.bottomCenter,
        child: HomeBottomNav(
          theme: AppThemes.byIndex(0),
          selectedIndex: 0,
          isPaired: true,
          showWidgets: false,
          showWatch: false,
          onTap: (_) {},
          onCreatePin: () {},
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text(LocaleService.current.widgets), findsNothing);
    expect(find.text(LocaleService.current.watchTogether), findsNothing);
  });
}
