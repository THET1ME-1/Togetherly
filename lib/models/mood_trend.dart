import 'mood_entry.dart';

/// Точка графика настроения: начало отрезка (день, неделя или месяц) и
/// среднее за него.
class MoodTrendPoint {
  const MoodTrendPoint(this.start, this.value);

  final DateTime start;
  final double value;
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
  final weeks = _group(days, sorted, (d) => DateTime(d.year, d.month, d.day - (d.weekday - 1)));
  if (weeks.length <= kMoodTrendMaxPoints) return weeks;
  return _group(days, sorted, (d) => DateTime(d.year, d.month, 1));
}

List<MoodTrendPoint> _group(Map<DateTime, double> days, List<DateTime> sorted, DateTime Function(DateTime) bucketOf) {
  final sums = <DateTime, double>{};
  final counts = <DateTime, int>{};
  for (final d in sorted) {
    final b = bucketOf(d);
    sums[b] = (sums[b] ?? 0) + days[d]!;
    counts[b] = (counts[b] ?? 0) + 1;
  }
  return [for (final b in sums.keys) MoodTrendPoint(b, sums[b]! / counts[b]!)];
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
