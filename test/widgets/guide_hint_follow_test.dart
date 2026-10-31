import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/widgets/common/guide_hint.dart';

/// Главная прокручивается и под открытой подсказкой. Владелец пролистал вниз:
/// кнопка уехала, а облачко, кольцо и пузырь остались висеть на месте.
void main() {
  testWidgets('подсказка едет вместе с кнопкой при прокрутке', (tester) async {
    final target = GlobalKey();
    final scroll = ScrollController();
    final theme = buildAppTheme(kPalettes[3], Brightness.light);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          controller: scroll,
          children: [
            const SizedBox(height: 300),
            Center(child: SizedBox(key: target, width: 60, height: 60)),
            const SizedBox(height: 1200),
          ],
        ),
      ),
    ));

    showGuideHint(
      tester.element(find.byKey(target)),
      targetKey: target,
      text: 'Подсказка',
      gotIt: 'Понятно',
      theme: theme,
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final before = tester.getTopLeft(find.text('Подсказка'));

    scroll.jumpTo(100);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    final after = tester.getTopLeft(find.text('Подсказка'));

    expect(after.dy, closeTo(before.dy - 100, 0.5));
    expect(after.dx, closeTo(before.dx, 0.5));

    await tester.tap(find.text('Понятно'));
    await tester.pump(const Duration(milliseconds: 200));
  });
}
