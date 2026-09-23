/// Единый расчёт срока отношений — «вместе N дней».
///
/// Дат три, и они почти всегда разные:
///  * `group.start_date` — момент КОННЕКТА (когда пара сошлась в приложении);
///  * дата системного таймера «Дней вместе» — начало отношений, её человек
///    правит колесом на главной;
///  * годовщина из профиля — та самая «дата знакомства», которую люди вводят
///    первой, потому что поле лежит на виду.
///
/// Профили считали срок от даты коннекта, а главный экран — от таймера, и одна
/// пара видела «53 дня» в профиле против «73» на главной. Годовщину не считал
/// никто: пара, сошедшаяся в приложении вчера, видела «0 дней» при годовщине
/// годовой давности (жалоба @qwinken, 24.08.2026). Берём САМУЮ РАННЮЮ из трёх:
/// отношения не короче ни коннекта, ни таймера, ни годовщины. Та же формула
/// работает в достижениях (`AchievementService`).
library;

/// Настоящая дата начала отношений.
///
/// Порядок такой:
///  1. человек правил системный таймер — берём более раннюю из его даты и даты
///     коннекта, годовщина в расчёт не идёт: свой срок он уже выставил;
///  2. таймер стоит нетронутым — пустоту закрывает годовщина, если она раньше.
///
/// «Правил» видно по дню: у нетронутого таймера дата равна дню коннекта, её
/// ставит само приложение при создании пары. На проде так у 13 377 пар, ещё
/// 29 962 отодвинули таймер назад и 452 — вперёд. Годовщину вводят 15 903, и у
/// 3 370 из них таймер как раз нетронут — это и есть «вместе 0 дней» при
/// годовщине годовой давности. Слепая «самая ранняя из трёх» отняла бы
/// выставленный срок у 1 605 пар, где годовщина стоит раньше правленого
/// таймера.
///
/// null — ни одной даты нет.
DateTime? coupleStartDate({
  DateTime? timerStart,
  DateTime? groupStart,
  DateTime? anniversary,
}) {
  final edited = timerStart != null &&
      (groupStart == null || !_sameDay(timerStart, groupStart));
  final dates = edited
      ? [timerStart, groupStart]
      : [timerStart, groupStart, anniversary];
  DateTime? earliest;
  for (final d in dates) {
    if (d == null) continue;
    if (earliest == null || d.isBefore(earliest)) earliest = d;
  }
  return earliest;
}

/// Сколько клеток календаря от дня [from] до дня [to]; час обоих отброшен.
///
/// Так считает главный экран (`TimerItem.daysElapsed`), кольцо года и натив
/// виджетов (`YearMath.kt`, `daysSince` в Swift). Полные сутки от часа начала
/// (`difference().inDays`) ночью давали на день меньше: пара, начавшая в три
/// часа дня, до трёх часов видела вчерашнее число. Часы делятся на 24 с
/// округлением, потому что сутки перевода на летнее время короче или длиннее
/// 24 часов, и деление нацело съедало бы день.
int calendarDaysBetween(DateTime from, DateTime to) {
  final a = DateTime(from.year, from.month, from.day);
  final b = DateTime(to.year, to.month, to.day);
  return (b.difference(a).inHours / 24).round();
}

/// Предлагать ли вести «Дни вместе» от только что введённой годовщины.
///
/// Раньше предлагали только перенос НАЗАД: годовщина раньше даты таймера.
/// Живой случай 23.09.2026: годовщину ввели с годом 2003, согласились вести
/// счёт от неё, таймер ушёл на 17.07.2003. Год исправили на 2026, а
/// предложения не было, и счётчик застрял на 8467 днях. Таймер после такого
/// согласия ещё и считается правленым, поэтому [coupleStartDate] годовщину уже
/// не слушает.
///
/// Правило:
///  * годовщина в будущем или на том же дне, что таймер, — не предлагаем;
///  * годовщина раньше таймера — предлагаем, как и прежде;
///  * позже таймера — только если таймер стоит ровно на [previousAnniversary]:
///    туда его поставило это же предложение, и исправление годовщины должно
///    его сдвинуть. Таймер, выставленный отдельно, вперёд не трогаем.
///
/// Дни сравниваются без часов: в таймере бывает время, в годовщине нет.
bool shouldOfferCounterFromAnniversary({
  required DateTime anniversary,
  required DateTime timerStart,
  DateTime? previousAnniversary,
  DateTime? now,
}) {
  final a = _dayOf(anniversary);
  final today = _dayOf(now ?? DateTime.now());
  if (a.isAfter(today)) return false;
  final t = _dayOf(timerStart);
  if (a == t) return false;
  if (a.isBefore(t)) return true;
  return previousAnniversary != null && _sameDay(previousAnniversary, t);
}

DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// Один ли это календарный день. Час создания пары и час в таймере разные —
/// сравнивать надо дни.
bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Дней вместе на [now] (по умолчанию — сейчас). null — считать не от чего.
/// Дата в будущем даёт 0, а не отрицательное число.
int? coupleDaysTogether({
  DateTime? timerStart,
  DateTime? groupStart,
  DateTime? anniversary,
  DateTime? now,
}) {
  final start = coupleStartDate(
    timerStart: timerStart,
    groupStart: groupStart,
    anniversary: anniversary,
  );
  if (start == null) return null;
  final days = calendarDaysBetween(start, now ?? DateTime.now());
  return days < 0 ? 0 : days;
}

/// Дата, от которой считает виджет «Дней вместе».
///
/// Пользовательский таймер («до встречи», «до отпуска») виджет показывает как
/// есть — его выбрали осознанно. Во всех остальных случаях дата берётся общим
/// правилом [coupleStartDate], тем же, что на главной, в профиле и на экране
/// виджетов.
///
/// Пока этого правила здесь не было, виджет при незагруженных таймерах падал
/// на дату коннекта: пара с годовщиной 17 февраля видела на рабочем столе
/// «9 дней» и 22 августа, а в приложении 196 дней и 17 февраля (жалоба
/// 01.09.2026 — «это не наша дата, и такое уже второй раз»). Дата коннекта
/// вообще не должна показываться одна: она значит лишь день, когда пара
/// сошлась в приложении.
DateTime? widgetDaysStart({
  DateTime? customTimerStart,
  DateTime? systemTimerStart,
  DateTime? groupStart,
  DateTime? anniversary,
}) {
  if (customTimerStart != null) return customTimerStart;
  return coupleStartDate(
    timerStart: systemTimerStart,
    groupStart: groupStart,
    anniversary: anniversary,
  );
}
