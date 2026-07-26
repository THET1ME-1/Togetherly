import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/common/m3_num_pad.dart';

/// Своя цифровая клавиатура вместо системной: тёмная системная панель посреди
/// светлого листа выглядела чужой, а половину экрана занимала зря.
void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('На панели десять цифр, стирание и готово', (tester) async {
    await tester.pumpWidget(host(M3NumPad(
      onDigit: (_) {},
      onBackspace: () {},
      onDone: () {},
    )));

    for (final d in ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9']) {
      expect(find.text(d), findsOneWidget, reason: 'цифра $d');
    }
    expect(find.byIcon(Icons.backspace_outlined), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
  });

  testWidgets('Цифра приходит нажатием', (tester) async {
    final typed = <String>[];
    await tester.pumpWidget(host(M3NumPad(
      onDigit: typed.add,
      onBackspace: () {},
    )));

    await tester.tap(find.text('7'));
    await tester.tap(find.text('0'));
    expect(typed, ['7', '0']);
  });

  testWidgets('Стирание и готово зовут свои обработчики', (tester) async {
    var erased = 0;
    var done = 0;
    await tester.pumpWidget(host(M3NumPad(
      onDigit: (_) {},
      onBackspace: () => erased++,
      onDone: () => done++,
    )));

    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
    expect(erased, 1);
    expect(done, 1);
  });

  testWidgets('Без onDone кнопка готово не рисуется', (tester) async {
    await tester.pumpWidget(host(M3NumPad(
      onDigit: (_) {},
      onBackspace: () {},
    )));

    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
    // Сетка остаётся ровной: место кнопки не схлопывается.
    expect(find.byType(M3NumPad), findsOneWidget);
  });

  testWidgets('Действие сверху показывается, когда его передали',
      (tester) async {
    await tester.pumpWidget(host(M3NumPad(
      onDigit: (_) {},
      onBackspace: () {},
      actionLabel: 'Сохранить',
      onAction: () {},
    )));

    expect(find.text('Сохранить'), findsOneWidget);
  });
}
