/// Напоминания памятной даты: число минут до начала.
///
/// У даты на весь день начало — полночь, и минуты читаются по часам на стене:
/// 900 — «за день в 9:00», −540 — «в этот день в 9:00», 9540 — «за неделю в
/// 9:00». Так же их читает сервер, который и шлёт напоминания
/// (`pocketbase/hotpath/date_rules.py`, `по_стене`). У даты со временем
/// минуты — просто промежуток до начала.
library;

/// Не больше напоминаний на дату — столько же принимает сервер.
const int kMaxReminders = 5;

/// Пределы: «в этот день» не позже 23:59, раньше всего — за 60 дней.
const int _minMinutes = -1439;
const int _maxMinutes = 60 * 24 * 60;

/// Пресеты листа «Напоминание», как в Google Календаре.
List<int> reminderPresets({required bool allDay}) => allDay
    ? const [-540, 900, 2340, 9540, 42660]
    : const [0, 5, 10, 30, 60, 1440];

/// Что ставим новой дате: на весь день — «в этот день» и «за день» в 9:00,
/// со временем — за 30 минут.
List<int> defaultReminders({required bool allDay}) =>
    allDay ? const [-540, 900] : const [30];

class AllDayReminder {
  const AllDayReminder({required this.daysBefore, required this.hour, required this.minute});
  final int daysBefore;
  final int hour;
  final int minute;

  @override
  bool operator ==(Object other) =>
      other is AllDayReminder &&
      other.daysBefore == daysBefore &&
      other.hour == hour &&
      other.minute == minute;

  @override
  int get hashCode => Object.hash(daysBefore, hour, minute);

  @override
  String toString() => 'за $daysBefore дн. в $hour:$minute';
}

/// Минуты до полуночи → за сколько дней и во сколько по часам на стене.
AllDayReminder allDayParts(int minutes) {
  if (minutes <= 0) {
    final m = -minutes.clamp(_minMinutes, 0);
    return AllDayReminder(daysBefore: 0, hour: m ~/ 60, minute: m % 60);
  }
  final days = (minutes + 1439) ~/ 1440;
  final wall = days * 1440 - minutes;
  return AllDayReminder(daysBefore: days, hour: wall ~/ 60, minute: wall % 60);
}

/// Обратно: за [daysBefore] дней в [hour]:[minute] → минуты до полуночи.
int allDayMinutes(int daysBefore, int hour, int minute) =>
    daysBefore * 1440 - (hour * 60 + minute);

enum ReminderUnit { minutes, hours, days, weeks }

class TimedReminder {
  const TimedReminder(this.amount, this.unit);
  final int amount;
  final ReminderUnit unit;

  @override
  bool operator ==(Object other) =>
      other is TimedReminder && other.amount == amount && other.unit == unit;

  @override
  int get hashCode => Object.hash(amount, unit);

  @override
  String toString() => '$amount ${unit.name}';
}

const Map<ReminderUnit, int> _unitMinutes = {
  ReminderUnit.minutes: 1,
  ReminderUnit.hours: 60,
  ReminderUnit.days: 1440,
  ReminderUnit.weeks: 10080,
};

/// Промежуток самой крупной целой единицей: 120 — «2 часа», 90 — «90 минут».
TimedReminder timedParts(int minutes) {
  if (minutes <= 0) return const TimedReminder(0, ReminderUnit.minutes);
  for (final unit in [ReminderUnit.weeks, ReminderUnit.days, ReminderUnit.hours]) {
    final size = _unitMinutes[unit]!;
    if (minutes % size == 0) return TimedReminder(minutes ~/ size, unit);
  }
  return TimedReminder(minutes, ReminderUnit.minutes);
}

int timedMinutes(int amount, ReminderUnit unit) => amount * _unitMinutes[unit]!;

/// Список из записи: целые минуты в пределах, без повторов, по порядку
/// срабатывания (раньше всего — первым), не больше пяти.
List<int> normalizeReminders(Iterable<dynamic>? raw) {
  final out = <int>{};
  for (final v in raw ?? const []) {
    final m = v is int ? v : (v is num ? v.toInt() : int.tryParse('$v'));
    if (m == null || m < _minMinutes || m > _maxMinutes) continue;
    out.add(m);
  }
  final sorted = out.toList()..sort();
  return sorted.take(kMaxReminders).toList();
}

/// Переключили «весь день»: напоминания переводятся по смыслу, а не теряются.
/// «За день в 9:00» становится «за день», «за 30 минут» — «в этот день в 9:00».
List<int> convertReminders(List<int> reminders, {required bool toAllDay}) {
  return normalizeReminders([
    for (final m in reminders)
      if (toAllDay)
        allDayMinutes(m < 1440 ? 0 : (m + 1439) ~/ 1440, 9, 0)
      else
        allDayParts(m).daysBefore * 1440,
  ]);
}
