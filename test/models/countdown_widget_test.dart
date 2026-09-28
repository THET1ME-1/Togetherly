import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/countdown_widget.dart';
import 'package:love_app/models/timer_item.dart';

void main() {
  final now = DateTime(2026, 9, 28, 12, 0);
  String label(DateTime d) => '${d.day}.${d.month}';

  TimerItem timer(String id, DateTime at, {bool countdown = true}) =>
      TimerItem(id: id, title: id, startDate: at, isCountdown: countdown);

  test('берём только будущие обратные отсчёты, от раннего к позднему', () {
    final events = countdownEventsFor(
      [
        timer('позже', DateTime(2026, 12, 1)),
        timer('прошло', DateTime(2026, 9, 1)),
        timer('счёт вперёд', DateTime(2026, 10, 1), countdown: false),
        timer('раньше', DateTime(2026, 10, 5)),
      ],
      now: now,
      dateLabel: label,
    );
    expect(events.map((e) => e.title), ['раньше', 'позже']);
    expect(events.first.dateLabel, '5.10');
  });

  test('список переживает круг через строку', () {
    final events = [
      CountdownEvent(title: 'Встреча «у моря»', atMs: 1790000000000, dateLabel: '1 ОКТ'),
    ];
    final back = decodeCountdownEvents(encodeCountdownEvents(events));
    expect(back.single.title, 'Встреча «у моря»');
    expect(back.single.atMs, 1790000000000);
    expect(decodeCountdownEvents('мусор'), isEmpty);
  });

  test('остаток считается от часов в момент показа, а не от записи', () {
    final at = DateTime(2026, 10, 1, 15, 30);
    final events = [
      CountdownEvent(title: 'x', atMs: at.millisecondsSinceEpoch, dateLabel: ''),
    ];
    final a = countdownAt(events, nowMs: now.millisecondsSinceEpoch)!;
    expect([a.days, a.hours, a.minutes], [3, 3, 30]);
    // Через сутки и 10 минут тот же список даёт другие числа — ровно этого
    // не хватало, пока числа приходили готовыми.
    final later = now.add(const Duration(days: 1, minutes: 10));
    final b = countdownAt(events, nowMs: later.millisecondsSinceEpoch)!;
    expect([b.days, b.hours, b.minutes], [2, 3, 20]);
  });

  test('первое событие прошло — показываем следующее, все прошли — пусто', () {
    final events = [
      CountdownEvent(title: 'первое', atMs: DateTime(2026, 9, 28, 13).millisecondsSinceEpoch, dateLabel: ''),
      CountdownEvent(title: 'второе', atMs: DateTime(2026, 10, 3).millisecondsSinceEpoch, dateLabel: ''),
    ];
    final after = DateTime(2026, 9, 29).millisecondsSinceEpoch;
    expect(countdownAt(events, nowMs: after)!.event.title, 'второе');
    expect(countdownAt(events, nowMs: DateTime(2026, 11, 1).millisecondsSinceEpoch), isNull);
  });

  test('полоса растёт к событию и не выходит из 0..100', () {
    final from = DateTime(2026, 9, 18).millisecondsSinceEpoch;
    final at = DateTime(2026, 10, 8).millisecondsSinceEpoch;
    final events = [CountdownEvent(title: 'x', atMs: at, dateLabel: '')];
    expect(countdownAt(events, nowMs: now.millisecondsSinceEpoch, fromMs: from)!.percent, 53);
    // Дата пары позже «сейчас» или не задана — полоса всё равно осмысленна.
    final noFrom = countdownAt(events, nowMs: now.millisecondsSinceEpoch)!;
    expect(noFrom.percent, inInclusiveRange(0, 100));
  });

  test('натив считает остаток сам и знает ключ списка событий', () {
    final kt = File('android/app/src/main/kotlin/com/togetherly/love/CountdownWidgetProvider.kt')
        .readAsStringSync();
    final swift = File('ios/TogetherlyWidget/CountdownWidget.swift').readAsStringSync();
    for (final src in [kt, swift]) {
      expect(src, contains('events'), reason: 'список событий не читается');
      expect(src, contains('from_ms'), reason: 'начало полосы не читается');
    }
    final dart = File('lib/services/home_widget_service.dart').readAsStringSync();
    expect(dart, contains(r"'tgcd_${g}_events'"));
    expect(dart, contains(r"'tgcd_${g}_from_ms'"));
  });

  test('данные «До встречи» пишет главная, а не только экран виджетов', () {
    final sync = File('lib/services/catalog_widget_sync.dart').readAsStringSync();
    expect(sync, contains('syncCountdownEvents('));
    final home = File('lib/screens/home_screen.dart').readAsStringSync();
    expect(home, contains('timers: _timerService.timers,\n      theme: _t,'));
  });
}
