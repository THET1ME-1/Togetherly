import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/screens/home/home_action_buttons.dart';
import 'package:love_app/screens/home/home_bottom_nav.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/services/locale_service.dart';

/// Экран 320 dp при системном шрифте 1.3 — нижняя граница, на которую
/// приложение обязано ложиться без переполнений. На эмуляторе
/// (`wm size 720x1600`, `wm density 360`, `font_scale 1.3`) ряд быстрых кнопок
/// вылезал вправо на 54 пикселя, а панель навигации вместе с круглой кнопкой —
/// на 40: пилюли держали жёсткие 74 dp, а отступы пунктов были подобраны под
/// 360 dp.
void main() {
  setUpAll(() => LocaleService.instance.setLanguage(AppLanguage.ru));

  final theme = AppThemes.byIndex(0);

  Future<void> render(WidgetTester tester, Widget child,
      {double width = 320, double scale = 1.3}) async {
    tester.view.physicalSize = Size(width * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 640),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: child)),
      ),
    ));
    await tester.pump();
  }

  testWidgets('ряд быстрых кнопок не переполняет экран 320 dp', (tester) async {
    await render(
      tester,
      HomeActionButtons(
        theme: theme,
        isPaired: true,
        myMoodImagePath: '',
        onDraw: () {},
        onMood: () {},
        onCalendar: () {},
        onPost: () {},
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('панель навигации не переполняет экран 320 dp', (tester) async {
    await render(
      tester,
      HomeBottomNav(
        theme: theme,
        selectedIndex: 0,
        isPaired: true,
        onTap: (_) {},
        onCreatePin: () {},
        onChat: () {},
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('на обычных 360 dp тоже без переполнений', (tester) async {
    await render(
      tester,
      HomeActionButtons(
        theme: theme,
        isPaired: true,
        myMoodImagePath: '',
        onDraw: () {},
        onMood: () {},
        onCalendar: () {},
        onPost: () {},
      ),
      width: 360,
      scale: 1.0,
    );
    expect(tester.takeException(), isNull);
  });
}
