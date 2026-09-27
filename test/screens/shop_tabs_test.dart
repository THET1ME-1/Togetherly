import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:love_app/dict_strings.dart' show trKey;
import 'package:love_app/models/avatar_frame.dart';
import 'package:love_app/models/user_data.dart';
import 'package:love_app/screens/gifts/gift_shop_screen.dart';
import 'package:love_app/services/catalog_service.dart';
import 'package:love_app/theme/app_palettes.dart';

import '../helpers/badge_catalog.dart';

/// Магазин на трёх вкладках (макет «Магазин», 27.09.2026). Проверяем то, что
/// ломается молча: вкладка рамок не предлагает купить рамку (они только из
/// сундука), надетое помечено, а на 320 dp при шрифте 1.3 ничего не вылезает.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const frames = [
    AvatarFrame(key: 'wreath', sort: 10, stillUrl: 'https://x/w.png'),
    AvatarFrame(key: 'cat', rarity: 'legendary', sort: 90, stillUrl: 'https://x/c.png'),
  ];

  Future<void> pumpShop(WidgetTester tester, ShopTab tab, {double scale = 1.3}) async {
    installTestBadges();
    CatalogService.instance.debugSetFrames(frames);
    final ud = UserData()..applyOwnedFeatures(const ['frame:frame_cat']);
    tester.view.physicalSize = const Size(320, 720) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: const Size(320, 720), textScaler: TextScaler.linear(scale)),
        child: GiftShopScreen(
          theme: buildAppTheme(kPalettes[0], Brightness.light),
          groupId: '',
          coins: 25,
          onCoins: (_) {},
          userData: ud,
          initialTab: tab,
          showGifts: false,
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('рамки: «Из сундука» вместо цены, полученная помечена своей', (tester) async {
    await pumpShop(tester, ShopTab.frames);
    expect(tester.takeException(), isNull);
    expect(find.text(trKey('shopFromChest')), findsOneWidget);
    expect(find.text(trKey('shopMineFrame')), findsOneWidget);
    expect(find.textContaining(trKey('shopBuyFor').replaceAll('{n}', '')), findsNothing);
  });

  testWidgets('значки: цена из каталога, наградные без цены', (tester) async {
    await pumpShop(tester, ShopTab.badges);
    expect(tester.takeException(), isNull);
    expect(find.text('20'), findsOneWidget, reason: 'цена лапки из каталога');
    expect(find.text(trKey('shopAward')), findsWidgets);
  });

  testWidgets('вкладки переключаются', (tester) async {
    await pumpShop(tester, ShopTab.badges, scale: 1.0);
    await tester.tap(find.text(trKey('shopTabFrames')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(trKey('shopFromChest')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
