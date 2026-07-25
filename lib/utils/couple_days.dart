/// Единый расчёт срока отношений — «вместе N дней».
///
/// Дат две, и они почти всегда разные:
///  * `group.start_date` — момент КОННЕКТА (когда пара сошлась в приложении);
///  * дата системного таймера «Дней вместе» — настоящее начало отношений,
///    её пользователь правит руками.
///
/// Профили считали срок от даты коннекта, а главный экран — от таймера, и одна
/// пара видела «53 дня» в профиле против «73» на главной. Берём БОЛЕЕ РАННЮЮ из
/// двух: отношения не короче ни коннекта, ни выставленной годовщины. Та же
/// формула работает в достижениях (`AchievementService`).
library;

/// Настоящая дата начала отношений: более ранняя из даты таймера и даты
/// коннекта. null — обеих дат нет.
DateTime? coupleStartDate({DateTime? timerStart, DateTime? groupStart}) {
  if (timerStart != null && groupStart != null) {
    return timerStart.isBefore(groupStart) ? timerStart : groupStart;
  }
  return timerStart ?? groupStart;
}

/// Дней вместе на [now] (по умолчанию — сейчас). null — считать не от чего.
/// Дата в будущем даёт 0, а не отрицательное число.
int? coupleDaysTogether({
  DateTime? timerStart,
  DateTime? groupStart,
  DateTime? now,
}) {
  final start = coupleStartDate(timerStart: timerStart, groupStart: groupStart);
  if (start == null) return null;
  final days = (now ?? DateTime.now()).difference(start).inDays;
  return days < 0 ? 0 : days;
}
