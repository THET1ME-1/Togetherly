import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/chest.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/chest/chest_frames.dart';
import 'package:love_app/widgets/chest/chest_share_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Карточка приза «Поделиться» глазами: две темы, два приза.
///
///   flutter test test/goldens/chest_share_preview.dart → build/chest-share/*.png
///
/// Анимацию открытия берёт из мастерской значков, если она есть рядом
/// (`~/Projects/togetherly-badges-hand/out_chest/chest_open/lg.webp`); без неё
/// на карточке неподвижный кадр из сборки.

Future<void> _loadFont(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return;
  final loader = FontLoader(family)..addFont(file.readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

const _open = 'test://chest_open';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'app_language': 'ru'});
    await LocaleService.instance.init();
    await _loadFont('Onest', 'assets/fonts/Onest.ttf');
    await _loadFont('Unbounded', 'assets/fonts/Unbounded.ttf');
    final webp = File('${Platform.environment['HOME']}/Projects/togetherly-badges-hand/out_chest/chest_open/lg.webp');
    if (webp.existsSync()) ChestFrames.debugPut(_open, webp.readAsBytesSync());
  });

  final cases = {
    'plus7': ('Togetherly+ на 7 дней', const ChestPrize(key: 'plus7', kind: ChestPrizeKind.plusTrial, weight: 10, tier: ChestTier.rare), 'Шанс 1%'),
    'teddy': ('Подарок «Мишка»', const ChestPrize(key: 'teddy', kind: ChestPrizeKind.gift, weight: 20, tier: ChestTier.rare), 'Шанс 2%'),
  };

  for (final b in Brightness.values) {
    for (final e in cases.entries) {
      testWidgets('${e.key} ${b.name}', (tester) async {
        final theme = buildAppTheme(kPalettes[0], b);
        final cs = ProfileTheme.themeFor(theme).colorScheme;
        tester.view.physicalSize = const Size(360 * 2, 640 * 2);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        final key = GlobalKey();
        final (tierKey, strong) = chestShareTier(e.value.$2);
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ProfileTheme.data(cs),
          home: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: key,
              child: ChestShareCard(
                prize: e.value.$2,
                title: e.value.$1,
                tierLabel: tierKey == 'chestTierTop' ? 'Главный приз' : 'Редкий приз',
                strongTier: strong,
                chance: e.value.$3,
                scheme: cs,
                fill: theme.fillColor,
                openUrl: _open,
              ),
            ),
          ),
        ));
        // Кадры анимации и картинки подарка декодируются вне тестовых часов.
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
          await tester.pump();
        }
        await tester.runAsync(() async {
          final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          Directory('build/chest-share').createSync(recursive: true);
          File('build/chest-share/${e.key}-${b.name}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      });
    }
  }
}
