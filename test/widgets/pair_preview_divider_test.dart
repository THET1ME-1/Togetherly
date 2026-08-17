// Разделитель в превью парного виджета совпадает с нативным.
//
// Превью в каталоге обещало вид «1:1 с нативным LoveWidget», а рисовало белую
// полосу 14 без линий и с символом `♥`. Глиф брался из запасного шрифта и
// вылезал на половину партнёра — тестер обвёл его на снимке (17.08.2026).
//
// Числа сверяются с `android/app/src/main/res/layout/love_widget.xml` и
// `LoveDivider` в `ios/TogetherlyWidget/LoveWidget.swift`: полоса 20,
// сердце 12, две линии по весу.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/pair_preview_divider.dart';

void main() {
  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(height: 100, child: PairPreviewDivider()),
        ),
      ),
    ),
  );

  testWidgets('полоса шириной 20, как в нативной разметке', (tester) async {
    await pump(tester);
    final box = tester.getSize(find.byType(PairPreviewDivider));
    expect(box.width, PairPreviewDivider.width);
  });

  testWidgets('сердце стоит ровно по центру полосы', (tester) async {
    await pump(tester);
    final heart = find.byIcon(Icons.favorite_rounded);
    expect(heart, findsOneWidget);

    final heartCenter = tester.getCenter(heart);
    final dividerCenter = tester.getCenter(find.byType(PairPreviewDivider));
    expect(heartCenter.dx, closeTo(dividerCenter.dx, 0.5));
    expect(heartCenter.dy, closeTo(dividerCenter.dy, 0.5));
  });

  testWidgets('сердце не шире полосы: на половину партнёра не выходит', (
    tester,
  ) async {
    await pump(tester);
    final heartWidth = tester.getSize(find.byIcon(Icons.favorite_rounded)).width;
    expect(heartWidth, lessThanOrEqualTo(PairPreviewDivider.width));
  });

  testWidgets('линии сверху и снизу на месте', (tester) async {
    await pump(tester);
    final lines = find.byWidgetPredicate(
      (w) => w is ColoredBox && w.color == PairPreviewDivider.lineColor,
    );
    expect(lines, findsNWidgets(2));
  });
}
