// Экран достижений «Полки»: пять блоков по семьям вместо тридцати восьми строк.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/pair_achievement.dart';
import 'package:love_app/screens/achievements_screen.dart';
import 'package:love_app/services/achievement_service.dart';
import 'package:love_app/theme/app_theme.dart';
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

Future<void> _open(WidgetTester tester) async {
  AchievementService.instance.stats.value = _stats;
  await tester.pumpWidget(achievementApp(AchievementsScreen(theme: AppThemes.pink)));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() => useLanguage('ru'));

  testWidgets('сводка и первая полка на месте, фильтров нет', (tester) async {
    useScreen(tester, const Size(360, 760));
    await _open(tester);
    expect(find.text('11 / 38'), findsOneWidget);
    expect(find.text('Открыто 11 из 38'), findsOneWidget);
    expect(find.text('ВРЕМЯ ВМЕСТЕ'), findsOneWidget);
    expect(find.text('100 дней вместе'), findsOneWidget);
    expect(find.text('45 из 100'), findsOneWidget);
    expect(find.text('В процессе'), findsNothing);
  });

  testWidgets('полок пять, по одной на семью', (tester) async {
    useScreen(tester, const Size(360, 2400));
    await _open(tester);
    for (final title in ['ВРЕМЯ ВМЕСТЕ', 'ВОСПОМИНАНИЯ', 'ПЕРЕПИСКА', 'РИСУНКИ', 'СЕРИЯ ДНЕЙ']) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(find.byKey(const ValueKey('achievement-shelf')), findsNothing);
    expect(find.byType(AchievementShelf), findsNWidgets(5));
  });

  testWidgets('касание по полученному открывает его лист', (tester) async {
    useScreen(tester, const Size(360, 760));
    await _open(tester);
    await tester.tap(find.byWidgetPredicate(
      (w) => w is AchievementMedal && w.achievement.id == 'together_30',
    ));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(AchievementSheetBody), findsOneWidget);
    expect(find.text('Месяц вместе'), findsOneWidget);
    expect(find.text('ПОЛУЧЕНО'), findsOneWidget);
  });

  testWidgets('семья, собранная целиком, говорит об этом', (tester) async {
    useScreen(tester, const Size(360, 2400));
    AchievementService.instance.stats.value =
        const AchievementStats(drawings: 100);
    await tester.pumpWidget(achievementApp(AchievementsScreen(theme: AppThemes.pink)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Здесь всё получено'), findsOneWidget);
  });

  for (final lang in ['ru', 'de', 'fr']) {
    testWidgets('320 точек и шрифт 1.3 без переполнений ($lang)', (tester) async {
      await useLanguage(lang);
      addTearDown(() => useLanguage('ru'));
      useScreen(tester, const Size(320, 2600), textScale: 1.3);
      await _open(tester);
      expect(tester.takeException(), isNull, reason: lang);
    });
  }
}
