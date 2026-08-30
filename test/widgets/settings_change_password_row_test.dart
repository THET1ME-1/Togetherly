import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Смена пароля живёт и в настройках, а не только на экране входа.
///
/// «Забыли пароль?» стоит под полем пароля на входе — то есть там, куда уже
/// вошедший человек больше не попадает. 30 августа 2026 спросили прямо: «как
/// пароль сбросить, в приложении ничего не найти». Строка в настройках держит
/// второй вход в ту же дверь.
Widget _app({VoidCallback? onChangePassword}) => MaterialApp(
      home: SettingsScreen(
        scheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE91E63)),
        accountEmail: 'sasha@example.com',
        onAppearance: () {},
        onNotifications: () {},
        onLanguage: () {},
        onCoinShop: () {},
        onPrivacyPolicy: () {},
        onExport: () {},
        onResetMissYou: () {},
        onTerms: () {},
        onSupport: () {},
        onOfficial: () {},
        onDrawTools: () {},
        onTelegramChannel: () {},
        onBugBot: () {},
        onAbout: () {},
        onChangePassword: onChangePassword ?? () {},
        onLogout: () {},
        onDeleteAccount: () {},
        lockScreenMood: false,
        onLockScreenMoodChanged: (_) {},
        sideActionIsArrow: true,
        onToggleSideAction: () {},
      ),
    );

/// Высокий вьюпорт: строки ниже экрана в ListView просто не строятся.
void _tallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 15000);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  // Секции запоминают, свёрнуты ли они, в SharedPreferences: без заглушки
  // экран не построится.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('строка смены пароля есть в настройках', (tester) async {
    _tallViewport(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.textContaining(RegExp('Сменить пароль|Change password')),
        findsOneWidget);
  });

  testWidgets('нажатие зовёт обработчик', (tester) async {
    _tallViewport(tester);
    var taps = 0;
    await tester.pumpWidget(_app(onChangePassword: () => taps++));
    await tester.pumpAndSettle();

    final row = find.textContaining(RegExp('Сменить пароль|Change password'));
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(taps, 1);
  });
}
