// Лист достижения — замена попапа по центру: рисунок, название, семья по
// порядку и ближайшая цель.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/pair_achievement.dart';
import 'package:love_app/widgets/achievements/achievement_medal.dart';
import 'package:love_app/widgets/achievements/achievement_sheet.dart';

import '../helpers/achievement_harness.dart';

const _stats = AchievementStats(
  daysTogether: 45,
  memories: 12,
  messages: 130,
  drawings: 6,
  streakDays: 7,
);

Widget _sheet(
  String id, {
  AchievementStats stats = _stats,
  bool fresh = true,
  int position = 1,
  int total = 1,
  VoidCallback? onSeeAll,
}) =>
    achievementApp(Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: AchievementSheetBody(
          achievement: PairAchievement.byId(id)!,
          stats: stats,
          fresh: fresh,
          position: position,
          total: total,
          onSeeAll: onSeeAll,
        ),
      ),
    ));

void main() {
  setUpAll(() => useLanguage('ru'));

  group('Окно лестницы', () {
    final days = PairAchievement.family(AchievementMetric.daysTogether);

    test('короткая семья показывается целиком', () {
      final streak = PairAchievement.family(AchievementMetric.streakDays);
      expect(ladderWindow(streak, streak.first), streak);
    });

    test('длинная семья режется до шести, текущее достижение внутри', () {
      for (final current in days) {
        final window = ladderWindow(days, current);
        expect(window.length, 6, reason: current.id);
        expect(window, contains(current), reason: current.id);
      }
    });

    test('окно идёт подряд, без пропусков', () {
      final window = ladderWindow(days, days[7]);
      final from = days.indexOf(window.first);
      expect(window, days.sublist(from, from + 6));
    });
  });

  testWidgets('название, описание и ближайшая цель семьи', (tester) async {
    await tester.pumpWidget(_sheet('streak_7'));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Неделя подряд'), findsOneWidget);
    expect(find.text('7 дней заходите оба'), findsOneWidget);
    expect(find.text('ДОСТИЖЕНИЕ ПОЛУЧЕНО!'), findsOneWidget);
    expect(find.text('Две недели подряд'), findsOneWidget);
    expect(find.text('7 из 14'), findsOneWidget);
    // Вся семья серии на лестнице: шесть фигур.
    expect(find.byType(AchievementMedal), findsNWidgets(6));
    expect(find.text('Отлично'), findsOneWidget);
  });

  testWidgets('открытое из списка подписано «Получено» и закрывается', (tester) async {
    await tester.pumpWidget(_sheet('streak_7', fresh: false));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('ПОЛУЧЕНО'), findsOneWidget);
    expect(find.text('Закрыть'), findsOneWidget);
  });

  testWidgets('несколько подряд: счётчик и кнопка «Дальше»', (tester) async {
    await tester.pumpWidget(_sheet('messages_100', position: 1, total: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('1 из 2'), findsOneWidget);
    expect(find.text('Дальше'), findsOneWidget);
    expect(find.text('Отлично'), findsNothing);
  });

  testWidgets('«Все достижения» есть только там, где его просили', (tester) async {
    await tester.pumpWidget(_sheet('streak_7'));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Все достижения'), findsNothing);

    var opened = 0;
    await tester.pumpWidget(_sheet('streak_7', onSeeAll: () => opened++));
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('Все достижения'));
    expect(opened, 1);
  });

  testWidgets('семья собрана целиком — вместо цели строка об этом', (tester) async {
    await tester.pumpWidget(_sheet(
      'streak_365',
      stats: const AchievementStats(streakDays: 400),
    ));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Здесь всё получено'), findsOneWidget);
  });

  for (final lang in ['ru', 'de']) {
    testWidgets('320 точек и шрифт 1.3 без переполнений ($lang)', (tester) async {
      await useLanguage(lang);
      addTearDown(() => useLanguage('ru'));
      useScreen(tester, const Size(320, 640), textScale: 1.3);
      for (final id in ['memories_250', 'messages_25', 'together_100', 'streak_365']) {
        await tester.pumpWidget(_sheet(
          id,
          stats: const AchievementStats(
            daysTogether: 120,
            memories: 260,
            messages: 30,
            streakDays: 365,
          ),
          position: 1,
          total: 3,
          onSeeAll: () {},
        ));
        await tester.pump(const Duration(seconds: 2));
        expect(tester.takeException(), isNull, reason: '$id, $lang');
      }
    });
  }
}
