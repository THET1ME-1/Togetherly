import '../dict_strings.dart';
import '../models/date_recurrence.dart';
import '../models/date_reminder.dart';
import '../models/pair_date.dart';
import '../services/locale_service.dart';
import 'xmas_text.dart' show xtPluralForm;

/// Строка «Наших дат» из словаря (`l10n/dict/dates.dart`) с подстановкой `{имя}`.
String dt(String key, [Map<String, Object> args = const {}]) {
  var s = trKey(key);
  args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}

/// Строка с числом: форма `.1`, `.2` или `.5` ключа [base], `{n}` — само число.
String dtCount(String base, int n, [Map<String, Object> args = const {}]) {
  final form = xtPluralForm(n, LocaleService.instance.language.code);
  return dt('$base.$form', {'n': n, ...args});
}

/// «Сегодня», «Завтра», «через 6 дней».
String untilText(int days) {
  if (days <= 0) return dt('dt.today');
  if (days == 1) return dt('dt.tomorrow');
  return dtCount('dt.inDays', days);
}

/// Время по-человечески: «9:00», «19:30».
String clockText(int hour, int minute) => '$hour:${minute.toString().padLeft(2, '0')}';

/// Повтор двумя частями, как в строке формы и в листе: главное («Каждый
/// месяц») и уточнение («2-е воскресенье», «в ср и вс, до 15 декабря»).
(String, String) repeatText(String rrule, DateTime start) {
  final rule = Recurrence.parse(rrule, start);
  if (rule == null) return (dt('dt.rNone'), '');
  switch (presetOf(rrule, start)) {
    case RepeatPresetKind.none:
      return (dt('dt.rNone'), '');
    case RepeatPresetKind.daily:
      return (dt('dt.rDaily'), '');
    case RepeatPresetKind.weekdays:
      return (dt('dt.rWeekdays'), dt('dt.rWeekdaysDetail'));
    case RepeatPresetKind.weekly:
      return (dt('dt.rWeekly'), dt('dt.onWd.${start.weekday}'));
    case RepeatPresetKind.biweekly:
      return (dt('dt.rBiweekly'), dt('dt.onWd.${start.weekday}'));
    case RepeatPresetKind.monthlyDay:
    case RepeatPresetKind.monthlyNth:
    case RepeatPresetKind.monthlyLast:
      return (dt('dt.rMonthly'), monthDetail(rule, start));
    case RepeatPresetKind.yearly:
      return (dt('dt.rYearly'), LocaleService.current.dayLogDate(start));
    case RepeatPresetKind.custom:
      return (_customHead(rule), _customDetail(rule, start));
  }
}

/// Повтор одной строкой — для списка дат и подписи под днём.
String repeatLine(String rrule, DateTime start) {
  final (main, detail) = repeatText(rrule, start);
  return detail.isEmpty ? main : '$main, $detail';
}

/// Какой день месяца: «8-го числа», «2-е воскресенье», «последний четверг».
String monthDetail(Recurrence rule, DateTime start) {
  final nth = rule.monthNth;
  if (nth == null) return dt('dt.monthDay', {'n': rule.monthDay ?? start.day});
  final wd = rule.monthWeekday ?? start.weekday;
  if (nth < 0) return dt('dt.lastWd.$wd');
  final ord = nth <= 4 ? dt('dt.ord.$nth') : '$nth';
  return dt('dt.nthWd.$wd', {'o': ord});
}

String _customHead(Recurrence rule) {
  final n = rule.interval;
  if (n == 1) {
    return switch (rule.freq) {
      RepeatFreq.daily => dt('dt.rDaily'),
      RepeatFreq.weekly => dt('dt.rWeekly'),
      RepeatFreq.monthly => dt('dt.rMonthly'),
      RepeatFreq.yearly => dt('dt.rYearly'),
    };
  }
  return switch (rule.freq) {
    RepeatFreq.daily => dtCount('dt.everyDays', n),
    RepeatFreq.weekly => dtCount('dt.everyWeeks', n),
    RepeatFreq.monthly => dtCount('dt.everyMonths', n),
    RepeatFreq.yearly => dtCount('dt.everyYears', n),
  };
}

String _customDetail(Recurrence rule, DateTime start) {
  final s = LocaleService.current;
  final parts = <String>[
    switch (rule.freq) {
      RepeatFreq.daily => '',
      RepeatFreq.weekly => _weekdaysText(rule.weekdays, start),
      RepeatFreq.monthly => monthDetail(rule, start),
      RepeatFreq.yearly => s.dayLogDate(start),
    },
    if (rule.until != null) dt('dt.until', {'date': s.dayLogDate(rule.until!)}),
    if (rule.count != null) dtCount('dt.times', rule.count!),
  ];
  return parts.where((p) => p.isNotEmpty).join(', ');
}

/// «в воскресенье» или «в ср и вс» — короткими именами, если дней несколько.
String _weekdaysText(Set<int> days, DateTime start) {
  final sorted = days.toList()..sort();
  if (sorted.length == 1) return dt('dt.onWd.${sorted.first}');
  final code = LocaleService.instance.language.code;
  final names = [
    for (final d in sorted)
      code == 'ru' || code == 'uk'
          ? LocaleService.current.shortWeekdays[d - 1].toLowerCase()
          : LocaleService.current.shortWeekdays[d - 1],
  ];
  final joined = names.length == 2
      ? names.join(dt('dt.and'))
      : '${names.sublist(0, names.length - 1).join(', ')}${dt('dt.and')}${names.last}';
  return dt('dt.onDays', {'days': joined});
}

/// Напоминание словами: «За день в 9:00», «За 30 минут», «В момент начала».
String reminderText(int minutes, {required bool allDay}) {
  if (allDay) {
    final p = allDayParts(minutes);
    final time = clockText(p.hour, p.minute);
    final d = p.daysBefore;
    if (d == 0) return dt('dt.remSameDay', {'time': time});
    if (d == 1) return dt('dt.remDayAt', {'time': time});
    if (d == 30) return dt('dt.remMonthAt', {'time': time});
    if (d == 7) return dt('dt.remWeekAt', {'time': time});
    if (d % 7 == 0) return dtCount('dt.remWeeksAt', d ~/ 7, {'time': time});
    return dtCount('dt.remDaysAt', d, {'time': time});
  }
  final t = timedParts(minutes);
  if (t.amount == 0) return dt('dt.remAtStart');
  return switch (t.unit) {
    ReminderUnit.minutes => dtCount('dt.remMinutes', t.amount),
    ReminderUnit.hours => t.amount == 1 ? dt('dt.remHour') : dtCount('dt.remHours', t.amount),
    ReminderUnit.days => t.amount == 1 ? dt('dt.remDay') : dtCount('dt.remDays', t.amount),
    ReminderUnit.weeks => t.amount == 1 ? dt('dt.remWeek') : dtCount('dt.remWeeks', t.amount),
  };
}

/// Название даты в этот повтор: своя — как назвали, годовщина — «2 года
/// вместе», день рождения — «День рождения» или «Твой день рождения».
String dateTitle(PairDate date, DateTime occurrenceDay) => switch (date.autoKind) {
      AutoDateKind.none => date.title,
      AutoDateKind.anniversary => dtCount('dt.years', date.yearsAt(occurrenceDay)),
      AutoDateKind.birthday => dt(date.isMine ? 'dt.birthdayMine' : 'dt.birthday'),
    };

/// Откуда готовая дата: «из таймера „Вместе“», «Лиза · из профиля».
String autoSourceText(PairDate date) => switch (date.autoKind) {
      AutoDateKind.none => '',
      AutoDateKind.anniversary => dt('dt.fromTimer'),
      AutoDateKind.birthday => date.isMine || date.subjectName.isEmpty
          ? dt('dt.fromProfile')
          : '${date.subjectName} · ${dt('dt.fromProfile')}',
    };

/// Сколько календарных дней от [from] до [to] (без часов и переводов времени).
int daysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// Подпись повтора: «4 декабря, пятница · 19:00 · добавила Лиза»,
/// «17 января, воскресенье · Лиза · исполнится 27».
String occurrenceLine(
  DateOccurrence o, {
  required String myUid,
  required String partnerName,
  required String partnerGender,
  bool withDate = true,
}) {
  final s = LocaleService.current;
  final d = o.date;
  return [
    if (withDate) '${s.dayLogDate(o.day)}, ${s.dayLogWeekday(o.day)}',
    if (o.at != null) clockText(o.at!.hour, o.at!.minute),
    if (d.autoKind == AutoDateKind.birthday && !d.isMine && d.subjectName.isNotEmpty) d.subjectName,
    if (d.autoKind == AutoDateKind.birthday && d.yearsAt(o.day) > 0) dt('dt.turns', {'n': d.yearsAt(o.day)}),
    if (!d.isAuto && d.authorUid.isNotEmpty && d.authorUid != myUid && partnerName.isNotEmpty)
      addedByText(partnerName, partnerGender),
  ].join(' · ');
}

/// «добавила Лиза» — по роду партнёра (`female`/`male`), иначе нейтрально.
String addedByText(String name, String gender) {
  final form = switch (gender) {
    'female' => 'f',
    'male' => 'm',
    _ => 'x',
  };
  return dt('dt.addedBy.$form', {'name': name});
}
