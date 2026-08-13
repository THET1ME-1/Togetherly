import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/screens/settings_screen.dart';
import 'package:love_app/services/app_icon_service.dart';

/// Выбор иконки приложения живёт в настройках.
///
/// Он пропал 25 июля 2026: настройки переехали из профиля отдельным экраном,
/// строку вырезали вместе со старой вёрсткой блоков, а в новый экран не
/// перенесли. Сервис, тринадцать значков и alias'ы в манифесте всё это время
/// оставались на месте — не работал только вход. Тест держит строку, чтобы она
/// не потерялась при следующей перестройке экрана.
Widget _app({String? appIconId}) => MaterialApp(
      home: SettingsScreen(
        scheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE91E63)),
        accountEmail: 'sasha@example.com',
        appIconId: appIconId,
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
        onAbout: () {},
        onLogout: () {},
        onDeleteAccount: () {},
        lockScreenMood: false,
        onLockScreenMoodChanged: (_) {},
        sideActionIsArrow: true,
        onToggleSideAction: () {},
      ),
    );

void main() {
  testWidgets('строка «Иконка приложения» есть и называет текущий значок',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(appIconId: AppIconService.defaultId));
    await tester.pump();

    // Язык в тестах не задан, поэтому принимаем обе локали.
    expect(
      find.textContaining(RegExp('Иконка приложения|App icon')),
      findsOneWidget,
    );
    final current = AppIconService.options.first;
    expect(
      find.textContaining(RegExp(current.name)),
      findsOneWidget,
    );
  });

  testWidgets('без поддержки платформы строки нет', (tester) async {
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app());
    await tester.pump();

    expect(
      find.textContaining(RegExp('Иконка приложения|App icon')),
      findsNothing,
    );
  });
}
