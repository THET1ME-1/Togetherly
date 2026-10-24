import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/screens/home/home_bottom_nav.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/widgets/unfold/unfold_route.dart';

/// Обращение 464 (24.10.2026, видео): плашка «Предпросмотр» стояла вровень с
/// кнопкой чата, и та закрывала её крестик. Плашка встаёт над кнопкой чата
/// по [kHomeChatButtonTop], поэтому число обязано совпадать с панелью.
void main() {
  setUpAll(() => LocaleService.instance.setLanguage(AppLanguage.ru));

  for (final width in [320.0, 360.0, 412.0]) {
    testWidgets('Кнопка чата не выше kHomeChatButtonTop на $width dp', (
      tester,
    ) async {
      const height = 800.0;
      tester.view.physicalSize = Size(width * 3, height * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: HomeBottomNav(
                theme: AppThemes.byIndex(0),
                selectedIndex: 0,
                isPaired: true,
                onTap: (_) {},
                onCreatePin: () {},
                onChat: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final chat = tester.getRect(find.byType(UnfoldSource));
      expect(height - chat.top, lessThanOrEqualTo(kHomeChatButtonTop));
      expect(
        height - chat.top,
        greaterThan(kHomeChatButtonTop - 4),
        reason: 'число отстало от панели, плашка висит слишком высоко',
      );
    });
  }
}
