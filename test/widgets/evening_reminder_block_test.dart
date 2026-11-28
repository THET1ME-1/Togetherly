import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/settings/evening_reminder_block.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Блок «Вечернее напоминание» в листе уведомлений (TOG-113).
void main() {
  late List<(bool, bool, int, bool)> saved;

  Future<void> pump(WidgetTester tester, {double width = 360, double scale = 1}) async {
    saved = [];
    tester.view.physicalSize = Size(width * 3, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        // Часы телефона 24-часовые, как у большинства наших людей; иначе
        // английская разметка покажет «9:00 PM».
        data: MediaQueryData(
          textScaler: TextScaler.linear(scale),
          size: Size(width, 800),
          alwaysUse24HourFormat: true,
        ),
        child: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              EveningReminderBlock(
                onSave: ({required mood, required task, required atMinutes, required custom}) async =>
                    saved.add((mood, task, atMinutes, custom)),
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
  }

  Switch switchOf(WidgetTester tester, String key) => tester.widget<Switch>(
      find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Switch)));

  testWidgets('по умолчанию оба включены и 21:00', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pump(tester);
    expect(switchOf(tester, 'er-mood').value, isTrue);
    expect(switchOf(tester, 'er-task').value, isTrue);
    expect(find.text('21:00'), findsOneWidget);
  });

  testWidgets('выключение не ставит «сам настраивал», включение ставит', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('er-mood')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(saved.last, (false, true, 21 * 60, false));
    expect(switchOf(tester, 'er-mood').value, isFalse);
    await tester.tap(find.byKey(const ValueKey('er-mood')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(saved.last, (true, true, 21 * 60, true));
  });

  testWidgets('выбор времени ставит «сам настраивал»', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('er-time')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('OK'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(saved.last, (true, true, 21 * 60, true));
  });

  testWidgets('прошлая метка не теряется при выключении', (tester) async {
    SharedPreferences.setMockInitialValues({'flutter.remind_custom': true});
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('er-task')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(saved.last, (true, false, 21 * 60, true));
  });

  testWidgets('читает сохранённое', (tester) async {
    SharedPreferences.setMockInitialValues({
      'flutter.remind_task': false,
      'flutter.remind_at': '20:30',
    });
    await pump(tester);
    expect(switchOf(tester, 'er-task').value, isFalse);
    expect(find.text('20:30'), findsOneWidget);
  });

  testWidgets('оба выключены — время не выбрать', (tester) async {
    SharedPreferences.setMockInitialValues({
      'flutter.remind_mood': false,
      'flutter.remind_task': false,
    });
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('er-time')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(TimePickerDialog), findsNothing);
  });

  testWidgets('время открывает выбор часов', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('er-time')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TimePickerDialog), findsOneWidget);
  });

  testWidgets('320 точек и крупный шрифт без переполнения', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pump(tester, width: 320, scale: 1.3);
    expect(tester.takeException(), isNull);
  });
}
