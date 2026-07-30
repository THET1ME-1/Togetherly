// Скриншоты для README рисуются здесь, а не снимаются с телефона.
//
// Так они не зависят от чужих данных на экране, не тащат чужие имена и аватары
// и обновляются одной командой после правки интерфейса:
//
//     flutter test test/goldens --update-goldens
//
// Готовые PNG лежат рядом в `goldens/`, коллаж для README собирает
// `tools/make_screenshots_collage.py`.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:love_app/models/pair_achievement.dart';
import 'package:love_app/screens/achievements_screen.dart';
import 'package:love_app/services/achievement_service.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_theme.dart';

/// Размер кадра — телефон 1080×2400 при плотности 3.
const Size _phone = Size(360, 800);

Future<void> _shoot(
  WidgetTester tester, {
  required Widget child,
  required String name,
}) async {
  tester.view.physicalSize = _phone * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: child,
  ));
  await tester.pump(const Duration(milliseconds: 600));
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('$name.png'));
}

/// Подшивает настоящие шрифты: без этого тестовый рендер пишет текст
/// прямоугольниками (Ahem), и скриншот выходит нечитаемым.
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

void main() {
  final theme = AppThemes.purple;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Экраны поднимают очередь загрузок и настройки — без подложки prefs
    // рендер падает на MissingPluginException.
    // Русский — как на скриншотах в README: остальные кадры там русские.
    SharedPreferences.setMockInitialValues({'app_language': 'ru'});
    await LocaleService.instance.init();
    await _loadFont('Onest', ['assets/fonts/Onest.ttf']);
    await _loadFont('Unbounded', ['assets/fonts/Unbounded.ttf']);
    // Иконки и эмодзи берём из системы: свои в проекте не лежат, а без них
    // галочки и медали остаются пустыми квадратами.
    await _loadFont('MaterialIcons', [
      '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);
    await _loadFont('Noto Color Emoji', [
      '/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf',
    ]);
  });

  testWidgets('достижения', (tester) async {
    // Живые числа: половина получена, у остальных виден прогресс.
    AchievementService.instance.stats.value = const AchievementStats(
      daysTogether: 214,
      memories: 76,
      messages: 1840,
      drawings: 7,
      streakDays: 12,
    );
    await _shoot(tester, child: AchievementsScreen(theme: theme), name: 'achievements');
  });

}
