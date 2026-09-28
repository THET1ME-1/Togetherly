import 'dart:convert';

import 'timer_item.dart';

/// Виджет «До встречи»: что уходит на рабочий стол и как оттуда считается.
///
/// До 28.09.2026 приложение клало в виджет готовые «дни, часы, минуты», и
/// писал их только экран «Виджеты» в момент постановки. Числа застывали, и
/// человек снимал виджет и ставил заново, лишь бы они сдвинулись (обращение
/// 197). Теперь в виджет уезжают сами события с их моментом, а остаток
/// считает натив по своим часам — тем же правилом, что [countdownAt].
/// Kotlin (`CountdownWidgetProvider`) и Swift (`CountdownWidget`) повторяют
/// его, и расхождение стережёт `test/models/countdown_widget_test.dart`.

/// Сколько ближайших событий кладём в виджет. Прошло первое — натив берёт
/// следующее, не дожидаясь приложения.
const int kCountdownWidgetEvents = 8;

/// Одно событие обратного отсчёта.
class CountdownEvent {
  const CountdownEvent({
    required this.title,
    required this.atMs,
    required this.dateLabel,
  });

  final String title;

  /// Момент события, миллисекунды эпохи.
  final int atMs;

  /// Подпись даты на чипе («12 ОКТЯБРЯ»).
  final String dateLabel;

  Map<String, Object> toJson() => {'t': title, 'at': atMs, 'd': dateLabel};

  static CountdownEvent? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final at = raw['at'];
    if (at is! num) return null;
    return CountdownEvent(
      title: (raw['t'] ?? '').toString(),
      atMs: at.toInt(),
      dateLabel: (raw['d'] ?? '').toString(),
    );
  }
}

/// Ближайшие обратные отсчёты пары, от раннего к позднему.
List<CountdownEvent> countdownEventsFor(
  Iterable<TimerItem> timers, {
  required DateTime now,
  required String Function(DateTime) dateLabel,
  int limit = kCountdownWidgetEvents,
}) {
  final upcoming = timers
      .where((t) => t.isCountdown && t.startDate.isAfter(now))
      .toList()
    ..sort((a, b) => a.startDate.compareTo(b.startDate));
  return [
    for (final t in upcoming.take(limit))
      CountdownEvent(
        title: t.title,
        atMs: t.startDate.millisecondsSinceEpoch,
        dateLabel: dateLabel(t.startDate).toUpperCase(),
      ),
  ];
}

/// Строка для ключа `tgcd_<g>_events`.
String encodeCountdownEvents(List<CountdownEvent> events) =>
    jsonEncode([for (final e in events) e.toJson()]);

List<CountdownEvent> decodeCountdownEvents(String raw) {
  try {
    final list = jsonDecode(raw);
    if (list is! List) return const [];
    return [
      for (final r in list)
        if (CountdownEvent.fromJson(r) case final e?) e,
    ];
  } catch (_) {
    return const [];
  }
}

/// Что показывает виджет в момент [nowMs].
class CountdownTick {
  const CountdownTick({
    required this.event,
    required this.days,
    required this.hours,
    required this.minutes,
    required this.percent,
  });

  final CountdownEvent event;
  final int days;
  final int hours;
  final int minutes;

  /// Пройденная доля пути от [fromMs] до события, 0..100.
  final int percent;
}

/// Остаток до первого ещё не наступившего события. `null` — все прошли.
///
/// [fromMs] — начало полосы (дата пары); 0 — неизвестно, тогда полоса
/// считается от тридцати дней до события.
CountdownTick? countdownAt(
  List<CountdownEvent> events, {
  required int nowMs,
  int fromMs = 0,
}) {
  CountdownEvent? next;
  for (final e in events) {
    if (e.atMs > nowMs && (next == null || e.atMs < next.atMs)) next = e;
  }
  if (next == null) return null;
  final leftMin = (next.atMs - nowMs) ~/ 60000;
  const dayMin = 24 * 60;
  final from = fromMs > 0 && fromMs < next.atMs
      ? fromMs
      : next.atMs - 30 * dayMin * 60000;
  final start = from > nowMs ? nowMs : from;
  final total = next.atMs - start;
  final passed = nowMs - start;
  final percent =
      total <= 0 ? 100 : ((passed * 100) / total).round().clamp(0, 100);
  return CountdownTick(
    event: next,
    days: leftMin ~/ dayMin,
    hours: (leftMin % dayMin) ~/ 60,
    minutes: leftMin % 60,
    percent: percent,
  );
}
