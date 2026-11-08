import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/pair_data.dart';
import 'package:love_app/screens/mood_calendar_screen.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/mood_service.dart';
import 'package:love_app/services/widget_service.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Календарь настроений с открытым барабаном месяца и года — на глаз.
///
/// Имя без `_test`: файл для просмотра. Запуск:
/// `flutter test test/goldens/mood_calendar_wheel_preview.dart`, картинка в
/// `build/mood-wheel/`.
Future<void> _loadFont(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return;
  final loader = FontLoader(family)..addFont(file.readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

void main() {
  setUpAll(() async {
    await _loadFont('Onest', 'assets/fonts/Onest.ttf');
    await _loadFont('Unbounded', 'assets/fonts/Unbounded.ttf');
  });

  testWidgets('барабан на календаре', (t) async {
    SharedPreferences.setMockInitialValues({});
    await LocaleService.instance.setLanguage(AppLanguage.ru);
    t.view.physicalSize = const Size(1179, 2556);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        home: MoodCalendarScreen(
          pairData: PairData(),
          moodService: MoodService(),
          widgetService: WidgetService(),
          theme: AppThemes.pink,
        ),
      ),
    ));
    await t.pump(const Duration(milliseconds: 500));
    // Месяц назад — появляется кнопка «Сегодня».
    await t.fling(find.byKey(const ValueKey('cal_swipe-false')), const Offset(300, 0), 1500);
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(find.byKey(const ValueKey('cal_title')));
    // Барабан выезжает анимацией размера: снимок после неё.
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 300));
    await t.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/mood-wheel').createSync(recursive: true);
      File('build/mood-wheel/wheel.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
