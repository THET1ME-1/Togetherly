import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/screens/home/home_bottom_nav.dart';
import 'package:love_app/theme/app_theme.dart';

/// Быстрый вход в чат — маленькая кнопка поверх круглой боковой.
///
/// До этого с главной до переписки было два шага: вкладка «Связь», а уже
/// оттуда кнопка чата. Значок садится на угол круглой кнопки и ведёт прямо в
/// чат; сама круглая кнопка при этом работает как раньше.
Widget _nav({VoidCallback? onChat, VoidCallback? onSide}) => MaterialApp(
      home: Scaffold(
        body: HomeBottomNav(
          selectedIndex: 0,
          theme: AppThemes.pink,
          isPaired: true,
          onTap: (_) {},
          onCreatePin: onSide ?? () {},
          sideIsArrow: true,
          onChat: onChat,
        ),
      ),
    );

void main() {
  testWidgets('значок чата стоит на круглой кнопке', (tester) async {
    await tester.pumpWidget(_nav(onChat: () {}));
    await tester.pump();

    expect(find.byKey(HomeBottomNav.chatBadgeKey), findsOneWidget);
  });

  testWidgets('нажатие ведёт в чат, а не в ленту', (tester) async {
    var chatTaps = 0;
    var laneTaps = 0;
    await tester.pumpWidget(_nav(onChat: () => chatTaps++, onSide: () => laneTaps++));
    await tester.pump();

    await tester.tap(find.byKey(HomeBottomNav.chatBadgeKey));
    await tester.pump();

    expect(chatTaps, 1);
    expect(laneTaps, 0, reason: 'значок не должен задевать кнопку под собой');
  });

  testWidgets('кнопка чата стоит НАД круглой, а не на ней', (tester) async {
    await tester.pumpWidget(_nav(onChat: () {}));
    await tester.pump();

    final chat = tester.getRect(find.byKey(HomeBottomNav.chatBadgeKey));
    final side = tester.getRect(find.byIcon(Icons.arrow_forward_rounded));

    expect(chat.bottom, lessThanOrEqualTo(side.top),
        reason: 'это отдельная кнопка выше круглой, а не значок поверх неё');
    expect((chat.center.dx - side.center.dx).abs(), lessThan(4),
        reason: 'обе стоят по одной оси, столбиком');
  });

  testWidgets('без обработчика значка нет', (tester) async {
    // У одиночки переписки не существует — значку неоткуда взяться.
    await tester.pumpWidget(_nav());
    await tester.pump();

    expect(find.byKey(HomeBottomNav.chatBadgeKey), findsNothing);
  });

  testWidgets('круглая кнопка продолжает работать сама по себе',
      (tester) async {
    var laneTaps = 0;
    await tester.pumpWidget(_nav(onChat: () {}, onSide: () => laneTaps++));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
    await tester.pump();

    expect(laneTaps, 1);
  });
}
