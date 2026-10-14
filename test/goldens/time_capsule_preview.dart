// Снимки экрана «Капсула времени» из настоящего кода:
// flutter test test/goldens/time_capsule_preview.dart → build/time-capsule/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/screens/time_capsule_screen.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _font(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return;
  final loader = FontLoader(family)
    ..addFont(file.readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'app_language': 'ru'});
    await LocaleService.instance.init();
    await _font('Onest', 'assets/fonts/Onest.ttf');
    await _font('Unbounded', 'assets/fonts/Unbounded.ttf');
    await _font('MaterialIcons',
        '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  });

  for (final (name, palette, b, width, scale, lang, filled) in [
    ('coffee-light-360-empty', 21, Brightness.light, 360.0, 1.0, AppLanguage.ru, false),
    ('coffee-light-360-filled', 21, Brightness.light, 360.0, 1.0, AppLanguage.ru, true),
    ('coffee-dark-360-filled', 21, Brightness.dark, 360.0, 1.0, AppLanguage.ru, true),
    ('pink-light-360-filled', 0, Brightness.light, 360.0, 1.0, AppLanguage.ru, true),
    ('pink-dark-320-1.3-de', 0, Brightness.dark, 320.0, 1.3, AppLanguage.de, false),
  ]) {
    testWidgets(name, (tester) async {
      LocaleService.instance.setLanguage(lang);
      final theme = buildAppTheme(kPalettes[palette], b);
      const h = 1500.0; // высокое окно: видно экран целиком, без прокрутки
      tester.view.physicalSize = Size(width * 3, h * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          // Как в приложении: время и даты системных виджетов на языке человека.
          locale: lang.locale,
          supportedLocales: LocaleService.supportedLocales,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: TimeCapsuleScreen(
            theme: theme,
            pairId: 'g',
            authorName: 'Аня',
            authorAvatar: '',
            now: () => DateTime(2026, 10, 14, 12),
            previewPhotoPath: filled ? 'assets/coloring/beach_thumb.jpg' : null,
          ),
        ),
      ));
      if (filled) {
        await tester.enterText(find.byKey(const ValueKey('capsule-title')), 'Нам через полгода');
        await tester.enterText(
          find.byKey(const ValueKey('capsule-letter')),
          'Привет из октября. Сейчас ты сидишь рядом и ругаешься на остывший кофе, '
          'а я пишу тебе в будущее. Если мы читаем это вместе, значит, всё '
          'получилось: и переезд, и собака, и море в мае.',
        );
        FocusManager.instance.primaryFocus?.unfocus();
      }
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.runAsync(() async {
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await boundary.toImage(pixelRatio: 2);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        Directory('build/time-capsule').createSync(recursive: true);
        File('build/time-capsule/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    });
  }
}
