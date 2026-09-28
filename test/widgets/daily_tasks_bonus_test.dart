import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/daily_task.dart';
import 'package:love_app/services/daily_task_service.dart';
import 'package:love_app/widgets/home/daily_tasks_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Бонусное задание: четвёртая строка, которая появляется только после трёх
/// закрытых основных.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpCard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(320 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
            size: Size(320, 900), textScaler: TextScaler.linear(1.3)),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: DailyTasksCard(
              groupId: 'g-bonus',
              partnerName: 'Лера',
              onOpenTask: (_) {},
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
  }

  void setDone(Iterable<String> ids) {
    final key = DailyTaskProgress.dayKey(DateTime.now());
    DailyTaskService.instance.applyGroupRaw({
      'daily_tasks': {'date': key, 'done': ids.toList()},
    });
  }

  testWidgets('пока основные не закрыты, бонуса нет', (tester) async {
    final s = DailyTaskService.instance..bind(groupId: 'g-bonus');
    setDone([s.today.first.id]);
    await pumpCard(tester);
    expect(s.bonus, isNull);
    expect(find.text('Bonus'), findsNothing);
    expect(find.text('Бонус'), findsNothing);
  });

  testWidgets('три закрыты — бонус четвёртой строкой, без переполнений',
      (tester) async {
    final s = DailyTaskService.instance..bind(groupId: 'g-bonus');
    setDone(s.today.map((t) => t.id));
    await pumpCard(tester);
    final bonus = s.bonus;
    expect(bonus, isNotNull);
    expect(find.text(bonus!.title('Лера')), findsOneWidget);
    expect(tester.takeException(), isNull);

    setDone([...s.today.map((t) => t.id), bonus.id]);
    await tester.pump(const Duration(milliseconds: 300));
    expect(s.bonusDone, isTrue);
    expect(tester.takeException(), isNull);
  });
}
