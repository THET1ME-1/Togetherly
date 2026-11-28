import 'package:pocketbase/pocketbase.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as zones;

import '../utils/calendar_day.dart';
import 'date_recurrence.dart';
import 'date_reminder.dart';

/// Готовые даты: показываются рядом со своими, но не правятся.
enum AutoDateKind { none, anniversary, birthday }

/// Один повтор даты, как его видит этот телефон.
class DateOccurrence {
  const DateOccurrence(this.date, this.day, this.at);

  final PairDate date;

  /// День по часам телефона (у даты со временем у партнёра в другом поясе
  /// он может не совпасть с днём автора).
  final DateTime day;

  /// Момент начала по часам телефона; null у даты на весь день.
  final DateTime? at;
}

/// Памятная дата пары — запись коллекции `pair_dates` (TOG-61).
///
/// День хранится текстом `ГГГГ-ММ-ДД`: дата на весь день одна и та же у обоих.
/// Дата со временем — момент: день и время в поясе автора [tz], у каждого
/// показывается по его часам.
class PairDate {
  PairDate({
    required this.id,
    this.groupId = '',
    this.authorUid = '',
    this.title = '',
    this.symbol = 'favorite',
    this.note = '',
    required this.day,
    this.time,
    this.tz = '',
    this.rrule = '',
    Set<String>? exdates,
    List<int>? reminders,
    this.created = '',
    this.autoKind = AutoDateKind.none,
    this.subjectUid = '',
    this.subjectName = '',
    this.isMine = false,
  })  : exdates = exdates ?? const {},
        reminders = reminders ?? const [];

  final String id;
  final String groupId;
  final String authorUid;
  final String title;

  /// Имя Material Symbol (`favorite`, `cake`).
  final String symbol;
  final String note;

  /// Первый день; null — запись битая, показывать нечего.
  final DateTime? day;

  /// `ЧЧ:ММ` или null — весь день.
  final String? time;

  /// IANA-пояс автора на момент сохранения.
  final String tz;

  /// Тело RRULE или пусто — без повтора.
  final String rrule;
  final Set<String> exdates;
  final List<int> reminders;
  final String created;

  final AutoDateKind autoKind;

  /// Чья это готовая дата: день рождения — того, у кого он.
  final String subjectUid;
  final String subjectName;
  final bool isMine;

  bool get allDay => time == null;
  bool get isAuto => autoKind != AutoDateKind.none;
  bool get repeats => Recurrence.parse(rrule, day ?? DateTime(2000)) != null;

  factory PairDate.fromPb(RecordModel r) => PairDate.fromMap({...r.data, 'id': r.id});

  factory PairDate.fromMap(Map<String, dynamic> m) {
    final rawEx = m['exdates'];
    return PairDate(
      id: '${m['id'] ?? ''}',
      groupId: '${m['group_id'] ?? ''}',
      authorUid: '${m['author_uid'] ?? ''}',
      title: '${m['title'] ?? ''}',
      symbol: '${m['symbol'] ?? ''}'.isEmpty ? 'favorite' : '${m['symbol']}',
      note: '${m['note'] ?? ''}',
      day: _parseDay('${m['day'] ?? ''}'),
      time: _parseTime('${m['start_time'] ?? ''}'),
      tz: '${m['tz'] ?? ''}',
      rrule: '${m['rrule'] ?? ''}',
      exdates: {
        if (rawEx is List)
          for (final e in rawEx)
            if (_parseDay('$e') != null) '$e',
      },
      reminders: normalizeReminders(m['reminders'] is List ? m['reminders'] as List : null),
      created: '${m['created'] ?? ''}',
    );
  }

  /// Запись для местного хранилища и сервера — поля коллекции как есть.
  Map<String, dynamic> toMap({String? groupId}) => {
        'id': id,
        'group_id': groupId ?? this.groupId,
        'author_uid': authorUid,
        'title': title,
        'symbol': symbol,
        'note': note,
        'day': day == null ? '' : dayKey(day!),
        'start_time': time ?? '',
        'tz': tz,
        'rrule': rrule,
        'exdates': exdates.toList()..sort(),
        'reminders': reminders,
        'created': created,
      };

  PairDate copyWith({
    String? title,
    String? symbol,
    String? note,
    DateTime? day,
    String? Function()? time,
    String? tz,
    String? rrule,
    Set<String>? exdates,
    List<int>? reminders,
  }) =>
      PairDate(
        id: id,
        groupId: groupId,
        authorUid: authorUid,
        title: title ?? this.title,
        symbol: symbol ?? this.symbol,
        note: note ?? this.note,
        day: day ?? this.day,
        time: time != null ? time() : this.time,
        tz: tz ?? this.tz,
        rrule: rrule ?? this.rrule,
        exdates: exdates ?? this.exdates,
        reminders: reminders ?? this.reminders,
        created: created,
        autoKind: autoKind,
        subjectUid: subjectUid,
        subjectName: subjectName,
        isMine: isMine,
      );

  /// Начало первого дня по часам телефона; null у даты на весь день. Форма
  /// показывает время так, а сохраняет прежние день и пояс, если их не трогали.
  DateTime? get startAt => day == null || allDay ? null : _moment(day!);

  /// Начало повтора в день автора [authorDay] по часам телефона; у даты на
  /// весь день — сам день.
  DateTime momentOn(DateTime authorDay) =>
      allDay ? DateTime(authorDay.year, authorDay.month, authorDay.day) : _moment(authorDay);

  /// «Только этот день»: повтор остаётся, день [occurrenceDay] выбрасывается.
  PairDate skipping(DateTime occurrenceDay) =>
      copyWith(exdates: {...exdates, dayKey(occurrenceDay)});

  /// «Этот и следующие»: повтор кончается накануне [occurrenceDay]. С первого
  /// дня — null: удалять всю дату.
  PairDate? endingBefore(DateTime occurrenceDay) {
    final start = day;
    final rule = start == null ? null : Recurrence.parse(rrule, start);
    if (start == null || rule == null || !occurrenceDay.isAfter(start)) return null;
    final last = calendarDay(occurrenceDay, -1);
    return copyWith(rrule: rule.copyWith(until: () => last, count: () => null).toRrule());
  }

  /// Сколько лет исполняется в этот повтор: годовщина — «2 года вместе»,
  /// день рождения — возраст.
  int yearsAt(DateTime occurrenceDay) => occurrenceDay.year - (day?.year ?? occurrenceDay.year);

  /// Повторы в окне [from, to] по дням телефона.
  List<DateOccurrence> occurrencesBetween(DateTime from, DateTime to) {
    final start = day;
    if (start == null) return const [];
    final lo = _dateOnly(from);
    final hi = _dateOnly(to);
    if (allDay) {
      return [
        for (final d in occurrencesOf(start: start, rrule: rrule, exdates: exdates, from: lo, to: hi))
          DateOccurrence(this, d, null),
      ];
    }
    // День автора и день телефона расходятся не больше чем на сутки.
    final out = <DateOccurrence>[];
    for (final d in occurrencesOf(
      start: start,
      rrule: rrule,
      exdates: exdates,
      from: calendarDay(lo, -1),
      to: calendarDay(hi, 1),
    )) {
      final at = _moment(d);
      final localDay = _dateOnly(at);
      if (localDay.isBefore(lo) || localDay.isAfter(hi)) continue;
      out.add(DateOccurrence(this, localDay, at));
    }
    return out;
  }

  /// Ближайший повтор не раньше [now]: дата на весь день — до конца её дня,
  /// дата со временем — пока не наступил её момент.
  DateOccurrence? nextFrom(DateTime now) {
    final start = day;
    if (start == null) return null;
    final today = _dateOnly(now);
    if (allDay) {
      for (final d in occurrencesAfter(start: start, rrule: rrule, exdates: exdates, from: today)) {
        return DateOccurrence(this, d, null);
      }
      return null;
    }
    var looked = 0;
    for (final d in occurrencesAfter(
        start: start, rrule: rrule, exdates: exdates, from: calendarDay(today, -1))) {
      final at = _moment(d);
      if (!at.isBefore(now)) return DateOccurrence(this, _dateOnly(at), at);
      if (++looked > 400) return null;
    }
    return null;
  }

  /// Начало повтора в день [d] автора — по часам телефона.
  DateTime _moment(DateTime d) {
    final parts = (time ?? '00:00').split(':');
    final h = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final location = _location(tz);
    if (location == null) return DateTime(d.year, d.month, d.day, h, m);
    final there = zones.TZDateTime(location, d.year, d.month, d.day, h, m);
    return DateTime.fromMillisecondsSinceEpoch(there.millisecondsSinceEpoch);
  }
}

/// Ближайший повтор каждой даты от [now], по порядку: сначала ближе по дню,
/// внутри дня — по времени (дата на весь день — в начале дня).
List<DateOccurrence> upcomingOccurrences(Iterable<PairDate> dates, DateTime now) {
  final out = [for (final d in dates) d.nextFrom(now)].whereType<DateOccurrence>().toList()
    ..sort((a, b) => (a.at ?? a.day).compareTo(b.at ?? b.day));
  return out;
}

/// Повторы всех дат в окне [from, to] по дням телефона: `ГГГГ-ММ-ДД` → список.
Map<String, List<DateOccurrence>> occurrencesByDay(
    Iterable<PairDate> dates, DateTime from, DateTime to) {
  final out = <String, List<DateOccurrence>>{};
  for (final d in dates) {
    for (final o in d.occurrencesBetween(from, to)) {
      out.putIfAbsent(dayKey(o.day), () => []).add(o);
    }
  }
  return out;
}

/// Годовщина пары из даты начала и дни рождения из профилей: показываются
/// рядом со своими датами и попадают в «ближайшую», но не правятся. Их
/// напоминания — прежняя `CelebrationNotificationService`.
List<PairDate> autoDates({
  required DateTime? start,
  required Map<String, DateTime> birthdays,
  required String myUid,
  required Map<String, String> names,
}) {
  return [
    if (start != null)
      PairDate(
        id: 'auto:anniversary',
        day: _dateOnly(start),
        rrule: 'FREQ=YEARLY',
        // Сам день начала — ещё не годовщина.
        exdates: {dayKey(start)},
        symbol: 'favorite',
        autoKind: AutoDateKind.anniversary,
      ),
    for (final e in birthdays.entries)
      PairDate(
        id: 'auto:birthday:${e.key}',
        day: _dateOnly(e.value),
        rrule: 'FREQ=YEARLY',
        symbol: 'cake',
        autoKind: AutoDateKind.birthday,
        subjectUid: e.key,
        subjectName: names[e.key] ?? '',
        isMine: e.key == myUid,
      ),
  ];
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime? _parseDay(String text) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(text);
  if (m == null) return null;
  final y = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), d = int.parse(m.group(3)!);
  if (mo < 1 || mo > 12 || d < 1 || d > daysInMonth(y, mo)) return null;
  return DateTime(y, mo, d);
}

String? _parseTime(String text) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text.trim());
  if (m == null) return null;
  final h = int.parse(m.group(1)!), min = int.parse(m.group(2)!);
  if (h > 23 || min > 59) return null;
  return '${h.toString().padLeft(2, '0')}:${m.group(2)}';
}

bool _tzReady = false;

zones.Location? _location(String name) {
  if (name.isEmpty) return null;
  if (!_tzReady) {
    tzdata.initializeTimeZones();
    _tzReady = true;
  }
  try {
    return zones.getLocation(name);
  } catch (_) {
    return null;
  }
}
