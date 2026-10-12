// Момент получения. На главной приходит нижний лист; на чужом экране (чат,
// рисование) лист оборвал бы дело, поэтому там островок на пять секунд.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/pair_achievement.dart';
import 'package:love_app/widgets/achievements/achievement_sheet.dart';
import 'package:love_app/widgets/achievements/achievement_unlock.dart';

import '../helpers/achievement_harness.dart';

const _stats = AchievementStats(messages: 130, streakDays: 7);

Widget _app({required bool homeOnTop, required List<String> ids, VoidCallback? onSeeAll}) =>
    achievementApp(Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () {
              for (final id in ids) {
                AchievementUnlock.show(
                  context,
                  PairAchievement.byId(id)!,
                  homeOnTop: () => homeOnTop,
                  stats: () => _stats,
                  onSeeAll: onSeeAll,
                );
              }
            },
            child: const Text('получить'),
          ),
        ),
      ),
    ));

/// Полторы секунды кадрами: хватает на сбор пачки, выезд листа и пружину
/// рисунка, и заведомо меньше времени, которое висит островок.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  setUpAll(() => useLanguage('ru'));
  tearDown(AchievementUnlock.debugReset);

  test('на главной лист, на чужом экране островок', () {
    expect(unlockSurfaceFor(homeOnTop: true), UnlockSurface.sheet);
    expect(unlockSurfaceFor(homeOnTop: false), UnlockSurface.island);
  });

  testWidgets('на главной достижение приходит листом', (tester) async {
    await tester.pumpWidget(_app(homeOnTop: true, ids: ['streak_7']));
    await tester.tap(find.text('получить'));
    await _settle(tester);
    expect(find.byType(AchievementSheetBody), findsOneWidget);
    expect(find.text('Неделя подряд'), findsOneWidget);
    expect(find.byKey(AchievementUnlock.islandKey), findsNothing);
  });

  testWidgets('на чужом экране приходит островок и сам уходит', (tester) async {
    await tester.pumpWidget(_app(homeOnTop: false, ids: ['streak_7']));
    await tester.tap(find.text('получить'));
    await _settle(tester);
    expect(find.byKey(AchievementUnlock.islandKey), findsOneWidget);
    expect(find.text('Неделя подряд'), findsOneWidget);
    expect(find.byType(AchievementSheetBody), findsNothing);

    await tester.pump(AchievementUnlock.islandStay);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(AchievementUnlock.islandKey), findsNothing);
  });

  testWidgets('касание по островку открывает лист', (tester) async {
    await tester.pumpWidget(_app(homeOnTop: false, ids: ['streak_7']));
    await tester.tap(find.text('получить'));
    await _settle(tester);
    await tester.tap(find.byKey(AchievementUnlock.islandKey));
    await _settle(tester);
    expect(find.byKey(AchievementUnlock.islandKey), findsNothing);
    expect(find.byType(AchievementSheetBody), findsOneWidget);
  });

  testWidgets('два сразу идут по очереди и считаются', (tester) async {
    await tester.pumpWidget(_app(homeOnTop: true, ids: ['messages_100', 'streak_7']));
    await tester.tap(find.text('получить'));
    await _settle(tester);
    expect(find.byType(AchievementSheetBody), findsOneWidget);
    expect(find.text('100 сообщений'), findsOneWidget);
    expect(find.text('1 из 2'), findsOneWidget);

    await tester.tap(find.text('Дальше'));
    await _settle(tester);
    expect(find.byType(AchievementSheetBody), findsOneWidget);
    expect(find.text('Неделя подряд'), findsOneWidget);
    expect(find.text('2 из 2'), findsOneWidget);

    await tester.tap(find.text('Отлично'));
    await _settle(tester);
    expect(find.byType(AchievementSheetBody), findsNothing);
  });

  test('попап по центру и конфетти удалены из приложения', () {
    expect(File('lib/widgets/achievement_unlock_overlay.dart').existsSync(), isFalse);
    final home = File('lib/screens/home_screen.dart').readAsStringSync();
    expect(home.contains('AchievementUnlockOverlay'), isFalse);
    expect(home.contains('AchievementUnlock.show('), isTrue);
  });
}
