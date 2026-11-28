import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/settings/evening_reminder_block.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Блок «Вечернее напоминание» в листе уведомлений (TOG-113).
///
/// Экран обязан показывать то, что сервер сделает. У пункта три режима:
/// `on`, `off` и «по привычке» (пусто, пока блок не открывали). Первый показ
/// записывает положение выключателей явно: сначала берётся выбор с сервера
/// (второй телефон, переустановка), потом привычка.
void main() {
  late List<(String?, String?, String?)> saved;
  late int inFlight;
  late int maxInFlight;

  Future<void> pump(
    WidgetTester tester, {
    bool moodHabit = false,
    bool taskHabit = false,
    bool paired = true,
    Future<Map<String, dynamic>?> Function()? server,
    double width = 360,
    double scale = 1,
  }) async {
    saved = [];
    inFlight = 0;
    maxInFlight = 0;
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
                moodHabit: moodHabit,
                taskHabit: taskHabit,
                paired: paired,
                uid: 'me',
                loadServer: server ?? () async => const {},
                onSave: ({mood, task, at}) async {
                  inFlight++;
                  if (inFlight > maxInFlight) maxInFlight = inFlight;
                  saved.add((mood, task, at));
                  await Future<void>.delayed(const Duration(milliseconds: 50));
                  inFlight--;
                },
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// Выбор этого человека, уже отправленный (`remind_set_at` = 100), и тот же
  /// выбор в профиле на сервере.
  Map<String, Object> mine({required String mood, required String task}) => {
        'flutter.remind_owner': 'me',
        'flutter.remind_mood_mode': mood,
        'flutter.remind_task_mode': task,
        'flutter.remind_set_at': 100,
      };
  Map<String, dynamic> server({required String mood, required String task}) =>
      {'remindMood': mood, 'remindTask': task, 'remindAt': '', 'remindSetAt': 100};

  Switch switchOf(WidgetTester tester, String key) => tester.widget<Switch>(
      find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Switch)));

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  // Привычку на телефоне считают по неполным данным (отметки только этой
  // пары, прогресс до загрузки), и первый показ мог записать «выкл» тому,
  // кто отмечает настроение каждый день. Пока решение не приходит с
  // сервера, показ ничего не пишет (ревью 28.11.2026).
  testWidgets('первый показ ничего не пишет', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pump(tester, moodHabit: true, taskHabit: false);
    expect(switchOf(tester, 'er-mood').value, isTrue);
    expect(switchOf(tester, 'er-task').value, isFalse);
    expect(find.text('21:00'), findsOneWidget);
    expect(saved, isEmpty);
  });

  testWidgets('выбор с сервера сильнее привычки и не переписывается', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pump(tester, moodHabit: true, taskHabit: true,
        server: () async =>
            {'remindMood': 'off', 'remindTask': 'on', 'remindAt': '23:00', 'remindSetAt': 200});
    expect(switchOf(tester, 'er-mood').value, isFalse);
    expect(switchOf(tester, 'er-task').value, isTrue);
    expect(find.text('23:00'), findsOneWidget);
    expect(saved, isEmpty);
  });

  testWidgets('сервер не ответил — показываем привычку, но не записываем', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pump(tester, moodHabit: true, server: () async => null);
    expect(switchOf(tester, 'er-mood').value, isTrue);
    expect(saved, isEmpty);
    await tap(tester, 'er-mood');
    expect(saved.last, ('off', null, null), reason: 'нажатие — уже выбор человека');
  });

  // Сервер без сети отвечает секундами — выключатели не ждут его. Нажатие —
  // выбор человека, и поздний ответ сервера его не перетирает.
  testWidgets('нажатие до ответа сервера не перетирается поздним ответом', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final late = Completer<Map<String, dynamic>?>();
    await pump(tester, moodHabit: true, server: () => late.future);
    expect(switchOf(tester, 'er-mood').onChanged, isNotNull);
    await tap(tester, 'er-mood');
    expect(saved.last, ('off', null, null));
    late.complete({'remindMood': 'on', 'remindSetAt': 999});
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(switchOf(tester, 'er-mood').value, isFalse);
  });

  testWidgets('своё на телефоне видно сразу и сверяется с профилем', (tester) async {
    SharedPreferences.setMockInitialValues({
      'flutter.remind_owner': 'me',
      'flutter.remind_mood_mode': 'on',
      'flutter.remind_task_mode': 'off',
      'flutter.remind_at': '20:30',
      'flutter.remind_set_at': 100,
    });
    var asked = false;
    await pump(tester, server: () async {
      asked = true;
      return {'remindMood': 'on', 'remindTask': 'off', 'remindAt': '20:30', 'remindSetAt': 100};
    });
    expect(asked, isTrue);
    expect(switchOf(tester, 'er-mood').value, isTrue);
    expect(switchOf(tester, 'er-task').value, isFalse);
    expect(find.text('20:30'), findsOneWidget);
    expect(saved, isEmpty);
  });

  testWidgets('выбор с другого телефона приезжает при открытии', (tester) async {
    SharedPreferences.setMockInitialValues({
      'flutter.remind_owner': 'me',
      'flutter.remind_mood_mode': 'on',
      'flutter.remind_set_at': 100,
    });
    await pump(tester, server: () async => {'remindMood': 'off', 'remindSetAt': 300});
    expect(switchOf(tester, 'er-mood').value, isFalse);
    expect(saved, isEmpty);
  });

  testWidgets('сохранения идут по очереди, последнее — с итоговым состоянием', (tester) async {
    SharedPreferences.setMockInitialValues(mine(mood: 'on', task: 'on'));
    await pump(tester, server: () async => server(mood: 'on', task: 'on'));
    await tester.tap(find.byKey(const ValueKey('er-mood')));
    await tester.pump(const Duration(milliseconds: 10));
    await tester.tap(find.byKey(const ValueKey('er-mood')));
    await tester.pump(const Duration(milliseconds: 10));
    await tester.tap(find.byKey(const ValueKey('er-task')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(maxInFlight, 1);
    expect(saved.last, ('on', 'off', null));
  });

  testWidgets('выбор времени уходит на сервер', (tester) async {
    SharedPreferences.setMockInitialValues(mine(mood: 'on', task: 'on'));
    await pump(tester, server: () async => server(mood: 'on', task: 'on'));
    await tester.tap(find.byKey(const ValueKey('er-time')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('OK'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 100));
    expect(saved.last, ('on', 'on', '21:00'));
  });

  testWidgets('оба выключены — время не выбрать', (tester) async {
    SharedPreferences.setMockInitialValues(mine(mood: 'off', task: 'off'));
    await pump(tester, server: () async => server(mood: 'off', task: 'off'));
    await tester.tap(find.byKey(const ValueKey('er-time')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(TimePickerDialog), findsNothing);
  });

  testWidgets('без пары строки задания нет', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pump(tester, paired: false, moodHabit: false, taskHabit: true);
    expect(find.byKey(const ValueKey('er-task')), findsNothing);
    expect(saved, isEmpty);
  });

  testWidgets('320 точек и крупный шрифт без переполнения', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pump(tester, width: 320, scale: 1.3);
    expect(tester.takeException(), isNull);
  });
}
