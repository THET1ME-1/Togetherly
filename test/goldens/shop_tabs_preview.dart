import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:love_app/models/avatar_frame.dart';
import 'package:love_app/models/user_data.dart';
import 'package:love_app/screens/gifts/gift_shop_screen.dart';
import 'package:love_app/services/catalog_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';

import '../helpers/badge_catalog.dart';

/// Вкладки значков и рамок для глаз: `flutter test test/goldens/shop_tabs_preview.dart`
/// → build/shop-tabs/*.png. Рамки рисуются неподвижными кадрами из сборки —
/// сети в тестах нет. Имя без `_test`: обычный прогон его не берёт.
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
  setUpAll(() async {
    await _loadFont('Onest', ['assets/fonts/Onest.ttf']);
    await _loadFont('Unbounded', ['assets/fonts/Unbounded.ttf']);
    await _loadFont('MaterialIcons', [
      '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache'
          '/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const keys = ['wreath', 'hearts', 'daisies', 'cloud', 'ribbon', 'lights', 'donut', 'clock', 'cat'];
  const names = ['Венок', 'Сердечки', 'Ромашки', 'Облачко', 'Ленточка', 'Гирлянда', 'Пончик', 'Циферблат', 'Котик'];
  final frames = [
    for (var i = 0; i < keys.length; i++)
      AvatarFrame(
        key: keys[i],
        rarity: i < 3 ? 'common' : (i < 6 ? 'rare' : 'legendary'),
        sort: i * 10,
        names: {'ru': names[i]},
      ),
  ];

  // Значки тянут картинки из сети, а её в тестах нет — снимаем только рамки.
  for (final tab in [ShopTab.frames]) {
    for (final dark in [false, true]) {
      testWidgets('$tab ${dark ? 'тёмная' : 'светлая'}', (tester) async {
        installTestBadges();
        CatalogService.instance.debugSetFrames(frames);
        final ud = UserData()..applyOwnedFeatures(const ['frame:frame_cat']);
        tester.view.physicalSize = const Size(393 * 2, 1700);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        final theme = buildAppTheme(kPalettes[1], dark ? Brightness.dark : Brightness.light);
        final key = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
          key: key,
          child: MaterialApp(
            theme: ProfileTheme.data(ProfileTheme.schemeFor(theme)),
            home: MediaQuery(
              data: const MediaQueryData(size: Size(393, 850)),
              child: GiftShopScreen(
                theme: theme,
                groupId: 'g',
                coins: 1109,
                onCoins: (_) {},
                userData: ud,
                initialTab: tab,
              ),
            ),
          ),
        ));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final img = await b.toImage(pixelRatio: 1);
          final data = await img.toByteData(format: ui.ImageByteFormat.png);
          Directory('build/shop-tabs').createSync(recursive: true);
          File('build/shop-tabs/${tab.name}_${dark ? 'dark' : 'light'}.png')
              .writeAsBytesSync(data!.buffer.asUint8List());
        });
      });
    }
  }
}
