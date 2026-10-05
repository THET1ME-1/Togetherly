import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/together/watch_home_blocks.dart';

/// Экран «Смотрим», вариант А «Афиша и плитки»: главная карточка и плитки на
/// теме «Розовая» — 393 точки, 320 точек с шрифтом 1,3 и тёмная тема.
///
/// Имя без `_test`: файл для глаз. Запуск:
/// `flutter test test/goldens/watch_home_preview.dart`, картинка в
/// `build/watch-home/blocks.png`.
Future<void> _font(String family, String path) async {
  final f = File(path);
  if (!f.existsSync()) return;
  await (FontLoader(family)..addFont(f.readAsBytes().then(ByteData.sublistView))).load();
}

void main() {
  setUpAll(() async {
    await _font('Onest', 'assets/fonts/Onest.ttf');
    await _font('Unbounded', 'assets/fonts/Unbounded.ttf');
    await _font('MaterialIcons', '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  });

  testWidgets('блоки экрана «Смотрим»', (tester) async {
    LocaleService.instance.setLanguage(AppLanguage.ru);
    tester.view.physicalSize = const Size(2400, 2000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final s = LocaleService.current;
    final pink = kPalettes.firstWhere((p) => p.name == 'Розовая');

    Widget phone(AppTheme t, double w, {double scale = 1, bool locked = true}) {
      final cs = t.scheme!;
      final pc = WatchComputerTile(code: '2x4vhuku', loading: false, onCopy: () {}, onOpenSite: () {});
      return Theme(
        data: ProfileTheme.data(cs),
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Container(
            width: w,
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(color: t.bgGradient.first, borderRadius: BorderRadius.circular(28)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WatchLead(title: s.watchHeroTitle, text: s.watchHeroText),
                const SizedBox(height: 12),
                WatchKinoCard(
                  theme: t,
                  title: s.watchWithPartner('JB SHARAN'),
                  subtitle: s.watchRoomOpensForBoth,
                  myUid: '',
                  myAvatar: '',
                  myName: 'Саня',
                  partnerUid: 'p1',
                  partnerAvatar: '',
                  partnerName: 'JB SHARAN',
                  note: s.watchAfterShortAd,
                  enabled: true,
                  onTap: () {},
                ),
                const SizedBox(height: 10),
                WatchBento(
                  reels: (tw) => WatchReelsTile(
                    title: s.reelsTogether,
                    text: locked ? s.reelsTogetherHint : s.reelsInvitedBy('JB SHARAN', 'TikTok'),
                    plusLocked: locked,
                    onTap: () {},
                    titleWidth: tw,
                  ),
                  games: (tw) => WatchGamesTile(title: s.gamesForTwo, text: s.gamesForTwoHint, onTap: () {}, titleWidth: tw),
                  computer: pc,
                ),
                const SizedBox(height: 10),
                WatchSectionHeader(title: s.watchOurVideos, count: 3),
              ],
            ),
          ),
        ),
      );
    }

    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFEFE7E4),
        body: RepaintBoundary(
          key: key,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              phone(buildAppTheme(pink, Brightness.light), 393),
              phone(buildAppTheme(pink, Brightness.light), 320, scale: 1.3, locked: false),
              phone(buildAppTheme(pink, Brightness.dark), 393),
            ],
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull, reason: 'без переполнений и падений');
    await tester.runAsync(() async {
      for (final e in tester.allElements.whereType<StatefulElement>()) {
        final w = e.widget;
        if (w is Image) await precacheImage(w.image, e);
      }
    });
    await tester.pump();
    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/watch-home').createSync(recursive: true);
      File('build/watch-home/blocks.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
