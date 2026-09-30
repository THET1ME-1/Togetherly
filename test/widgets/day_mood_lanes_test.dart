// История настроения за день: каждая смена хранится, лист дня показывает обе
// дорожки, а календарь и статистика по-прежнему считают день одним
// настроением — последним.
//
// Просьба из отзыва в Play 14.08.2026: видеть, когда партнёр сменил
// настроение и на какое. До 30.09.2026 у большинства новая отметка стирала
// прежнюю: хранить все смены умел только выключенный по умолчанию режим.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/mood_entry.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/widgets/mood/day_mood_lanes.dart';

MoodEntry _e(String id, String mood, int h, int m, {int day = 29}) => MoodEntry(
      id: id,
      moodId: mood,
      imagePath: '',
      label: mood,
      timestamp: DateTime(2026, 9, day, h, m),
    );

void main() {
  setUp(() => LocaleService.instance.setLanguage(AppLanguage.ru));

  test('последняя за день: одна запись на день, новые дни сверху', () {
    final daily = MoodEntry.latestPerDay([
      _e('a', 'sad', 8, 40),
      _e('b', 'happy', 22, 48),
      _e('c', 'love', 13, 2),
      _e('d', 'kiss', 10, 0, day: 28),
    ]);
    expect(daily.map((e) => e.id), ['b', 'd']);
  });

  test('сегодняшняя отметка больше не стирает прежние, статистика по дням', () {
    final src = File('lib/services/mood_service.dart').readAsStringSync();
    final today = src.substring(src.indexOf('Future<void> setMoodForToday('),
        src.indexOf('Future<void> setMoodForDate('));
    expect(today, isNot(contains('_repo.delete')));
    expect(src, isNot(contains('_allowMultiplePerDay')));
    expect(src, contains('MoodEntry.latestPerDay(_myEntries)'));
    expect(src, contains('MoodEntry.latestPerDay(_partnerEntries[uid]'));

    final cal = File('lib/screens/mood_calendar_screen.dart').readAsStringSync();
    expect(cal, contains('_buildAnalytics(scheme, MoodEntry.latestPerDay(entries))'));
    expect(cal, contains('_showDayLanes(day, moods)'));
    expect(File('lib/screens/home/widgets/day_log_sheet.dart').readAsStringSync(),
        contains('DayMoodLanes('));
  });

  Future<void> pump(WidgetTester tester, List<MoodEntry> mine,
      List<MoodEntry> theirs,
      {Size size = const Size(390, 844), double scale = 1}) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = size * 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: DayMoodLanes(
              mine: mine,
              theirs: theirs,
              myName: 'Саша',
              partnerName: 'Аня',
            ),
          ),
        ),
      ),
    ));
  }

  final mine = [_e('a', 'sad', 8, 40), _e('c', 'laugh', 13, 2), _e('f', 'kiss', 22, 48)];
  final theirs = [_e('b', 'happy', 9, 15), _e('d', 'anxiety', 17, 30), _e('e', 'love', 19, 5)];

  testWidgets('отметки идут по времени: свои слева, партнёра справа',
      (tester) async {
    await pump(tester, mine, theirs);
    final times = ['08:40', '09:15', '13:02', '17:30', '19:05', '22:48'];
    final ys = [for (final t in times) tester.getCenter(find.text(t)).dy];
    expect(ys, orderedEquals([...ys]..sort()));

    final center = tester.getSize(find.byType(DayMoodLanes)).width / 2 + 16;
    Offset labelOf(MoodEntry e) =>
        tester.getCenter(find.text(e.localizedLabel).first);
    for (final e in mine) {
      expect(labelOf(e).dx, lessThan(center), reason: e.id);
    }
    for (final e in theirs) {
      expect(labelOf(e).dx, greaterThan(center), reason: e.id);
    }
  });

  testWidgets('без отметок блока нет', (tester) async {
    await pump(tester, const [], const []);
    expect(find.text('Саша'), findsNothing);
  });

  testWidgets('320 dp и шрифт 1.3 без переполнений', (tester) async {
    await pump(tester, mine, theirs, size: const Size(320, 640), scale: 1.3);
    expect(tester.takeException(), isNull);
  });
}
