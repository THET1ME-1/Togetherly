// Лист «Виджет не появился» (обращения 25.11.2026, Android 1.44): лончер
// молча не поставил виджет, человек должен узнать, как поставить его сам.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/app_sheet.dart';
import 'package:love_app/widgets/widget_pin_help_sheet.dart';

void main() {
  Future<void> open(
    WidgetTester tester, {
    required bool xiaomi,
    Brightness brightness = Brightness.light,
    VoidCallback? onOpenSettings,
  }) async {
    final theme = buildAppTheme(kPalettes[0], brightness);
    final cs = ProfileTheme.themeFor(theme).colorScheme;
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ProfileTheme.data(cs),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showAppSheet<void>(
                context,
                builder: (_) => WidgetPinHelpSheet(xiaomi: xiaomi, onOpenSettings: onOpenSettings),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  for (final language in [AppLanguage.ru, AppLanguage.de]) {
    for (final brightness in Brightness.values) {
      testWidgets('Xiaomi, ${language.code}, ${brightness.name}: 320 точек, шрифт 1.3, без переполнения',
          (tester) async {
        LocaleService.instance.setLanguage(language);
        var opened = 0;
        await open(tester, xiaomi: true, brightness: brightness, onOpenSettings: () => opened++);
        expect(tester.takeException(), isNull);
        final settings = find.byKey(const ValueKey('widget-pin-help-settings'));
        expect(settings, findsOneWidget);
        await tester.ensureVisible(settings);
        await tester.pumpAndSettle();
        await tester.tap(settings);
        expect(opened, 1);
        // «Понятно» прижата к низу и видна всегда.
        expect(tester.getRect(find.byKey(const ValueKey('widget-pin-help-ok'))).bottom,
            lessThanOrEqualTo(640));
      });
    }
  }

  testWidgets('не Xiaomi: только как поставить руками, кнопки разрешений нет', (tester) async {
    LocaleService.instance.setLanguage(AppLanguage.ru);
    await open(tester, xiaomi: false);
    expect(find.textContaining('удерживайте палец'), findsOneWidget);
    expect(find.byKey(const ValueKey('widget-pin-help-settings')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('widget-pin-help-ok')));
    await tester.pumpAndSettle();
    expect(find.byType(WidgetPinHelpSheet), findsNothing);
  });
}
