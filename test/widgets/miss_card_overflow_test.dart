import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/miss_widget_card.dart';

/// Карточка «Скучаю» в каталоге уже, чем виджет на рабочем столе, а кегль
/// числа подобран под стол. На четырёхзначном счёте число выезжало из плитки
/// на подпись «Сегодня» (снимок 20.09.2026).
Widget _host(Widget child, {required double width, required double height}) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, height: height, child: child),
        ),
      ),
    );

MissWidgetCard _card(MissCardSize size, {int mine = 1000, int partner = 198}) =>
    MissWidgetCard(
      size: size,
      myCount: mine,
      partnerCount: partner,
      roles: const {
        'surface': Color(0xFFFFF8F7),
        'onSurface': Color(0xFF22191A),
        'onSurfaceVariant': Color(0xFF524344),
        'outline': Color(0xFF857373),
        'primary': Color(0xFFE56A77),
        'onPrimary': Color(0xFFFFFFFF),
        'primaryContainer': Color(0xFFFEEAF1),
        'onPrimaryContainer': Color(0xFFFF7E8B),
        'tertiaryContainer': Color(0xFFFFDDB4),
        'onTertiaryContainer': Color(0xFF5C421A),
      },
      meLabel: 'Вы',
      partnerName: 'JB SHARAN',
      sendLabel: 'Скучаю',
      whenLabel: 'Сегодня',
      sentToday: false,
    );

void main() {
  testWidgets('четырёхзначный счёт не вылезает из плитки 4×2', (tester) async {
    await tester.pumpWidget(_host(_card(MissCardSize.medium), width: 300, height: 142));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('1000'), findsOneWidget);
    expect(find.text('Сегодня'), findsOneWidget);
  });

  testWidgets('узкая карточка 2×2 держит тот же счёт', (tester) async {
    await tester.pumpWidget(_host(_card(MissCardSize.small), width: 150, height: 150));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('полоска 4×1 не переполняется', (tester) async {
    await tester.pumpWidget(_host(_card(MissCardSize.strip), width: 300, height: 70));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('шестизначный счёт сокращается, а не ломает плитку', (tester) async {
    await tester.pumpWidget(
      _host(_card(MissCardSize.medium, mine: 123456), width: 300, height: 142),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('123,5K'), findsOneWidget);
  });
}
