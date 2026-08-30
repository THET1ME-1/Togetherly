import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/screens/settings_screen.dart';

/// Канал и бот для багов живут в настройках, в разделе «О приложении».
///
/// Спрашивают об этом в поддержке прямым текстом — «не могу найти ссылку на
/// тгк» (15.08.2026), — а бот для жалоб до сих пор знали только те, кому его
/// присылали в ответ. Обе ссылки лежали где угодно, кроме приложения.
Widget _app() => MaterialApp(
      home: SettingsScreen(
        scheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE91E63)),
        accountEmail: 'sasha@example.com',
        onAppIcon: () {},
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
        onAbout: () {},
        onChangePassword: () {},
        onLogout: () {},
        onDeleteAccount: () {},
        onTelegramChannel: () {},
        onBugBot: () {},
        lockScreenMood: false,
        onLockScreenMoodChanged: (_) {},
        sideActionIsArrow: true,
        onToggleSideAction: () {},
      ),
    );

/// Экран настроек длиннее любого телефона, а ListView строит только видимое.
/// Даём тесту очень высокий вьюпорт, чтобы разделы дошли до строк.
void _tallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 15000);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('в настройках есть строки канала и бота', (tester) async {
    _tallViewport(tester);

    await tester.pumpWidget(_app());
    await tester.pump();

    // Язык в тестах не задан, поэтому принимаем обе локали.
    expect(
      find.textContaining(RegExp('Наш канал|Telegram channel')),
      findsOneWidget,
      reason: 'ссылку на канал спрашивают в поддержке',
    );
    expect(
      find.textContaining(RegExp('Сообщить о проблеме|Report a problem')),
      findsOneWidget,
      reason: 'бот для багов должен быть виден из приложения',
    );
  });

  testWidgets('нажатия ведут наружу', (tester) async {
    _tallViewport(tester);

    var channel = 0;
    var bot = 0;
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        scheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE91E63)),
        accountEmail: '',
        onAppIcon: () {},
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
        onAbout: () {},
        onChangePassword: () {},
        onLogout: () {},
        onDeleteAccount: () {},
        onTelegramChannel: () => channel++,
        onBugBot: () => bot++,
        lockScreenMood: false,
        onLockScreenMoodChanged: (_) {},
        sideActionIsArrow: true,
        onToggleSideAction: () {},
      ),
    ));
    await tester.pump();

    await tester.tap(find.textContaining(RegExp('Наш канал|Telegram channel')));
    await tester.pump();
    expect(channel, 1);

    await tester.tap(
      find.textContaining(RegExp('Сообщить о проблеме|Report a problem')),
    );
    await tester.pump();
    expect(bot, 1);
  });
}
