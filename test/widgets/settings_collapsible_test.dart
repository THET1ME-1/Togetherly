import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/ui_prefs.dart';
import 'package:love_app/widgets/settings_scaffold.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Секции настроек сворачиваются, как секции профиля, и решение человека
/// переживает выход с экрана: свернувший «Аккаунт» не должен разворачивать его
/// заново на каждый заход.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget screen() => MaterialApp(
    home: Scaffold(
      body: ListView(
        children: const [
          SettingsCollapsible(
            prefsKey: 'about',
            title: 'О приложении',
            icon: Icons.help_rounded,
            children: [
              SettingsRow(icon: Icons.info_rounded, title: 'Версия'),
            ],
          ),
        ],
      ),
    ),
  );

  testWidgets('по умолчанию секция раскрыта', (tester) async {
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    expect(find.text('Версия'), findsOneWidget);
    expect(find.text('О ПРИЛОЖЕНИИ'), findsOneWidget);
  });

  testWidgets('тап по заголовку сворачивает и разворачивает', (tester) async {
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    await tester.tap(find.text('О ПРИЛОЖЕНИИ'));
    await tester.pumpAndSettle();
    expect(find.text('Версия'), findsNothing);

    await tester.tap(find.text('О ПРИЛОЖЕНИИ'));
    await tester.pumpAndSettle();
    expect(find.text('Версия'), findsOneWidget);
  });

  testWidgets('свёрнутость переживает пересоздание экрана', (tester) async {
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.tap(find.text('О ПРИЛОЖЕНИИ'));
    await tester.pumpAndSettle();

    // Экран закрыли и открыли заново — состояние поднимается из prefs.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    expect(find.text('Версия'), findsNothing);
    expect(await UiPrefs.collapsedSections(), contains('settings:about'));
  });

  testWidgets('развёрнутую секцию из хранилища убираем', (tester) async {
    await UiPrefs.setSectionCollapsed('settings:about', true);
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.text('Версия'), findsNothing);

    await tester.tap(find.text('О ПРИЛОЖЕНИИ'));
    await tester.pumpAndSettle();

    expect(await UiPrefs.collapsedSections(), isNot(contains('settings:about')));
  });
}
