// Картинки листа смены баннера со строкой GIF поверх шапки профиля:
// flutter test test/goldens/banner_gif_preview.dart → build/banner-gif/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:love_app/screens/profile/banner_source_sheet.dart';
import 'package:love_app/screens/profile/profile_hero.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/plus_access.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _font(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return;
  final loader = FontLoader(family)
    ..addFont(file.readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

/// Полосатый «закат» 320×180 в два кадра — вместо настоящего GIF.
List<int> _bannerGif() {
  img.Image frame(int shift) {
    final f = img.Image(width: 320, height: 180);
    for (var y = 0; y < 180; y++) {
      final t = ((y + shift) % 180) / 180;
      img.drawLine(f,
          x1: 0,
          y1: y,
          x2: 319,
          y2: y,
          color: img.ColorRgb8(
              (250 - 60 * t).round(), (140 + 60 * t).round(), (120 + 90 * t).round()));
    }
    f.frameDuration = 120;
    return f;
  }

  return img.encodeGif(frame(0)..addFrame(frame(60)));
}

void main() {
  late String gifPath;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'app_language': 'ru'});
    await LocaleService.instance.init();
    await _font('Onest', 'assets/fonts/Onest.ttf');
    await _font('Unbounded', 'assets/fonts/Unbounded.ttf');
    await _font('MaterialIcons',
        '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    final dir = Directory.systemTemp.createTempSync('banner_preview');
    gifPath = '${dir.path}/banner.gif';
    File(gifPath).writeAsBytesSync(_bannerGif());
  });

  for (final (name, palette, b, width, scale, lang, gate) in [
    ('pink-light-393-locked', 0, Brightness.light, 393.0, 1.0, AppLanguage.ru, PlusGate.locked),
    ('pink-light-393-open', 0, Brightness.light, 393.0, 1.0, AppLanguage.ru, PlusGate.open),
    ('mint-dark-320-1.3-de-locked', 12, Brightness.dark, 320.0, 1.3, AppLanguage.de, PlusGate.locked),
  ]) {
    testWidgets(name, (tester) async {
      // Поток кадров файла живёт в общем кэше картинок: без чистки застывший
      // снимок встал бы на кадре, до которого его докрутил живой.
      imageCache
        ..clear()
        ..clearLiveImages();
      LocaleService.instance.setLanguage(lang);
      final theme = buildAppTheme(kPalettes[palette], b);
      final cs = ProfileTheme.themeFor(theme).colorScheme;
      const h = 760.0;
      tester.view.physicalSize = Size(width * 3, h * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      late BuildContext ctx;
      await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ProfileTheme.data(cs),
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Builder(builder: (c) {
            ctx = c;
            return Scaffold(
              backgroundColor: cs.surface,
              body: ListView(
                padding: EdgeInsets.zero,
                children: [
                  ProfileHero(
                    cs: cs,
                    uid: 'u1',
                    avatarUrl: '',
                    name: 'Саша',
                    theme: theme,
                    plus: gate == PlusGate.open,
                    bannerUrl: '',
                    localBannerPath: gifPath,
                    bannerAnimated: gate == PlusGate.open,
                    subtitle: 'вместе 688 дней',
                    onEdit: () {},
                    onPickBanner: () {},
                    onTapAvatar: () {},
                    onSettings: () {},
                    onHelp: () {},
                  ),
                ],
              ),
            );
          }),
        ),
      ));
      // Чтение файла и разбор кадра идут настоящим временем.
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 50));
      }

      Future<void> shot(String file) => tester.runAsync(() async {
            final boundary = key.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 2);
            final png =
                await image.toByteData(format: ui.ImageByteFormat.png);
            Directory('build/banner-gif').createSync(recursive: true);
            File('build/banner-gif/$file.png')
                .writeAsBytesSync(png!.buffer.asUint8List());
          });

      await shot('$name-hero');
      showBannerSourceSheet(ctx, cs: cs, gifGate: gate);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      await shot(name);
    });
  }
}
