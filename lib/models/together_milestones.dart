/// Дорожка вех пары: что пройдено, где вы сегодня и что впереди.
///
/// Виджет «Вместе» показывал один процент до ближайшей круглой даты, и считал
/// его натив — там же лежали русские склонения, поэтому немец видел «дней» и
/// «года» по-русски. Теперь путь считается здесь, а натив рисует линию и
/// печатает готовые строки.
///
/// Вех две породы: сотни дней (100, 200, 300…) и годовщины. Годовщина —
/// календарная: пара празднует её своим числом, а не через 365 суток, поэтому
/// високосный год не сдвигает праздник на день назад.
library;

import '../services/locale_service.dart';

/// Одна отметка на дорожке.
class Milestone {
  const Milestone({
    required this.days,
    required this.date,
    required this.daysLeft,
    this.isAnniversary = false,
    this.years = 0,
  });

  /// Сколько дней вместе на этой отметке.
  final int days;

  /// Календарная дата отметки: пройденной или будущей.
  final DateTime date;

  /// Сколько суток до неё; у пройденной — ноль.
  final int daysLeft;

  /// Годовщина, а не круглое число дней.
  final bool isAnniversary;

  /// Какая по счёту годовщина; у отметки в днях — ноль.
  final int years;
}

/// Путь целиком: прошлая отметка, сегодняшний день, ближайшая и годовщина.
class MilestoneTrack {
  const MilestoneTrack({
    required this.days,
    required this.previous,
    required this.next,
    required this.anniversary,
    required this.percent,
  });

  /// Сколько дней вместе сегодня.
  final int days;

  /// Последняя пройденная отметка; `null` — пара ещё в первой сотне.
  final Milestone? previous;

  /// Ближайшая будущая отметка: сотня или годовщина, что раньше.
  final Milestone next;

  /// Ближайшая годовщина — её виджет показывает отдельной строкой, даже
  /// когда впереди сначала круглое число дней.
  final Milestone anniversary;

  /// Сколько пути пройдено от прошлой отметки до следующей, в процентах.
  final int percent;
}

/// Сотни дней, между которыми лежит [days].
int _hundredBefore(int days) => (days ~/ 100) * 100;

/// Годовщина номер [n] от даты начала, календарём.
///
/// 29 февраля у пары, начавшейся в високосный год, отмечается 1 марта:
/// `DateTime(2027, 2, 29)` в Dart нормализуется сам, и это ровно то, что
/// делает календарь телефона.
DateTime _anniversaryOf(DateTime start, int n) =>
    DateTime(start.year + n, start.month, start.day);

/// Дата через [n] календарных суток от [d].
///
/// Не `add(Duration(days: n))`: при переводе часов сутки бывают 23-часовыми, и
/// «сотый день» уезжал на день назад — на этом же спотыкался счётчик «дней
/// вместе» (см. calendarDaysBetween в utils/couple_days.dart).
DateTime _plusDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

int _daysBetween(DateTime a, DateTime b) {
  final from = DateTime(a.year, a.month, a.day);
  final to = DateTime(b.year, b.month, b.day);
  return to.difference(from).inDays;
}

/// Дорожка на сегодня.
///
/// [start] — день, с которого пара считает себя вместе; [today] — сегодняшняя
/// дата; [anniversary] — своя дата из профиля, если пара её задала (она важнее
/// даты начала счёта: люди празднуют знакомство, а не день установки).
MilestoneTrack milestoneTrack({
  required DateTime start,
  required DateTime today,
  DateTime? anniversary,
}) {
  // Дата начала в будущем — считаем, что путь ещё не начался: отрицательные
  // дни на виджете читаются как поломка, а не как «скоро начнём».
  final days = _daysBetween(start, today).clamp(0, 1 << 30);

  final anniversaryBase = anniversary ?? start;
  // Годовщина, до которой осталось ноль дней, — это сегодняшний праздник, а не
  // повод показать следующий через год.
  var years = today.year - anniversaryBase.year;
  while (_anniversaryOf(anniversaryBase, years).isAfter(today)) {
    years -= 1;
  }
  final todayIsAnniversary =
      _daysBetween(_anniversaryOf(anniversaryBase, years), today) == 0 &&
          years >= 1;
  final nextYears = todayIsAnniversary ? years : years + 1;
  final nextAnniversaryDate = _anniversaryOf(anniversaryBase, nextYears);
  final nextAnniversary = Milestone(
    days: _daysBetween(start, nextAnniversaryDate),
    date: nextAnniversaryDate,
    daysLeft: _daysBetween(today, nextAnniversaryDate),
    isAnniversary: true,
    years: nextYears,
  );

  final nextHundredDays = _hundredBefore(days) + 100;
  final nextHundred = Milestone(
    days: nextHundredDays,
    date: _plusDays(start, nextHundredDays),
    daysLeft: nextHundredDays - days,
  );

  final next = nextAnniversary.daysLeft < nextHundred.daysLeft
      ? nextAnniversary
      : nextHundred;

  // Позади — та отметка, от которой считаем путь: сотня или прошлая годовщина,
  // смотря что ближе к сегодняшнему дню.
  final hundredBack = _hundredBefore(days);
  Milestone? previous;
  if (hundredBack >= 100) {
    previous = Milestone(
      days: hundredBack,
      date: _plusDays(start, hundredBack),
      daysLeft: 0,
    );
  }
  if (years >= 1) {
    final passedAnniversaryDate = _anniversaryOf(anniversaryBase, years);
    final passedDays = _daysBetween(start, passedAnniversaryDate);
    if (previous == null || passedDays > previous.days) {
      previous = Milestone(
        days: passedDays,
        date: passedAnniversaryDate,
        daysLeft: 0,
        isAnniversary: true,
        years: years,
      );
    }
  }

  final from = previous?.days ?? 0;
  final span = (next.days - from).clamp(1, 1 << 30);
  final percent = (((days - from) / span) * 100).round().clamp(0, 100);

  return MilestoneTrack(
    days: days,
    previous: previous,
    next: next,
    anniversary: nextAnniversary,
    percent: percent,
  );
}

/// Готовые строки дорожки: их печатает натив, не считая ничего сам.
///
/// До этого склонения («день», «дня», «дней») и слово «через» лежали в
/// Kotlin по-русски, и немец с испанцем читали русский текст — та же мина,
/// что уже ловили в подписи «сколько уже вместе».
class TrackLabels {
  const TrackLabels({
    required this.previousTitle,
    required this.previousSub,
    required this.todayTitle,
    required this.todaySub,
    required this.nextTitle,
    required this.nextSub,
    required this.anniversaryTitle,
    required this.anniversarySub,
  });

  /// Пройденная веха; пустые строки — пара ещё в первой сотне, и рисовать
  /// «0 дней» нельзя: это читается поломкой.
  final String previousTitle;
  final String previousSub;

  final String todayTitle;
  final String todaySub;

  final String nextTitle;
  final String nextSub;

  final String anniversaryTitle;
  final String anniversarySub;
}

String _milestoneTitle(Milestone m, AppStrings s) =>
    m.isAnniversary ? s.tgYearsMilestone(m.years) : s.tgDaysMilestone(m.days);

/// Подписи для [track]. [formatDate] отдаёт дату так, как её пишут на
/// остальных экранах — форматирование живёт снаружи, чтобы модель осталась
/// чистой и проверяемой.
TrackLabels trackLabels(
  MilestoneTrack track,
  AppStrings s,
  String Function(DateTime) formatDate,
) {
  final previous = track.previous;
  return TrackLabels(
    previousTitle: previous == null ? '' : _milestoneTitle(previous, s),
    previousSub: previous == null
        ? ''
        : s.tgMilestonePassed.replaceAll('{date}', formatDate(previous.date)),
    todayTitle: s.tgMilestoneToday
        .replaceAll('{days}', s.tgDaysMilestone(track.days)),
    todaySub: s.tgMilestoneShare
        .replaceAll('{percent}', '${track.percent}')
        .replaceAll('{target}', _milestoneTitle(track.next, s)),
    nextTitle: _milestoneTitle(track.next, s),
    nextSub: s.tgInDays(track.next.daysLeft),
    anniversaryTitle: s.tgYearsMilestone(track.anniversary.years),
    anniversarySub: formatDate(track.anniversary.date),
  );
}
