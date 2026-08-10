// Немецкая раскладка на узком экране.
//
// Немецкий длиннее русского примерно на четверть, и первым это ломает не
// длинный абзац, а короткая подпись в жёстком месте: таб нижней навигации,
// таблетка фильтра, подпись размера виджета. Расчёт по числу символов тут не
// доказательство — нужен рендер.
//
// Тест делает две вещи. Во-первых, ловит переполнение: Flutter при обрезке
// RenderFlex бросает ошибку, и прогон падает сам. Во-вторых, снимает кадры,
// которые можно посмотреть глазами:
//
//     flutter test test/goldens/de_layout_test.dart --update-goldens
//
// Кадры лежат рядом в `goldens/de/`.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:love_app/models/pair_achievement.dart';
import 'package:love_app/screens/achievements_screen.dart';
import 'package:love_app/screens/home/home_bottom_nav.dart';
import 'package:love_app/services/achievement_service.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/theme/profile_theme.dart';

/// Самый узкий телефон, который мы поддерживаем: 360 dp.
const Size _narrow = Size(360, 800);

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  var any = false;
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) continue;
    loader.addFont(file.readAsBytes().then(ByteData.sublistView));
    any = true;
  }
  if (any) await loader.load();
}

Future<void> _shoot(
  WidgetTester tester, {
  required Widget child,
  required String name,
  Size size = _narrow,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(child);
  await tester.pump(const Duration(milliseconds: 600));
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('de/$name.png'),
  );
}

void main() {
  final theme = buildAppTheme(kPalettes[0], Brightness.light);

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({'app_language': 'de'});
    await LocaleService.instance.init();
    await LocaleService.instance.setLanguage(AppLanguage.de);
    await _loadFont('Onest', ['assets/fonts/Onest.ttf']);
    await _loadFont('Unbounded', ['assets/fonts/Unbounded.ttf']);
    await _loadFont('MaterialIcons', [
      '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);
    await _loadFont('Noto Color Emoji', [
      '/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf',
    ]);
  });

  test('язык теста действительно немецкий', () {
    expect(LocaleService.instance.language, AppLanguage.de);
    expect(LocaleService.current.achFilterInProgress, 'Läuft noch');
  });

  testWidgets('нижняя навигация: четыре подписи в один ряд', (tester) async {
    // «Verbindung» — самое длинное слово из четырёх, вдвое длиннее русской
    // «Связь». Если таб не выдержит, панель переполнится и тест упадёт.
    await _shoot(
      tester,
      name: 'bottom_nav',
      size: const Size(360, 200),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ProfileTheme.themeFor(theme),
        home: Scaffold(
          backgroundColor: ProfileTheme.schemeFor(theme).surface,
          body: Align(
            alignment: Alignment.bottomCenter,
            child: HomeBottomNav(
              selectedIndex: 0,
              theme: theme,
              isPaired: true,
              onTap: (_) {},
              onCreatePin: () {},
            ),
          ),
        ),
      ),
    );
  });

  testWidgets('французский: достижения без обрезки', (tester) async {
    await LocaleService.instance.setLanguage(AppLanguage.fr);
    addTearDown(() => LocaleService.instance.setLanguage(AppLanguage.de));
    AchievementService.instance.stats.value = const AchievementStats(
      daysTogether: 214,
      memories: 76,
      messages: 1840,
      drawings: 7,
      streakDays: 12,
    );
    await _shoot(
      tester,
      name: 'achievements_fr',
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: AchievementsScreen(theme: theme),
      ),
    );
  });

  testWidgets('испанский: достижения без обрезки', (tester) async {
    await LocaleService.instance.setLanguage(AppLanguage.es);
    addTearDown(() => LocaleService.instance.setLanguage(AppLanguage.de));
    AchievementService.instance.stats.value = const AchievementStats(
      daysTogether: 214,
      memories: 76,
      messages: 1840,
      drawings: 7,
      streakDays: 12,
    );
    await _shoot(
      tester,
      name: 'achievements_es',
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: AchievementsScreen(theme: theme),
      ),
    );
  });

  testWidgets('итальянский: достижения без обрезки', (tester) async {
    await LocaleService.instance.setLanguage(AppLanguage.it);
    addTearDown(() => LocaleService.instance.setLanguage(AppLanguage.de));
    AchievementService.instance.stats.value = const AchievementStats(
      daysTogether: 214,
      memories: 76,
      messages: 1840,
      drawings: 7,
      streakDays: 12,
    );
    await _shoot(
      tester,
      name: 'achievements_it',
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: AchievementsScreen(theme: theme),
      ),
    );
  });

  testWidgets('португальский: достижения без обрезки', (tester) async {
    await LocaleService.instance.setLanguage(AppLanguage.pt);
    addTearDown(() => LocaleService.instance.setLanguage(AppLanguage.de));
    AchievementService.instance.stats.value = const AchievementStats(
      daysTogether: 214,
      memories: 76,
      messages: 1840,
      drawings: 7,
      streakDays: 12,
    );
    await _shoot(
      tester,
      name: 'achievements_pt',
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: AchievementsScreen(theme: theme),
      ),
    );
  });

  testWidgets('достижения: фильтры-таблетки и подписи метрик', (tester) async {
    // Три фильтра делят строку поровну: «Alle», «Erhalten», «Läuft noch».
    AchievementService.instance.stats.value = const AchievementStats(
      daysTogether: 214,
      memories: 76,
      messages: 1840,
      drawings: 7,
      streakDays: 12,
    );
    await _shoot(
      tester,
      name: 'achievements',
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: AchievementsScreen(theme: theme),
      ),
    );
  });
}
