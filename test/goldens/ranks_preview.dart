import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/rank.dart';
import 'package:love_app/screens/profile/profile_hero.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/rank/new_rank_dialog.dart';
import 'package:love_app/widgets/rank/rank_chip.dart';
import 'package:love_app/widgets/rank/ranks_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Звания за часы глазами: шапка профиля с чипом, лист званий и экран нового
/// звания, светлая и тёмная тема, 360 точек.
///
///   flutter test test/goldens/ranks_preview.dart → build/ranks/*.png
///
/// Эмблемы приходят из каталога по сети, в тесте их нет — на их месте пусто.

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
    await _loadFont('Unbounded', 'assets/fonts/Unbounded.ttf');
  });

  Future<void> shot(WidgetTester tester, String name, Widget child, Size size, ColorScheme cs) async {
    final key = GlobalKey();
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ProfileTheme.data(cs),
      home: RepaintBoundary(key: key, child: Material(color: cs.surface, child: child)),
    ));
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/ranks').createSync(recursive: true);
      File('build/ranks/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  for (final b in Brightness.values) {
    final cs = ProfileTheme.themeFor(buildAppTheme(kPalettes[0], b)).colorScheme;

    testWidgets('шапка профиля ${b.name}', (tester) async {
      await shot(
        tester,
        'hero-${b.name}',
        Align(
          alignment: Alignment.topCenter,
          child: ProfileHero(
            cs: cs,
            uid: 'u1',
            avatarUrl: '',
            name: 'Маша',
            bannerUrl: '',
            subtitle: '312 дней вместе',
            rankChip: RankChip(cs: cs, seconds: 3 * 3600 + 20 * 60, hours: kRankHours, onTap: () {}),
          ),
        ),
        const Size(360, 320),
        cs,
      );
    });

    testWidgets('лист званий ${b.name}', (tester) async {
      await shot(tester, 'sheet-${b.name}', RanksSheet(cs: cs, seconds: 3 * 3600 + 20 * 60, hours: kRankHours), const Size(360, 900), cs);
    });

    testWidgets('новое звание ${b.name}', (tester) async {
      await shot(tester, 'new-${b.name}', const Center(child: NewRankDialog(rank: 5, seconds: 15 * 3600 + 4 * 60)), const Size(360, 640), cs);
    });
  }
}
