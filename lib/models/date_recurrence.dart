/// Повтор памятной даты пары: подмножество RRULE из RFC 5545.
///
/// Правило хранится текстом в записи (`FREQ=YEARLY`,
/// `FREQ=WEEKLY;BYDAY=WE,SU;UNTIL=20261215`), его же раскладывает сервер для
/// напоминаний (`pocketbase/hotpath/date_rules.py`, библиотека dateutil). Чтобы
/// приложение и напоминания не разошлись ни на день, оба сверяются с одним
/// файлом примеров — `test/fixtures/date_recurrence_cases.json`.
///
/// Счёт только календарный: день, месяц, год. Сутки перевода часов длятся
/// 23 или 25 часов, поэтому `Duration(days:)` здесь не годится.
library;

enum RepeatFreq { daily, weekly, monthly, yearly }

/// Строки пресетов в листе «Повтор» — как в Google Календаре.
enum RepeatPresetKind {
  none,
  daily,
  weekdays,
  weekly,
  biweekly,
  monthlyDay,
  monthlyNth,
  monthlyLast,
  yearly,
  custom,
}

class RepeatPreset {
  const RepeatPreset(this.kind, this.rrule);
  final RepeatPresetKind kind;
  final String rrule;
}

/// Коды дней недели RRULE; индекс + 1 — `DateTime.weekday`.
const List<String> kWeekdayCodes = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

/// Сколько промахов подряд терпим, прежде чем решить, что правило не даёт
/// дней вовсе (31-е число раз в год от февраля).
const int _maxMisses = 1000;

class Recurrence {
  const Recurrence({
    required this.freq,
    this.interval = 1,
    this.weekdays = const {},
    this.monthDay,
    this.monthNth,
    this.monthWeekday,
    this.until,
    this.count,
  });

  final RepeatFreq freq;
  final int interval;

  /// Неделя: дни, 1 — понедельник … 7 — воскресенье.
  final Set<int> weekdays;

  /// Месяц: число месяца, или [monthNth]-й [monthWeekday] (−1 — последний).
  final int? monthDay;
  final int? monthNth;
  final int? monthWeekday;

  /// Последний день повтора включительно, или сколько раз всего.
  final DateTime? until;
  final int? count;

  Recurrence copyWith({
    RepeatFreq? freq,
    int? interval,
    Set<int>? weekdays,
    int? Function()? monthDay,
    int? Function()? monthNth,
    int? Function()? monthWeekday,
    DateTime? Function()? until,
    int? Function()? count,
  }) =>
      Recurrence(
        freq: freq ?? this.freq,
        interval: interval ?? this.interval,
        weekdays: weekdays ?? this.weekdays,
        monthDay: monthDay != null ? monthDay() : this.monthDay,
        monthNth: monthNth != null ? monthNth() : this.monthNth,
        monthWeekday: monthWeekday != null ? monthWeekday() : this.monthWeekday,
        until: until != null ? until() : this.until,
        count: count != null ? count() : this.count,
      );

  /// Разбор правила. Пусто, незнакомо или сломано — null (дата без повтора):
  /// чужое правило не должно ронять экран.
  static Recurrence? parse(String rrule, DateTime start) {
    var text = rrule.trim().toUpperCase();
    if (text.startsWith('RRULE:')) text = text.substring(6);
    if (text.isEmpty) return null;

    final parts = <String, String>{};
    for (final piece in text.split(';')) {
      final i = piece.indexOf('=');
      if (i <= 0) return null;
      parts[piece.substring(0, i)] = piece.substring(i + 1);
    }
    const known = {'FREQ', 'INTERVAL', 'BYDAY', 'BYMONTHDAY', 'UNTIL', 'COUNT', 'WKST'};
    if (!parts.keys.every(known.contains)) return null;
    if ((parts['WKST'] ?? 'MO') != 'MO') return null;

    final freq = switch (parts['FREQ']) {
      'DAILY' => RepeatFreq.daily,
      'WEEKLY' => RepeatFreq.weekly,
      'MONTHLY' => RepeatFreq.monthly,
      'YEARLY' => RepeatFreq.yearly,
      _ => null,
    };
    if (freq == null) return null;

    final interval = int.tryParse(parts['INTERVAL'] ?? '1');
    if (interval == null || interval < 1) return null;

    DateTime? until;
    if (parts['UNTIL'] != null) {
      until = _parseRuleDay(parts['UNTIL']!);
      if (until == null) return null;
    }
    int? count;
    if (parts['COUNT'] != null) {
      count = int.tryParse(parts['COUNT']!);
      if (count == null || count < 1) return null;
    }
    if (until != null && count != null) return null;

    final byDay = parts['BYDAY'];
    final byMonthDay = parts['BYMONTHDAY'];
    final day = _day(start);

    switch (freq) {
      case RepeatFreq.daily:
      case RepeatFreq.yearly:
        if (byDay != null || byMonthDay != null) return null;
        return Recurrence(freq: freq, interval: interval, until: until, count: count);
      case RepeatFreq.weekly:
        if (byMonthDay != null) return null;
        final days = <int>{};
        for (final code in (byDay ?? kWeekdayCodes[day.weekday - 1]).split(',')) {
          final i = kWeekdayCodes.indexOf(code);
          if (i < 0) return null;
          days.add(i + 1);
        }
        return Recurrence(
            freq: freq, interval: interval, weekdays: days, until: until, count: count);
      case RepeatFreq.monthly:
        if (byDay != null && byMonthDay != null) return null;
        if (byDay != null) {
          final m = RegExp(r'^([+-]?\d)(MO|TU|WE|TH|FR|SA|SU)$').firstMatch(byDay);
          if (m == null) return null;
          final nth = int.parse(m.group(1)!);
          if (nth == 0 || nth.abs() > 5) return null;
          return Recurrence(
            freq: freq,
            interval: interval,
            monthNth: nth,
            monthWeekday: kWeekdayCodes.indexOf(m.group(2)!) + 1,
            until: until,
            count: count,
          );
        }
        final md = int.tryParse(byMonthDay ?? '${day.day}');
        if (md == null || md < 1 || md > 31) return null;
        return Recurrence(
            freq: freq, interval: interval, monthDay: md, until: until, count: count);
    }
  }

  /// Правило текстом, в одном порядке полей — по нему сравниваются пресеты.
  String toRrule() {
    final parts = <String>['FREQ=${freq.name.toUpperCase()}'];
    if (interval > 1) parts.add('INTERVAL=$interval');
    if (freq == RepeatFreq.weekly) {
      final days = weekdays.toList()..sort();
      parts.add('BYDAY=${days.map((d) => kWeekdayCodes[d - 1]).join(',')}');
    }
    if (freq == RepeatFreq.monthly) {
      parts.add(monthNth != null
          ? 'BYDAY=$monthNth${kWeekdayCodes[(monthWeekday ?? 1) - 1]}'
          : 'BYMONTHDAY=$monthDay');
    }
    if (until != null) parts.add('UNTIL=${_ruleDay(until!)}');
    if (count != null) parts.add('COUNT=$count');
    return parts.join(';');
  }

  /// Все дни повтора от [start] по порядку. День начала, не попавший в
  /// правило, повтором не считается (как у dateutil), COUNT считает выданное.
  Iterable<DateTime> days(DateTime start) sync* {
    final s = _day(start);
    final last = until == null ? null : _day(until!);
    var given = 0;
    var misses = 0;

    // День уже за UNTIL — повтор кончился.
    bool over(DateTime d) => last != null && d.isAfter(last);

    switch (freq) {
      case RepeatFreq.daily:
        for (var k = 0;; k++) {
          final d = DateTime(s.year, s.month, s.day + k * interval);
          if (over(d)) return;
          yield d;
          if (count != null && ++given >= count!) return;
        }
      case RepeatFreq.weekly:
        final order = weekdays.toList()..sort();
        final monday = DateTime(s.year, s.month, s.day - (s.weekday - 1));
        for (var w = 0;; w++) {
          for (final wd in order) {
            final d = DateTime(monday.year, monday.month, monday.day + w * 7 * interval + wd - 1);
            if (d.isBefore(s)) continue;
            if (over(d)) return;
            yield d;
            if (count != null && ++given >= count!) return;
          }
        }
      case RepeatFreq.monthly:
        for (var k = 0;; k++) {
          final first = DateTime(s.year, s.month + k * interval, 1);
          final d = monthNth != null
              ? _nthWeekday(first.year, first.month, monthNth!, monthWeekday ?? s.weekday)
              : (monthDay! <= _daysIn(first.year, first.month)
                  ? DateTime(first.year, first.month, monthDay!)
                  : null);
          if (d == null || d.isBefore(s)) {
            if (++misses > _maxMisses) return;
            continue;
          }
          misses = 0;
          if (over(d)) return;
          yield d;
          if (count != null && ++given >= count!) return;
        }
      case RepeatFreq.yearly:
        for (var k = 0;; k++) {
          final year = s.year + k * interval;
          if (s.day > _daysIn(year, s.month)) {
            if (++misses > _maxMisses) return;
            continue;
          }
          misses = 0;
          final d = DateTime(year, s.month, s.day);
          if (over(d)) return;
          yield d;
          if (count != null && ++given >= count!) return;
        }
    }
  }
}

/// Дни даты в окне [from, to] включительно, без выброшенных ([exdates] —
/// `ГГГГ-ММ-ДД`).
List<DateTime> occurrencesOf({
  required DateTime start,
  required String rrule,
  required Set<String> exdates,
  required DateTime from,
  required DateTime to,
}) {
  final lo = _day(from);
  final hi = _day(to);
  return occurrencesAfter(start: start, rrule: rrule, exdates: exdates, from: lo)
      .takeWhile((d) => !d.isAfter(hi))
      .toList();
}

/// Дни даты начиная с [from], по порядку, лениво (у повтора без конца их
/// бесконечно много — брать `take`).
Iterable<DateTime> occurrencesAfter({
  required DateTime start,
  required String rrule,
  required Set<String> exdates,
  required DateTime from,
}) {
  final lo = _day(from);
  final rule = Recurrence.parse(rrule, start);
  final all = rule == null ? [_day(start)] : rule.days(start);
  return all.where((d) => !d.isBefore(lo) && !exdates.contains(dayKey(d)));
}

/// Пресеты листа «Повтор» от дня начала, как у Google: «во 2-е воскресенье»
/// только для 1–4-го, «в последнее» — только в последнюю неделю месяца.
List<RepeatPreset> repeatPresets(DateTime start) {
  final d = _day(start);
  final wd = kWeekdayCodes[d.weekday - 1];
  final nth = (d.day - 1) ~/ 7 + 1;
  final isLast = d.day + 7 > _daysIn(d.year, d.month);
  return [
    const RepeatPreset(RepeatPresetKind.none, ''),
    const RepeatPreset(RepeatPresetKind.daily, 'FREQ=DAILY'),
    const RepeatPreset(RepeatPresetKind.weekdays, 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR'),
    RepeatPreset(RepeatPresetKind.weekly, 'FREQ=WEEKLY;BYDAY=$wd'),
    RepeatPreset(RepeatPresetKind.biweekly, 'FREQ=WEEKLY;INTERVAL=2;BYDAY=$wd'),
    RepeatPreset(RepeatPresetKind.monthlyDay, 'FREQ=MONTHLY;BYMONTHDAY=${d.day}'),
    if (nth <= 4) RepeatPreset(RepeatPresetKind.monthlyNth, 'FREQ=MONTHLY;BYDAY=$nth$wd'),
    if (isLast) RepeatPreset(RepeatPresetKind.monthlyLast, 'FREQ=MONTHLY;BYDAY=-1$wd'),
    const RepeatPreset(RepeatPresetKind.yearly, 'FREQ=YEARLY'),
  ];
}

/// Какой строке листа соответствует правило; своё — [RepeatPresetKind.custom].
RepeatPresetKind presetOf(String rrule, DateTime start) {
  final rule = Recurrence.parse(rrule, start);
  if (rule == null) return RepeatPresetKind.none;
  final text = rule.toRrule();
  for (final p in repeatPresets(start)) {
    if (p.rrule == text) return p.kind;
  }
  return RepeatPresetKind.custom;
}

/// `ГГГГ-ММ-ДД` — так дни лежат в записи и в списке выброшенных.
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Сколько дней в месяце.
int daysInMonth(int year, int month) => _daysIn(year, month);

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

int _daysIn(int year, int month) => DateTime(year, month + 1, 0).day;

/// [nth]-й (−1 — последний) день недели [weekday] месяца или null.
DateTime? _nthWeekday(int year, int month, int nth, int weekday) {
  final total = _daysIn(year, month);
  if (nth > 0) {
    final firstWd = DateTime(year, month, 1).weekday;
    final day = 1 + (weekday - firstWd + 7) % 7 + (nth - 1) * 7;
    return day <= total ? DateTime(year, month, day) : null;
  }
  final lastWd = DateTime(year, month, total).weekday;
  final day = total - (lastWd - weekday + 7) % 7 - (-nth - 1) * 7;
  return day >= 1 ? DateTime(year, month, day) : null;
}

String _ruleDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

DateTime? _parseRuleDay(String text) {
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})').firstMatch(text);
  if (m == null) return null;
  return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
}
