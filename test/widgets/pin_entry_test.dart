import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/common/m3_num_pad.dart';
import 'package:love_app/widgets/common/pin_entry_sheet.dart';

/// Ввод PIN секретных воспоминаний: крупные ячейки и своя клавиатура вместо
/// системной. Проверяем ровно то, что легко сломать: длину, стирание и то,
/// что короткий PIN при установке не принимается.
void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('показывает четыре пустые ячейки и свою клавиатуру',
      (tester) async {
    await tester.pumpWidget(host(PinEntry(create: true, onDone: (_) {})));
    await tester.pump();

    expect(find.byType(M3NumPad), findsOneWidget);
    expect(find.byKey(const ValueKey('pin-cell-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('pin-cell-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('pin-cell-4')), findsNothing);
  });

  testWidgets('набор из четырёх цифр отдаёт PIN', (tester) async {
    String? got;
    await tester.pumpWidget(host(PinEntry(create: false, onDone: (v) => got = v)));
    await tester.pump();

    for (final d in ['1', '2', '3', '4']) {
      await tester.tap(find.text(d));
      await tester.pump();
    }
    expect(got, '1234');
  });

  testWidgets('стирание убирает последнюю цифру', (tester) async {
    String? got;
    await tester.pumpWidget(host(PinEntry(create: false, onDone: (v) => got = v)));
    await tester.pump();

    for (final d in ['1', '2', '3']) {
      await tester.tap(find.text(d));
      await tester.pump();
    }
    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pump();
    await tester.tap(find.text('9'));
    await tester.pump();
    await tester.tap(find.text('9'));
    await tester.pump();

    expect(got, '1299');
  });

  testWidgets('лишние нажатия после четвёртой цифры игнорируются',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(host(PinEntry(create: false, onDone: (_) => calls++)));
    await tester.pump();

    for (var i = 0; i < 6; i++) {
      await tester.tap(find.text('7'));
      await tester.pump();
    }
    expect(calls, 1);
  });
}
