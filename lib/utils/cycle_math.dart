/// Арифметика менструального цикла.
///
/// Считается по собственным отметкам, а не по «средним 28 дням»: норма — от 21
/// до 35, и человеку с циклом в 33 дня стандартный календарь врёт каждый месяц.
/// Чем больше отмеченных циклов, тем точнее прогноз.
///
/// Овуляция отсчитывается от КОНЦА цикла: лютеиновая фаза (от овуляции до
/// месячных) держится в пределах 10–16 дней, обычно 14, а фолликулярная гуляет
/// сильно. Поэтому «следующие месячные минус 14» надёжнее, чем «начало плюс
/// половина цикла».
///
/// Это календарный метод. Он не заменяет ни врача, ни тесты на овуляцию, и при
/// нерегулярном цикле ошибается — такие прогнозы помечаются [CycleForecast.irregular].
library;

/// Чем помечен конкретный день в календаре.
enum CyclePhase {
  /// Отмечено вручную: месячные идут.
  period,

  /// Ожидаемые месячные по прогнозу.
  predictedPeriod,

  /// Фертильное окно вокруг овуляции.
  fertile,

  /// Расчётный день овуляции.
  ovulation,

  /// Обычный день.
  none,
}

/// Прогноз на ближайший цикл.
class CycleForecast {
  const CycleForecast({
    required this.nextPeriod,
    required this.ovulation,
    required this.fertileFrom,
    required this.fertileTo,
    required this.cycleLength,
    required this.irregular,
    required this.overdueDays,
  });

  /// Ожидаемое начало следующих месячных.
  final DateTime nextPeriod;

  /// Расчётный день овуляции.
  final DateTime ovulation;

  /// Границы фертильного окна включительно.
  final DateTime fertileFrom;
  final DateTime fertileTo;

  /// Средняя длина цикла, по которой построен прогноз.
  final int cycleLength;

  /// Разброс длин слишком велик — прогнозу верить нельзя.
  final bool irregular;

  /// На сколько дней задержка относительно прошлого ожидания. 0 — нет.
  final int overdueDays;
}

class CycleMath {
  const CycleMath._();

  /// Длина лютеиновой фазы: от овуляции до следующих месячных.
  static const int lutealPhaseDays = 14;

  /// Сколько дней до овуляции живут сперматозоиды — начало фертильного окна.
  static const int fertileBefore = 5;

  /// Сколько дней после овуляции ещё возможно зачатие.
  static const int fertileAfter = 1;

  /// По скольким последним циклам считаем средние. Старые данные не берём:
  /// цикл меняется с возрастом, нагрузкой, здоровьем.
  static const int windowCycles = 6;

  /// Границы правдоподобной длины цикла. Промежуток вне их — не цикл, а
  /// пропущенная отметка, и в среднее он попадать не должен.
  static const int minPlausible = 21;
  static const int maxPlausible = 45;

  /// Разброс длин, после которого прогноз считается ненадёжным.
  static const int irregularSpread = 8;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Первые дни каждых месячных: отметки, идущие подряд, — один цикл.
  static List<DateTime> starts(List<DateTime> marks) {
    if (marks.isEmpty) return const [];
    final days = marks.map(_day).toSet().toList()..sort();

    final result = <DateTime>[days.first];
    for (var i = 1; i < days.length; i++) {
      final gap = days[i].difference(days[i - 1]).inDays;
      if (gap > 1) result.add(days[i]);
    }
    return result;
  }

  /// Средняя длина цикла в днях. null — циклов меньше двух.
  static int? averageCycleLength(List<DateTime> marks) {
    final gaps = _plausibleGaps(marks);
    if (gaps.isEmpty) return null;
    final sum = gaps.reduce((a, b) => a + b);
    return (sum / gaps.length).round();
  }

  /// Средняя длительность самих месячных в днях. null — отметок нет.
  static int? averagePeriodLength(List<DateTime> marks) {
    if (marks.isEmpty) return null;
    final days = marks.map(_day).toSet().toList()..sort();

    final lengths = <int>[];
    var run = 1;
    for (var i = 1; i < days.length; i++) {
      if (days[i].difference(days[i - 1]).inDays == 1) {
        run++;
      } else {
        lengths.add(run);
        run = 1;
      }
    }
    lengths.add(run);

    final window = lengths.length > windowCycles
        ? lengths.sublist(lengths.length - windowCycles)
        : lengths;
    final sum = window.reduce((a, b) => a + b);
    return (sum / window.length).round();
  }

  /// Промежутки между началами циклов — только правдоподобные и только
  /// последние [windowCycles].
  static List<int> _plausibleGaps(List<DateTime> marks) {
    final s = starts(marks);
    if (s.length < 2) return const [];

    final gaps = <int>[];
    for (var i = 1; i < s.length; i++) {
      final gap = s[i].difference(s[i - 1]).inDays;
      if (gap >= minPlausible && gap <= maxPlausible) gaps.add(gap);
    }
    if (gaps.isEmpty) return const [];
    return gaps.length > windowCycles
        ? gaps.sublist(gaps.length - windowCycles)
        : gaps;
  }

  /// Прогноз на ближайший цикл. null — данных мало (меньше двух циклов).
  static CycleForecast? predict(List<DateTime> marks, {DateTime? today}) {
    final length = averageCycleLength(marks);
    if (length == null) return null;

    final now = _day(today ?? DateTime.now());
    final lastStart = starts(marks).last;

    // Ожидаемая дата могла уже пройти: человек не отметил новые месячные или
    // они задерживаются. Сдвигаем вперёд целыми циклами, но помним задержку —
    // её честнее показать, чем молча нарисовать дату в прошлом.
    var next = lastStart.add(Duration(days: length));
    var overdue = 0;
    if (!next.isAfter(now)) {
      overdue = now.difference(next).inDays;
      while (!next.isAfter(now)) {
        next = next.add(Duration(days: length));
      }
    }

    final ovulation = next.subtract(const Duration(days: lutealPhaseDays));
    final gaps = _plausibleGaps(marks);
    final spread = gaps.isEmpty
        ? 0
        : gaps.reduce((a, b) => a > b ? a : b) -
            gaps.reduce((a, b) => a < b ? a : b);

    return CycleForecast(
      nextPeriod: next,
      ovulation: ovulation,
      fertileFrom: ovulation.subtract(const Duration(days: fertileBefore)),
      fertileTo: ovulation.add(const Duration(days: fertileAfter)),
      cycleLength: length,
      irregular: spread >= irregularSpread,
      overdueDays: overdue,
    );
  }

  /// Какой сегодня день цикла, считая от последнего начала. null — отметок нет.
  static int? dayOfCycle(List<DateTime> marks, {DateTime? today}) {
    final s = starts(marks);
    if (s.isEmpty) return null;
    final now = _day(today ?? DateTime.now());
    final last = s.lastWhere((d) => !d.isAfter(now), orElse: () => s.first);
    return now.difference(last).inDays + 1;
  }

  /// Чем помечен день [date] — для раскраски календаря.
  static CyclePhase phaseOn(
    List<DateTime> marks,
    DateTime date, {
    DateTime? today,
    int? periodLength,
  }) {
    final day = _day(date);
    if (marks.map(_day).contains(day)) return CyclePhase.period;

    final forecast = predict(marks, today: today);
    if (forecast == null) return CyclePhase.none;

    if (day == forecast.ovulation) return CyclePhase.ovulation;
    if (!day.isBefore(forecast.fertileFrom) &&
        !day.isAfter(forecast.fertileTo)) {
      return CyclePhase.fertile;
    }

    // Ожидаемые месячные растягиваем на их обычную длительность.
    final len = periodLength ?? averagePeriodLength(marks) ?? 5;
    final predictedEnd =
        forecast.nextPeriod.add(Duration(days: len - 1));
    if (!day.isBefore(forecast.nextPeriod) && !day.isAfter(predictedEnd)) {
      return CyclePhase.predictedPeriod;
    }

    return CyclePhase.none;
  }
}
