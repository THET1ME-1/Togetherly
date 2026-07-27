/// Разметка совместного времени для виджетов «Кольцо года» и «Календарь лет».
///
/// Оба виджета показывают одно и то же событие с разных сторон: кольцо — долю
/// текущего года, сетка — прожитые месяцы. Считается это в одном месте, потому
/// что расхождение видно сразу: кольцо почти замкнулось, а последняя точка
/// сетки ещё не загорелась.
///
/// Границы лет и месяцев календарные, не «каждые 365 дней»: пара празднует
/// годовщину в свою дату, а не через фиксированное число суток.
class YearProgress {
  const YearProgress({
    required this.daysTotal,
    required this.yearsCompleted,
    required this.monthsCompleted,
    required this.daysIntoYear,
    required this.daysToNextAnniversary,
    required this.nextAnniversary,
  });

  /// Дней вместе всего.
  final int daysTotal;

  /// Полных лет: столько раз наступала годовщина.
  final int yearsCompleted;

  /// Полных месяцев — столько точек в сетке залито как прожитые.
  final int monthsCompleted;

  /// Дней с последней годовщины — числитель доли кольца.
  final int daysIntoYear;

  /// Дней до следующей годовщины.
  final int daysToNextAnniversary;

  /// Дата следующей годовщины.
  final DateTime nextAnniversary;

  /// Доля текущего года, 0…1. Знаменатель — 365 по хендофу: на високосном
  /// году иначе получается скачок прогресса назад в конце февраля.
  double get ringProgress => (daysIntoYear % 365) / 365;

  /// Считает разметку от даты начала [start] на момент [now].
  ///
  /// Время суток отбрасывается: виджет живёт днями, и пара, начавшая вечером,
  /// не должна видеть на день меньше, чем начавшая утром того же дня.
  factory YearProgress.between(DateTime start, DateTime now) {
    final from = DateTime(start.year, start.month, start.day);
    final to = DateTime(now.year, now.month, now.day);

    final daysTotal = to.difference(from).inDays;

    // Годовщина в этом году: 29 февраля в невисокосном году DateTime сдвигает
    // на 1 марта сам — пара отмечает годовщину в первый же существующий день.
    var years = to.year - from.year;
    if (_dateOf(from, to.year).isAfter(to)) years -= 1;
    if (years < 0) years = 0;

    final lastAnniversary = _dateOf(from, from.year + years);
    final nextAnniversary = _dateOf(from, from.year + years + 1);

    // Полные календарные месяцы. День короче исходного (31 января → 28
    // февраля) месяц не засчитывает: точка сетки загорится 1 марта.
    var months = (to.year - from.year) * 12 + (to.month - from.month);
    if (to.day < from.day) months -= 1;

    return YearProgress(
      daysTotal: daysTotal < 0 ? 0 : daysTotal,
      yearsCompleted: years,
      monthsCompleted: months < 0 ? 0 : months,
      daysIntoYear: to.difference(lastAnniversary).inDays,
      daysToNextAnniversary: nextAnniversary.difference(to).inDays,
      nextAnniversary: nextAnniversary,
    );
  }

  /// Та же дата в другом году. Февральский день, которого в году нет,
  /// DateTime переносит на следующий существующий.
  static DateTime _dateOf(DateTime source, int year) =>
      DateTime(year, source.month, source.day);
}
