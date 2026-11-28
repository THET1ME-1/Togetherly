import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/date_reminder.dart';

void main() {
  group('пресеты как в Google Календаре', () {
    test('весь день: в этот день, за день, за 2 дня, за неделю, за месяц — в 9:00', () {
      expect(reminderPresets(allDay: true), [-540, 900, 2340, 9540, 42660]);
    });

    test('со временем: в момент начала, 5, 10, 30 минут, час, день', () {
      expect(reminderPresets(allDay: false), [0, 5, 10, 30, 60, 1440]);
    });
  });

  group('весь день: минуты по часам на стене', () {
    test('разбор', () {
      expect(allDayParts(-540), const AllDayReminder(daysBefore: 0, hour: 9, minute: 0));
      expect(allDayParts(900), const AllDayReminder(daysBefore: 1, hour: 9, minute: 0));
      expect(allDayParts(9540), const AllDayReminder(daysBefore: 7, hour: 9, minute: 0));
      expect(allDayParts(3120), const AllDayReminder(daysBefore: 3, hour: 20, minute: 0));
      expect(allDayParts(0), const AllDayReminder(daysBefore: 0, hour: 0, minute: 0));
    });

    test('сборка — обратно те же минуты', () {
      for (final m in [-540, 900, 2340, 9540, 42660, 4140, -1230, 1]) {
        final p = allDayParts(m);
        expect(allDayMinutes(p.daysBefore, p.hour, p.minute), m, reason: '$m');
      }
    });
  });

  group('со временем: самая крупная целая единица', () {
    test('разбор', () {
      expect(timedParts(0), const TimedReminder(0, ReminderUnit.minutes));
      expect(timedParts(30), const TimedReminder(30, ReminderUnit.minutes));
      expect(timedParts(120), const TimedReminder(2, ReminderUnit.hours));
      expect(timedParts(90), const TimedReminder(90, ReminderUnit.minutes));
      expect(timedParts(2880), const TimedReminder(2, ReminderUnit.days));
      expect(timedParts(10080), const TimedReminder(1, ReminderUnit.weeks));
    });

    test('сборка', () {
      expect(timedMinutes(2, ReminderUnit.hours), 120);
      expect(timedMinutes(3, ReminderUnit.weeks), 30240);
    });
  });

  test('список напоминаний: без повторов, по порядку, не больше пяти', () {
    expect(normalizeReminders([900, -540, 900, 30, 60, 120, 5000]), [-540, 30, 60, 120, 900]);
    expect(normalizeReminders(['900', 'x', null, -2000]), [900]);
  });

  test('по умолчанию у новой даты', () {
    expect(defaultReminders(allDay: true), [-540, 900]);
    expect(defaultReminders(allDay: false), [30]);
  });

  test('смена «весь день» переводит напоминания, а не теряет их', () {
    // Было «за день в 9:00» у даты на весь день — у даты в 19:00 это «за день».
    expect(convertReminders([900, -540], toAllDay: false), [0, 1440]);
    expect(convertReminders([30, 1440], toAllDay: true), [-540, 900]);
  });
}
