import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/daily_task.dart';
import 'package:love_app/models/evening_reminder.dart';

/// Вечернее напоминание (TOG-113): привычка, по которой телефон выбирает
/// начальное положение выключателей при первом показе блока. Пороги обязаны
/// совпадать с сервером — по ним же он напоминает тем, кто блок не открывал.
void main() {
  final now = DateTime.utc(2026, 11, 28, 18);

  group('настроение', () {
    test('четыре разных дня из 14 — привычка', () {
      final marks = [
        for (final d in [1, 3, 5, 9]) now.subtract(Duration(days: d)),
      ];
      expect(moodHabitOf(marks, now), isTrue);
    });

    test('несколько отметок в один день считаются одним днём', () {
      final day = now.subtract(const Duration(days: 2));
      final marks = [
        for (var h = 0; h < 6; h++) day.add(Duration(hours: h)),
        now.subtract(const Duration(days: 4)),
        now.subtract(const Duration(days: 6)),
      ];
      expect(moodHabitOf(marks, now), isFalse);
    });

    test('старше двух недель не считается', () {
      final marks = [
        for (final d in [15, 16, 17, 18, 20]) now.subtract(Duration(days: d)),
      ];
      expect(moodHabitOf(marks, now), isFalse);
    });

    test('отметок нет', () => expect(moodHabitOf(const [], now), isFalse));
  });

  group('задание дня', () {
    test('пара делала за последние три дня', () {
      expect(taskHabitOf(const DailyTaskProgress(date: '2026-11-25', done: {'a'}), now), isTrue);
      expect(taskHabitOf(const DailyTaskProgress(date: '2026-11-24', done: {'a'}), now), isFalse);
    });

    test('пустой список выполненного — не привычка', () {
      expect(taskHabitOf(const DailyTaskProgress(date: '2026-11-28', done: {}), now), isFalse);
      expect(taskHabitOf(const DailyTaskProgress.empty(), now), isFalse);
    });
  });

  test('пороги те же, что у сервера', () {
    final py = File('pocketbase/evening_reminder_push.py').readAsStringSync();
    int value(String name) =>
        int.parse(RegExp('^$name = (\\d+)', multiLine: true).firstMatch(py)!.group(1)!);
    expect(kHabitMoodDays, value('HABIT_MOOD_DAYS'));
    expect(kHabitTaskDays, value('HABIT_TASK_DAYS'));
    expect(kHabitWindowDays, value('HABIT_DAYS'));
  });
}
