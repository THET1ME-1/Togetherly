import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/screens/home/home_bottom_nav.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Владелец 12.11.2026: «Где подсказки на главном меню, куда зайти, что
/// делать — каждая кнопка меню что делает». Ту обходит нижнее меню, и ему
/// нужно знать, где стоит каждая кнопка: ключи кнопок задаёт главная.
void main() {
  final keys = {for (final i in HomeBottomNav.defaultOrder) i: GlobalKey(debugLabel: 'nav$i')};

  Widget nav({bool showWatch = true}) => MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: HomeBottomNav(
              selectedIndex: 0,
              theme: AppThemes.pink,
              isPaired: false,
              onTap: (_) {},
              showWatch: showWatch,
              itemKeys: keys,
            ),
          ),
        ),
      );

  testWidgets('у каждой кнопки меню свой ключ, на который покажет Ту', (tester) async {
    await tester.pumpWidget(nav());
    for (final entry in keys.entries) {
      expect(entry.value.currentContext, isNotNull, reason: 'кнопка ${entry.key} без ключа');
    }
    final xs = [for (final i in HomeBottomNav.defaultOrder) tester.getRect(find.byKey(keys[i]!)).center.dx];
    expect(xs, orderedEquals([...xs]..sort()), reason: 'ключи перепутаны между кнопками');
  });

  testWidgets('спрятанной вкладке показывать не на что', (tester) async {
    await tester.pumpWidget(nav(showWatch: false));
    expect(keys[4]!.currentContext, isNull);
  });

  test('подсказки меню переведены', () async {
    SharedPreferences.setMockInitialValues({});
    for (final lang in [AppLanguage.ru, AppLanguage.en, AppLanguage.uk, AppLanguage.zh]) {
      await LocaleService.instance.setLanguage(lang);
      final s = LocaleService.current;
      for (final text in [s.navHintHome, s.navHintWidgets, s.navHintWatch, s.navHintConnect, s.navHintProfile]) {
        expect(text, isNot(startsWith('navHint')), reason: '$lang: строки нет в словаре');
        expect(text.length, greaterThan(10));
      }
    }
  });
}
