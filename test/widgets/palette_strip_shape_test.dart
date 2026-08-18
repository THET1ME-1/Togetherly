import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/widgets/seed_swatch.dart';

/// Кружок палитры обязан остаться кружком.
///
/// Лента «Палитра» — горизонтальный `ListView` внутри `SizedBox(height: 62)`, а
/// он раздаёт детям ЖЁСТКУЮ высоту: `Container(width: 46, height: 46)` внутри
/// таких ограничений растягивается до 62 и рисуется эллипсом (снимок человека,
/// 18.08.2026). Кнопка «завести свою тему» рядом при этом остаётся 46 и стоит
/// не на одной линии с остальными.
void main() {
  Widget strip(List<Widget> items) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 62,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => items[i],
            ),
          ),
        ),
      );

  testWidgets('кружок палитры круглый, а не овальный', (tester) async {
    await tester.pumpWidget(strip([
      SeedSwatch(palette: paletteByIndex(0), size: 46),
      SeedSwatch(palette: paletteByIndex(1), size: 46, selected: true),
    ]));

    // Меряем сам кружок, а не то место, что виджет занял в ленте: по высоте
    // ему и положено растянуться, круглой обязана остаться картинка внутри.
    final sizes = tester
        .widgetList<SeedSwatch>(find.byType(SeedSwatch))
        .map((w) => tester.getSize(find.descendant(
              of: find.byWidget(w),
              matching: find.byType(ClipOval),
            )))
        .toList();

    for (final s in sizes) {
      expect(s.height, s.width,
          reason: 'кружок вытянулся: ${s.width}×${s.height}');
      // Рамка съедает по пикселю с каждой стороны, поэтому сравниваем с
      // запасом: важно, что кружок не растянулся до высоты ленты (62).
      expect(s.width, lessThanOrEqualTo(46.0));
      expect(s.width, greaterThanOrEqualTo(40.0));
    }
  });

  testWidgets('соседние кружки стоят на одной линии', (tester) async {
    await tester.pumpWidget(strip([
      SeedSwatch(palette: paletteByIndex(0), size: 46),
      SeedSwatch(palette: paletteByIndex(1), size: 46, selected: true),
    ]));

    final centers = tester
        .widgetList<SeedSwatch>(find.byType(SeedSwatch))
        .map((w) => tester.getCenter(find.descendant(
              of: find.byWidget(w),
              matching: find.byType(ClipOval),
            )).dy)
        .toList();
    expect(centers.first, centers.last,
        reason: 'кружки ленты съехали друг относительно друга');
  });
}
