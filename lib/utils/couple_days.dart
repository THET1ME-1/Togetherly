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

/// Настоящая дата начала отношений: самая ранняя из даты таймера, даты
/// коннекта и годовщины. null — ни одной даты нет.
DateTime? coupleStartDate({
  DateTime? timerStart,
  DateTime? groupStart,
  DateTime? anniversary,
}) {
  DateTime? earliest;
  for (final d in [timerStart, groupStart, anniversary]) {
    if (d == null) continue;
    if (earliest == null || d.isBefore(earliest)) earliest = d;
  }
  return earliest;
}

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
  final days = (now ?? DateTime.now()).difference(start).inDays;
  return days < 0 ? 0 : days;
}
