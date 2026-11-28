import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/settings/evening_reminder_block.dart';
import 'package:love_app/widgets/settings_scaffold.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Блок «Вечернее напоминание» на глаз (TOG-113). В общий прогон не входит:
/// `flutter test test/goldens/evening_reminder_preview.dart`, снимки в
/// `build/evening/`.
Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  var any = false;
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) continue;
    loader.addFont(Future.value(file.readAsBytesSync().buffer.asByteData()));
    any = true;
  }
  if (any) await loader.load();
}

void main() {
  setUpAll(() async {
    await _loadFont('Onest', ['assets/fonts/Onest.ttf']);
    await _loadFont('Unbounded', ['assets/fonts/Unbounded.ttf']);
    await _loadFont('MaterialIcons', [
      '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache'
          '/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);
  });

  testWidgets('вечернее напоминание', (tester) async {
    // Без подмены prefs выбор языка ждёт настоящий канал и тест виснет.
    SharedPreferences.setMockInitialValues({});
    await LocaleService.instance.setLanguage(AppLanguage.ru);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<void> shot(String name, int palette, Brightness b, Map<String, Object> prefs,
        {double width = 360, double scale = 1, bool paired = true}) async {
      SharedPreferences.setMockInitialValues(prefs);
      await tester.binding.setSurfaceSize(Size(width, 560));
      final cs = ProfileTheme.schemeFor(buildAppTheme(kPalettes[palette], b));
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ProfileTheme.data(cs),
        home: RepaintBoundary(
          key: key,
          child: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 560),
              textScaler: TextScaler.linear(scale),
              alwaysUse24HourFormat: true,
            ),
            child: Scaffold(
              backgroundColor: cs.surfaceContainer,
              body: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  // Последняя строка листа уведомлений над блоком — как в профиле.
                  SettingsGroup([
                    SettingsRow(
                      icon: Icons.calendar_month_rounded,
                      title: 'Дни вместе',
                      subtitle: 'Счётчик в шторке уведомлений',
                      trailing: Switch(value: true, onChanged: (_) {}),
                    ),
                  ]),
                  EveningReminderBlock(
                    moodHabit: true,
                    taskHabit: false,
                    paired: paired,
                    uid: 'me',
                    loadServer: () async => null,
                    onSave: ({mood, task, at}) async {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ));
      // Строки групп въезжают анимацией (`AppearOnScroll`): ей нужны кадры.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final dir = Directory('build/evening')..createSync(recursive: true);
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    // Первый показ: привычка к настроению есть, к заданиям нет.
    await shot('1_first_show', 0, Brightness.light, {});
    await shot('2_dark', 0, Brightness.dark, {
      'flutter.remind_mood_mode': 'on',
      'flutter.remind_task_mode': 'off',
      'flutter.remind_at': '22:30',
    });
    await shot('3_off', 7, Brightness.light, {
      'flutter.remind_mood_mode': 'off',
      'flutter.remind_task_mode': 'off',
    });
    await shot('4_narrow', 12, Brightness.dark, {}, width: 320, scale: 1.3);
    await shot('5_solo', 3, Brightness.light, {}, paired: false);
  });
}
