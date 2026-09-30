// Экран справки «Как сделать»: частые вопросы, поиск, темы и ответ, кнопка
// которого ведёт прямо на нужный экран. Узкий экран с крупным шрифтом не
// должен ничего переполнять.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/help_items.dart';
import 'package:love_app/screens/help_screen.dart';
import 'package:love_app/services/locale_service.dart';

void main() {
  setUp(() => LocaleService.instance.setLanguage(AppLanguage.ru));

  Future<List<HelpAction>> pump(
    WidgetTester tester, {
    bool plusInStore = true,
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = size * 3;
    addTearDown(tester.view.reset);
    final actions = <HelpAction>[];
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
            size: size, textScaler: TextScaler.linear(textScale)),
        child: HelpScreen(
          scheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF7E8B)),
          plusInStore: plusInStore,
          onAction: actions.add,
          onWriteUs: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return actions;
  }

  testWidgets('наверху два частых вопроса, ниже темы', (tester) async {
    await pump(tester);
    expect(find.text('Чаще всего спрашивают'.toUpperCase()), findsOneWidget);
    expect(find.textContaining('Как оплатить Togetherly'), findsWidgets);
    expect(find.text('Как удалить пару'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('поиск оставляет только подходящее и прячет частые',
      (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('help-search')), 'пароля');
    await tester.pumpAndSettle();
    expect(find.text('Как сменить пароль'), findsOneWidget);
    expect(find.text('Как удалить пару'), findsNothing);
    expect(find.text('Чаще всего спрашивают'.toUpperCase()), findsNothing);

    await tester.enterText(find.byKey(const Key('help-search')), 'абракадабра');
    await tester.pumpAndSettle();
    expect(find.text('Не помогло, написать нам'), findsOneWidget);
  });

  testWidgets('ответ показывает шаги, «Открыть» ведёт на вкладку',
      (tester) async {
    final actions = await pump(tester);
    await tester.tap(find.text('Как удалить пару').first);
    await tester.pumpAndSettle();
    expect(find.text('Связь → Отключиться'), findsOneWidget);
    expect(find.textContaining('красную кнопку «Отключиться»'), findsOneWidget);
    await tester.tap(find.byKey(const Key('help-open')));
    await tester.pumpAndSettle();
    expect(actions, [HelpAction.tabConnect]);
  });

  testWidgets('в сборке с сайта Плюс ведёт на lava.top', (tester) async {
    final actions = await pump(tester, plusInStore: false);
    await tester.tap(find.textContaining('Как оплатить Togetherly').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('lava.top'), findsWidgets);
    await tester.tap(find.byKey(const Key('help-open')));
    await tester.pumpAndSettle();
    expect(actions, [HelpAction.plusSite]);
  });

  testWidgets('320 dp и шрифт 1.3 без переполнений', (tester) async {
    await pump(tester, size: const Size(320, 640), textScale: 1.3);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Как поменять дату начала отношений').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
