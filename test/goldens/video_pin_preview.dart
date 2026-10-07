import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/memory/video_pin.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Видео-пин глазами: светлая и тёмная тема, 360 точек.
///
///   flutter test test/goldens/video_pin_preview.dart → build/video-pin/*.png
///
/// Кадров в превью нет — так пин выглядит у роликов без обложки (TikTok из
/// совместной ленты).

Future<void> _loadFont(String family, String path) async {
  final loader = FontLoader(family)
    ..addFont(File(path).readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'app_language': 'ru'});
    await LocaleService.instance.init();
    await _loadFont('Onest', 'assets/fonts/Onest.ttf');
    await _loadFont('MaterialIcons', '${Platform.environment['FLUTTER_ROOT'] ?? '/home/alelx/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  });

  for (final b in Brightness.values) {
    testWidgets('видео-пин ${b.name}', (tester) async {
      final theme = buildAppTheme(kPalettes[0], b);
      final cs = ProfileTheme.themeFor(theme).colorScheme;
      final key = GlobalKey();
      tester.view.physicalSize = const Size(360 * 2, 1500 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      Widget card(Widget pin) => Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: theme.cardSurface,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: pin,
            ),
          );

      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ProfileTheme.data(cs),
        home: RepaintBoundary(
          key: key,
          // Material: в ленте текст наследует стиль от неё, а без неё Flutter
          // метит его жёлтым подчёркиванием.
          child: Material(
            type: MaterialType.transparency,
            child: Container(
            color: b == Brightness.light ? const Color(0xFFFFE8DC) : cs.surface,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                card(VideoPin(
                  scheme: cs,
                  fill: theme.fillColor,
                  url: 'https://youtu.be/dQw4w9WgXcQ',
                  platformName: 'YouTube',
                  platformIcon: Icons.smart_display_rounded,
                  title: 'Сплав по озеру — влог за выходные',
                  author: 'Аня и Кирилл',
                  onPlay: () {},
                  onOpen: () {},
                  onWatchTogether: () {},
                )),
                card(VideoPin(
                  scheme: cs,
                  fill: theme.fillColor,
                  url: 'https://www.tiktok.com/@mila.k/video/1',
                  platformName: 'TikTok',
                  platformIcon: Icons.music_video_rounded,
                  title: 'когда он опять забыл купить хлеб',
                  author: '@mila.k',
                  caption: 'Из совместной ленты',
                  onPlay: () {},
                  onOpen: () {},
                )),
              ],
            ),
          ),
          ),
        ),
      ));
      await tester.pump();
      await tester.runAsync(() async {
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory('build/video-pin').createSync(recursive: true);
        File('build/video-pin/${b.name}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    });
  }
}
