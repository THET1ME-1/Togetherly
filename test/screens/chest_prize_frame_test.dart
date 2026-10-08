import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/chest.dart';
import 'package:love_app/screens/chest_prize_screen.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/widgets/chest/chest_prize_image.dart';

/// Рамка на экране приза помещается в экран (жалоба с 1.35.0+245: «рамки
/// слишком большие и толстые» — венок вылезал за края).
void main() {
  testWidgets('рамка на экране приза не шире экрана', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final t = buildAppTheme(kPalettes.first, Brightness.light);
    await tester.pumpWidget(
      MaterialApp(
        home: ChestPrizeScreen(
          theme: t,
          prize: const ChestPrize(key: 'frame_autumnwreath', kind: ChestPrizeKind.frame, weight: 0, tier: ChestTier.common),
          title: 'Рамка «Осенний венок»',
          subtitle: 'Рамка для аватарки, навсегда',
          tier: 'Обычные',
          chance: '2%',
        ),
      ),
    );
    await tester.pump();
    final size = tester.getSize(find.byType(ChestPrizeImage));
    expect(size.width, lessThanOrEqualTo(412 * 0.9));
  });
}
