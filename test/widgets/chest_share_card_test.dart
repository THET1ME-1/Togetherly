import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/chest.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/chest/chest_share_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Карточка приза из сундука для «Поделиться» (макет, вариант B, 07.10.2026):
/// лучи на всю карточку, открытый сундук с призом, название на тёмной плашке,
/// внизу подпись Togetherly и адрес. Углы прямые — иначе её принимают за
/// обрезанный скриншот, а скриншот и делали вместо неё.

Future<void> _loadFont(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return;
  final loader = FontLoader(family)..addFont(file.readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

const _plusTrial = ChestPrize(key: 'plus7', kind: ChestPrizeKind.plusTrial, weight: 10, tier: ChestTier.rare);

Future<ColorScheme> _pump(WidgetTester tester, {String title = 'Togetherly+ на 7 дней', Brightness b = Brightness.light}) async {
  final theme = buildAppTheme(kPalettes[0], b);
  final cs = ProfileTheme.themeFor(theme).colorScheme;
  tester.view.physicalSize = const Size(360 * 3, 640 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: ProfileTheme.data(cs),
    home: Align(
      alignment: Alignment.topLeft,
      child: ChestShareCard(
        prize: _plusTrial,
        title: title,
        tierLabel: 'Главный приз',
        strongTier: true,
        chance: 'Шанс 1%',
        scheme: cs,
        fill: theme.fillColor,
        openUrl: null,
      ),
    ),
  ));
  await tester.pump();
  return cs;
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'app_language': 'ru'});
    await LocaleService.instance.init();
    await _loadFont('Onest', 'assets/fonts/Onest.ttf');
    await _loadFont('Unbounded', 'assets/fonts/Unbounded.ttf');
  });

  test('ярус приза на карточке', () {
    expect(chestShareTier(_plusTrial), ('chestTierTop', true));
    expect(chestShareTier(const ChestPrize(key: 'plus', kind: ChestPrizeKind.plus, weight: 1, tier: ChestTier.legendary)),
        ('chestTierTop', true));
    expect(chestShareTier(const ChestPrize(key: 'domovoy', kind: ChestPrizeKind.badge, weight: 1, tier: ChestTier.legendary)),
        ('chestShareLegendary', true));
    expect(chestShareTier(const ChestPrize(key: 'owl', kind: ChestPrizeKind.badge, weight: 1, tier: ChestTier.rare)),
        ('chestShareRare', false));
    expect(chestShareTier(const ChestPrize(key: 'coins5', kind: ChestPrizeKind.coins, weight: 1, tier: ChestTier.common)),
        ('chestShareCommon', false));
  });

  testWidgets('360×640 — снимок ×3 даёт 1080×1920', (tester) async {
    await _pump(tester);
    expect(tester.getSize(find.byType(ChestShareCard)), const Size(kChestShareWidth, kChestShareHeight));
    expect(kChestShareWidth * 3, 1080);
    expect(kChestShareHeight * 3, 1920);
  });

  testWidgets('углы карточки прямые', (tester) async {
    await _pump(tester);
    final root = tester.widget<Material>(
        find.descendant(of: find.byType(ChestShareCard), matching: find.byType(Material)).first);
    expect(root.borderRadius, isNull);
    expect(root.shape, isNull);
    expect(find.descendant(of: find.byType(ChestShareCard), matching: find.byType(ClipRRect)).evaluate()
        .where((e) => (e.widget as ClipRRect).borderRadius != BorderRadius.zero &&
            tester.getSize(find.byWidget(e.widget)).width >= kChestShareWidth - 1), isEmpty,
        reason: 'скругление всей карточки');
  });

  testWidgets('подпись Togetherly и адрес, название, ярус и шанс', (tester) async {
    await _pump(tester);
    expect(find.text('Togetherly'), findsOneWidget);
    expect(find.text('togetherly.day'), findsOneWidget);
    expect(find.text('ВЫПАЛО ИЗ СУНДУКА'), findsOneWidget);
    expect(find.text('Togetherly+ на\u00A07\u00A0дней'), findsOneWidget);
    expect(find.text('Главный приз'), findsOneWidget);
    expect(find.text('Шанс 1%'), findsOneWidget);
  });

  for (final b in Brightness.values) {
    testWidgets('длинное название не ломает карточку: ${b.name}', (tester) async {
      await _pump(tester, b: b, title: 'Подарок «Шкатулка с медальоном и двумя фотографиями внутри»');
      expect(tester.takeException(), isNull);
    });
  }
}
