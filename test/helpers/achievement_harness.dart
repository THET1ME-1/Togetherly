// Общая обвязка тестов достижений: русские строки, тема приложения и экран
// нужного размера.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/theme/theme_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> useLanguage(String code) async {
  SharedPreferences.setMockInitialValues({'app_language': code});
  await LocaleService.instance.init();
}

/// Экран [size] в точках с масштабом шрифта [textScale].
void useScreen(WidgetTester tester, Size size, {double textScale = 1.0}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Дожидается всех картинок на экране. Кадры из сборки грузятся настоящим
/// вводом-выводом, и без этого снимок выходит то с рисунками, то без них —
/// смотря успел ли диск.
Future<void> settleImages(WidgetTester tester) async {
  final elements = find.byType(Image).evaluate().toList();
  await tester.runAsync(() async {
    for (final e in elements) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await tester.pump();
}

Widget achievementApp(Widget home, {AppTheme? theme}) {
  final t = theme ?? AppThemes.pink;
  return ThemeScope(
    theme: t,
    child: MaterialApp(
      theme: ProfileTheme.data(ProfileTheme.schemeFor(t)),
      home: home,
    ),
  );
}
