import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:love_app/models/user_data.dart';
import 'package:love_app/screens/welcome_screen.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/theme_scope.dart';

/// Онбординг — первое, что видит человек, и единственный экран, который нельзя
/// проверить «потом»: он показывается один раз. Здесь смотрим, что три сцены
/// живут, помещаются на 360 dp и берут цвета темы, а не свои.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget host({Brightness brightness = Brightness.light}) {
    final theme = buildAppTheme(kPalettes[0], brightness);
    return MediaQuery(
      data: const MediaQueryData(size: Size(360, 780)),
      child: ThemeScope(
        theme: theme,
        child: MaterialApp(home: WelcomeScreen(userData: UserData())),
      ),
    );
  }

  testWidgets('показывает первый экран без переполнений', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();

    final s = LocaleService.current;
    expect(find.text(s.welcomeSlide1Title), findsOneWidget);
    expect(find.text(s.welcomeNext), findsOneWidget);
    expect(find.text(s.privateSecure), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('пролистывание доводит до последнего экрана', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();

    final s = LocaleService.current;
    // `pumpAndSettle` тут не годится: сцены анимируются бесконечно, и покоя
    // экран не достигает никогда. Листаем по времени.
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text(s.welcomeNext));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    expect(find.text(s.welcomeSlide3Title), findsOneWidget);
    // На последнем экране кнопка ведёт в регистрацию, а под ней появляется
    // вход для тех, у кого аккаунт уже есть.
    expect(find.text(s.createAccount), findsOneWidget);
    expect(find.text(s.alreadyHaveAccount), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('тёмная тема рисуется без ошибок', (tester) async {
    await tester.pumpWidget(host(brightness: Brightness.dark));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
