// Кадры достижений для сверки с макетом (экран «Полки», лист, островок):
// flutter test test/goldens/achievements_preview.dart → build/achievements/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/pair_achievement.dart';
import 'package:love_app/screens/achievements_screen.dart';
import 'package:love_app/services/achievement_service.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/theme/theme_scope.dart';
import 'package:love_app/widgets/achievements/achievement_sheet.dart';
import 'package:love_app/widgets/achievements/achievement_unlock.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _stats = AchievementStats(
  daysTogether: 45,
  memories: 12,
  messages: 130,
  drawings: 6,
  streakDays: 7,
);

Future<void> _font(String family, String path) async {
  final loader = FontLoader(family)
    ..addFont(File(path).readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

/// Кадры из сборки грузятся настоящим вводом-выводом: даём ему пройти.
Future<void> _loadImages(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 400));
  }
}

Future<void> _shoot(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await boundary.toImage(pixelRatio: 2);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    Directory('build/achievements').createSync(recursive: true);
    File('build/achievements/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'app_language': 'ru'});
    await LocaleService.instance.init();
    await _font('Onest', 'assets/fonts/Onest.ttf');
    await _font('Unbounded', 'assets/fonts/Unbounded.ttf');
    await _font(
      'MaterialIcons',
      '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
  });
  tearDown(AchievementUnlock.debugReset);

  Widget app(AppTheme theme, GlobalKey key, Widget home) => RepaintBoundary(
        key: key,
        child: ThemeScope(
          theme: theme,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ProfileTheme.data(ProfileTheme.schemeFor(theme)),
            home: home,
          ),
        ),
      );

  void screen(WidgetTester tester, Size size, [double scale = 1]) {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = size * 2;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  for (final (name, palette, b) in [
    ('light', 0, Brightness.light),
    ('dark', 0, Brightness.dark),
    ('bordo-dark', 17, Brightness.dark),
  ]) {
    final theme = buildAppTheme(kPalettes[palette], b);

    testWidgets('полки $name', (tester) async {
      screen(tester, const Size(360, 1500));
      AchievementService.instance.stats.value = _stats;
      final key = GlobalKey();
      await tester.pumpWidget(app(theme, key, AchievementsScreen(theme: theme)));
      await _loadImages(tester);
      await _shoot(tester, key, 'shelves-$name');
    });

    testWidgets('лист $name', (tester) async {
      screen(tester, const Size(360, 760));
      final key = GlobalKey();
      await tester.pumpWidget(app(
        theme,
        key,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showAchievementSheet(
                  context,
                  PairAchievement.byId('streak_7')!,
                  stats: _stats,
                  fresh: true,
                  onSeeAll: () {},
                ),
                child: const Text('лист'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('лист'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(seconds: 2));
      await _loadImages(tester);
      await _shoot(tester, key, 'sheet-$name');
    });
  }

  testWidgets('лист 320 при шрифте 1.3, второе из трёх', (tester) async {
    screen(tester, const Size(320, 640), 1.3);
    final theme = buildAppTheme(kPalettes[0], Brightness.light);
    final key = GlobalKey();
    await tester.pumpWidget(app(
      theme,
      key,
      Scaffold(
        backgroundColor: ProfileTheme.schemeFor(theme).surfaceContainerHigh,
        body: Align(
          alignment: Alignment.bottomCenter,
          child: AchievementSheetBody(
            achievement: PairAchievement.byId('messages_25')!,
            stats: _stats,
            fresh: true,
            position: 2,
            total: 3,
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 2));
    await _loadImages(tester);
    await _shoot(tester, key, 'sheet-320-13');
  });

  testWidgets('островок', (tester) async {
    screen(tester, const Size(360, 300));
    final theme = buildAppTheme(kPalettes[0], Brightness.light);
    final key = GlobalKey();
    await tester.pumpWidget(app(
      theme,
      key,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => AchievementUnlock.show(
                context,
                PairAchievement.byId('messages_100')!,
                homeOnTop: () => false,
                stats: () => _stats,
              ),
              child: const Text('островок'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('островок'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    await _loadImages(tester);
    await _shoot(tester, key, 'island');
    await tester.pump(AchievementUnlock.islandStay);
    await tester.pump(const Duration(seconds: 1));
  });
}
