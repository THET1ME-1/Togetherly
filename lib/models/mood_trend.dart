import 'mood_entry.dart';

/// Точка графика настроения: начало отрезка (день, неделя или месяц) и
/// среднее за него.
class MoodTrendPoint {
  const MoodTrendPoint(this.start, this.value, {DateTime? end, this.wholeMonth = false})
      : end = end ?? start;

  final DateTime start;
  final double value;

  /// Последний день отрезка: у дня совпадает с началом, у недели — воскресенье.
  final DateTime end;

  /// Точка — целый месяц: подписывается его названием.
  final bool wholeMonth;
}

/// Подпись точки при нажатии: «12–18 октября · 4,2». Раньше график показывал
/// одну цифру среднего, и не было понятно, к какой неделе она относится.
///
/// [monthsGen] — месяцы в родительном падеже, [monthsNom] — в именительном
/// (оба с пустым нулевым элементом, как `fullMonths`).
String moodTrendPointLabel(
  MoodTrendPoint p,
  List<String> monthsGen,
  List<String> monthsNom, {
  bool decimalComma = true,
}) {
  final value = p.value.toStringAsFixed(1);
  final number = decimalComma ? value.replaceAll('.', ',') : value;
  final String when;
  if (p.wholeMonth) {
    when = monthsNom[p.start.month];
  } else if (p.start == p.end) {
    when = '${p.start.day} ${monthsGen[p.start.month]}';
  } else if (p.start.month == p.end.month) {
    when = '${p.start.day}–${p.end.day} ${monthsGen[p.end.month]}';
  } else {
    when = '${p.start.day} ${monthsGen[p.start.month]} – ${p.end.day} ${monthsGen[p.end.month]}';
  }
  return '$when · $number';
}

/// Сколько недель график держит, дальше — месяцы. Полгода неделями — около
/// 26 точек: месяцами те же полгода сжимались в пять, и кривая выходила
/// плоской.
const int kMoodTrendMaxPoints = 26;

/// Кружки на точках — только пока их не больше 12: дальше они налезают друг
/// на друга, и читается одна линия.
bool moodTrendShowsDots(int points) => points <= 12;

/// Точки графика из средних по дням.
///
/// Каждый день отдельной точкой годится на неделю-две. За полгода выходило
/// 63 кружка, налезающих друг на друга (жалоба владельца 08.11.2026), поэтому
/// дальше дни складываются в недели (с понедельника), а недели, если их
/// больше [kMoodTrendMaxPoints], — в месяцы.
List<MoodTrendPoint> moodTrendPoints(Map<DateTime, double> days) {
  final sorted = days.keys.toList()..sort();
  if (sorted.length <= 14) {
    return [for (final d in sorted) MoodTrendPoint(d, days[d]!)];
  }
  final weeks = _group(
    days,
    sorted,
    (d) => DateTime(d.year, d.month, d.day - (d.weekday - 1)),
    (b) => DateTime(b.year, b.month, b.day + 6),
  );
  if (weeks.length <= kMoodTrendMaxPoints) return weeks;
  return _group(
    days,
    sorted,
    (d) => DateTime(d.year, d.month, 1),
    (b) => DateTime(b.year, b.month + 1, 0),
    wholeMonth: true,
  );
}

List<MoodTrendPoint> _group(
  Map<DateTime, double> days,
  List<DateTime> sorted,
  DateTime Function(DateTime) bucketOf,
  DateTime Function(DateTime) endOf, {
  bool wholeMonth = false,
}) {
  final sums = <DateTime, double>{};
  final counts = <DateTime, int>{};
  for (final d in sorted) {
    final b = bucketOf(d);
    sums[b] = (sums[b] ?? 0) + days[d]!;
    counts[b] = (counts[b] ?? 0) + 1;
  }
  return [
    for (final b in sums.keys)
      MoodTrendPoint(b, sums[b]! / counts[b]!, end: endOf(b), wholeMonth: wholeMonth),
  ];
}

/// Картинка каждого настроения — из последней отметки с ним.
///
/// В паках настроения называются одинаково (`laugh`, `love` и у стандартного,
/// и у котиков), и по названию картинка находилась из стандартного пака:
/// статистика показывала жёлтые смайлы, а в дне стоял котик (08.11.2026,
/// «на дне факт»).
Map<String, String> moodImagesOf(Iterable<MoodEntry> entries) {
  final latest = <String, MoodEntry>{};
  for (final e in entries) {
    if (e.imagePath.isEmpty) continue;
    final cur = latest[e.moodId];
    if (cur == null || e.timestamp.isAfter(cur.timestamp)) latest[e.moodId] = e;
  }
  return {for (final e in latest.entries) e.key: e.value.imagePath};
}
