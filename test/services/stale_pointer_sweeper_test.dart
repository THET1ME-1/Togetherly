// Обращение 231 (Realme 10 Pro, 04.10.2026): после любого действия приложение
// перестаёт принимать нажатия, «Назад» работает, перезапуск лечит. Механизм —
// flutter#193549: системный жест забирает касание, конец его до Flutter не
// доходит, список остаётся в перетаскивании и через IgnorePointer не пускает
// нажатия к кнопкам. Тесты идут по порядку: первый без защиты, второй с ней.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/stale_pointer_sweeper.dart';

void main() {
  var taps = 0;

  Widget app() => MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              for (var i = 0; i < 30; i++)
                SizedBox(
                  height: 80,
                  child: ElevatedButton(
                    key: ValueKey(i),
                    onPressed: () => taps++,
                    child: Text('$i'),
                  ),
                ),
            ],
          ),
        ),
      );

  // Касание, у которого не пришёл конец: прокрутило список и пропало.
  Future<void> loseADrag(WidgetTester tester) async {
    final lost = await tester.createGesture(pointer: 1);
    await lost.down(const Offset(200, 300), timeStamp: Duration.zero);
    await lost.moveBy(const Offset(0, -60), timeStamp: const Duration(milliseconds: 50));
    await lost.moveBy(const Offset(0, -60), timeStamp: const Duration(milliseconds: 100));
    await tester.pump();
  }

  Future<void> tapButton(WidgetTester tester, int pointer, Duration at) async {
    final g = await tester.createGesture(pointer: pointer);
    await g.down(tester.getCenter(find.byKey(const ValueKey(5))), timeStamp: at);
    await g.up(timeStamp: at + const Duration(milliseconds: 60));
    await tester.pump();
  }

  testWidgets('без защиты потерянное касание запирает нажатия', (tester) async {
    taps = 0;
    await tester.pumpWidget(app());
    await loseADrag(tester);
    await tapButton(tester, 2, const Duration(seconds: 6));
    await tapButton(tester, 3, const Duration(seconds: 7));
    expect(taps, 0, reason: 'так и выглядит обращение 231');
  });

  testWidgets('с защитой второе нажатие уже проходит', (tester) async {
    StalePointerSweeper.install();
    taps = 0;
    await tester.pumpWidget(app());
    await loseADrag(tester);
    await tapButton(tester, 2, const Duration(seconds: 6));
    await tapButton(tester, 3, const Duration(seconds: 7));
    expect(StalePointerSweeper.swept, greaterThan(0));
    expect(taps, greaterThan(0));
  });

  testWidgets('палец, который держат и двигают, не отменяется', (tester) async {
    StalePointerSweeper.install();
    final before = StalePointerSweeper.swept;
    await tester.pumpWidget(app());
    final held = await tester.createGesture(pointer: 10);
    await held.down(const Offset(200, 300), timeStamp: Duration.zero);
    await held.moveBy(const Offset(0, -2), timeStamp: const Duration(seconds: 3));
    await tapButton(tester, 11, const Duration(seconds: 5));
    expect(StalePointerSweeper.swept, before, reason: 'палец жив: двигался секунду назад');
    await held.up(timeStamp: const Duration(seconds: 6));
  });
}
