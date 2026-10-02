import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/home_layout.dart';
import 'package:love_app/screens/home/home_bottom_nav.dart';
import 'package:love_app/services/home_layout_service.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/widgets/home_layout_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Раскладка главной на экране 320 dp при шрифте 1.3: лист, секция настроек
/// и панель без спрятанных вкладок не должны переполняться.
void main() {
  setUpAll(() => LocaleService.instance.setLanguage(AppLanguage.ru));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> render(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 640),
          textScaler: TextScaler.linear(1.3),
        ),
        child: Scaffold(body: child),
      ),
    ));
    await tester.pump();
  }

  testWidgets('лист раскладки помещается на узком экране', (tester) async {
    HomeLayoutService.instance.debugSet(
      const HomeLayout().withBlock(HomeBlock.map, shown: false),
    );
    await render(
      tester,
      Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showHomeLayoutSheet(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Виджеты'), findsOneWidget);
    // Блоки ниже края листа: ListView строит их по мере прокрутки.
    await tester.scrollUntilVisible(
      find.text('Лента воспоминаний'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Сундук недели'), findsOneWidget);
  });

  testWidgets('секция в настройках помещается на узком экране', (tester) async {
    HomeLayoutService.instance.debugSet(const HomeLayout());
    await render(
      tester,
      ListView(children: const [HomeLayoutSettingsSection()]),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Карта «Где мы»'), findsOneWidget);
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
