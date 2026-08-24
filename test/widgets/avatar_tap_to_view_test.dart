import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/avatar_widget.dart';

/// Аватар открывается на весь экран по нажатию.
///
/// Просьба из поддержки: лицо партнёра видно кружком в 36–44 точки, и
/// разглядеть его негде. Проверяем ровно границы поведения — где тап работает,
/// а где обязан молчать: в списках нажатие уже занято строкой, а у кружка с
/// буквой открывать нечего.
class _Routes extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) pushes++;
  }
}

void main() {
  Future<_Routes> pump(
    WidgetTester tester, {
    required bool tapToView,
    String url = 'https://example.com/avatar.jpg',
  }) async {
    final routes = _Routes();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [routes],
      home: Scaffold(
        body: Center(
          child: AvatarWidget(
            uid: 'partner-uid',
            liveUrl: url,
            name: 'Аня',
            size: 40,
            primary: Colors.pink,
            tapToView: tapToView,
          ),
        ),
      ),
    ));
    return routes;
  }

  testWidgets('нажатие открывает фотографию', (tester) async {
    final routes = await pump(tester, tapToView: true);
    await tester.tap(find.byType(AvatarWidget));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(routes.pushes, 1);
  });

  testWidgets('без разрешения тап ничего не открывает', (tester) async {
    final routes = await pump(tester, tapToView: false);
    await tester.tap(find.byType(AvatarWidget));
    await tester.pump(const Duration(milliseconds: 300));
    expect(routes.pushes, 0);
  });

  testWidgets('у кружка с буквой открывать нечего', (tester) async {
    final routes = await pump(tester, tapToView: true, url: '');
    await tester.tap(find.byType(AvatarWidget));
    await tester.pump(const Duration(milliseconds: 300));
    expect(routes.pushes, 0);
    expect(find.text('А'), findsOneWidget,
        reason: 'вместо фотографии остаётся первая буква имени');
  });
}
