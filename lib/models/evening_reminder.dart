import 'daily_task.dart';

/// Вечернее напоминание (TOG-113): привычка, по которой сервер напоминает
/// тем, кто блок настроек не открывал (`pocketbase/evening_reminder_push.py`),
/// а телефон при первом показе блока выбирает начальное положение
/// выключателей. Числа обязаны совпадать с сервером — сверяет
/// test/models/evening_reminder_test.dart.

/// Окно привычки к настроению, дней.
const int kHabitWindowDays = 14;

/// Сколько разных дней из окна нужно отмечать настроение.
const int kHabitMoodDays = 4;

/// За сколько последних дней пара должна была делать задание.
const int kHabitTaskDays = 3;

/// Отмечал настроение хотя бы в [kHabitMoodDays] разных дней (дни по UTC, как
/// считает сервер) за последние [kHabitWindowDays].
bool moodHabitOf(Iterable<DateTime> marks, DateTime now) {
  final since = now.toUtc().subtract(const Duration(days: kHabitWindowDays));
  final days = <String>{
    for (final t in marks)
      if (t.toUtc().isAfter(since)) DailyTaskProgress.dayKey(t),
  };
  return days.length >= kHabitMoodDays;
}

/// Пара выполняла задание дня за последние [kHabitTaskDays] дней (по UTC, как
/// меняются задания в приложении).
bool taskHabitOf(DailyTaskProgress progress, DateTime now) {
  if (progress.done.isEmpty || progress.date.isEmpty) return false;
  final from = DailyTaskProgress.dayKey(
      now.toUtc().subtract(const Duration(days: kHabitTaskDays)));
  return progress.date.compareTo(from) >= 0;
}
