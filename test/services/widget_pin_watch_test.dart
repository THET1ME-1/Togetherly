import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/widget_pin_watch.dart';

/// Обращения 25.11.2026 (Android, 1.44): «добавляю на рабочий стол, а ничего
/// не появляется». Лончер Xiaomi отвечает «умею ставить виджеты», но без
/// разрешения «Ярлыки на рабочем столе» молча ничего не делает, а приложение
/// при этом показывало зелёное «Виджет добавлен». Теперь итог просьбы
/// узнаётся по самому рабочему столу.
void main() {
  testWidgets('виджет встал — итог «поставлен», даже без окна системы', (tester) async {
    var count = 2;
    WidgetPinOutcome? outcome;
    watchWidgetPin(count: () async => count, before: 2).then((o) => outcome = o);
    await tester.pump(const Duration(milliseconds: 900));
    count = 3;
    await tester.pump(const Duration(milliseconds: 500));
    expect(outcome, WidgetPinOutcome.placed);
  });

  testWidgets('система промолчала: ни окна, ни виджета — итог «тишина»', (tester) async {
    WidgetPinOutcome? outcome;
    watchWidgetPin(count: () async => 2, before: 2).then((o) => outcome = o);
    await tester.pump(const Duration(seconds: 3));
    expect(outcome, isNull, reason: 'рано: окно системы могло ещё не открыться');
    await tester.pump(const Duration(seconds: 2));
    expect(outcome, WidgetPinOutcome.silent);
  });

  testWidgets('окно системы открылось и закрылось без виджета — «отменили»', (tester) async {
    WidgetPinOutcome? outcome;
    watchWidgetPin(count: () async => 2, before: 2).then((o) => outcome = o);
    await tester.pump(const Duration(milliseconds: 500));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    // Человек думает над окном дольше «тихого» срока — это не тишина.
    await tester.pump(const Duration(seconds: 10));
    expect(outcome, isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 3));
    expect(outcome, WidgetPinOutcome.cancelled);
  });

  testWidgets('виджет встал после окна системы — «поставлен»', (tester) async {
    var count = 0;
    WidgetPinOutcome? outcome;
    watchWidgetPin(count: () async => count, before: 0).then((o) => outcome = o);
    await tester.pump(const Duration(milliseconds: 500));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(seconds: 6));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 500));
    count = 1;
    await tester.pump(const Duration(milliseconds: 500));
    expect(outcome, WidgetPinOutcome.placed);
  });
}
