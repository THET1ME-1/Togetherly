import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/mood_entry.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/mood/day_mood_lanes.dart';

/// История настроения за день двумя дорожками на розовой теме, 393 и 320.
///
/// Имя без `_test`: файл для глаз. Запуск:
/// `flutter test test/goldens/day_mood_lanes_preview.dart`, картинка в
/// `build/qr-preview/day_mood_lanes.png`.
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

MoodEntry _e(String id, String mood, int h, int m) => MoodEntry(
      id: id,
      moodId: mood,
      imagePath: MoodOption.byId(mood)!.imagePath,
      label: mood,
      timestamp: DateTime(2026, 9, 29, h, m),
    );

void main() {
  setUpAll(() async {
    await _loadFont('Onest', ['assets/fonts/Onest.ttf']);
    await _loadFont('Unbounded', ['assets/fonts/Unbounded.ttf']);
  });

  testWidgets('две дорожки', (tester) async {
    LocaleService.instance.setLanguage(AppLanguage.ru);
    tester.view.physicalSize = const Size(1600, 1500);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final cs = ProfileTheme.schemeFor(AppThemes.pink);
    final key = GlobalKey();
    final mine = [_e('a', 'sad', 8, 40), _e('c', 'laugh', 13, 2), _e('f', 'kiss', 22, 48)];
    final theirs = [_e('b', 'happy', 9, 15), _e('d', 'anxiety', 17, 30), _e('e', 'love', 19, 5)];

    Widget phone(double w) => Container(
          width: w,
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(28)),
          // В приложении лист даёт Material, здесь — сам превью.
          child: Material(
            type: MaterialType.transparency,
            child: DayMoodLanes(
              mine: mine,
              theirs: theirs,
              myName: 'Саша',
              partnerName: 'Аня',
            ),
          ),
        );

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ProfileTheme.data(cs),
      home: RepaintBoundary(
        key: key,
        child: ColoredBox(
          color: const Color(0xFF171210),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [phone(393), phone(320)],
          ),
        ),
      ),
    ));
    await tester.runAsync(() async {
      final ctx = key.currentContext!;
      for (final e in [...mine, ...theirs]) {
        await precacheImage(AssetImage(e.imagePath), ctx);
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump(const Duration(milliseconds: 500));

    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/qr-preview')..createSync(recursive: true);
      File('${dir.path}/day_mood_lanes.png')
          .writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}
