// Фигура достижения: уровень читается формой M3, внутри рисунок у полученного
// и число-цель у неполученного. Металлических цветов и эмодзи больше нет.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/pair_achievement.dart';
import 'package:love_app/widgets/achievements/achievement_art.dart';
import 'package:love_app/widgets/achievements/achievement_medal.dart';

import '../helpers/achievement_harness.dart';

void main() {
  setUpAll(() => useLanguage('ru'));

  test('у каждого уровня своя форма', () {
    final shapes = AchievementTier.values.map(achievementShape).toSet();
    expect(shapes.length, AchievementTier.values.length);
  });

  test('число-цель помещается в фигуру: тысячи сокращаются', () {
    expect(medalNumber(7), '7');
    expect(medalNumber(1825), '1825');
    expect(medalNumber(10000), '10K');
    expect(medalNumber(50000), '50K');
  });

  testWidgets('полученное показывает рисунок, а не число', (tester) async {
    final a = PairAchievement.byId('streak_14')!;
    await tester.pumpWidget(achievementApp(
      Scaffold(body: AchievementMedal(achievement: a, earned: true, size: 64)),
    ));
    expect(find.byType(AchievementArt), findsOneWidget);
    expect(find.text('14'), findsNothing);
  });

  testWidgets('неполученное показывает число-цель без рисунка', (tester) async {
    final a = PairAchievement.byId('streak_14')!;
    await tester.pumpWidget(achievementApp(
      Scaffold(body: AchievementMedal(achievement: a, earned: false, size: 64)),
    ));
    expect(find.byType(AchievementArt), findsNothing);
    expect(find.text('14'), findsOneWidget);
  });

  testWidgets('касание доходит только до полученного', (tester) async {
    final a = PairAchievement.byId('streak_7')!;
    var taps = 0;
    for (final earned in [false, true]) {
      await tester.pumpWidget(achievementApp(Scaffold(
        body: Center(
          child: AchievementMedal(
            achievement: a,
            earned: earned,
            size: 64,
            onTap: () => taps++,
          ),
        ),
      )));
      await tester.tap(find.byType(AchievementMedal));
    }
    expect(taps, 1);
  });
}
