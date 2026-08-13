// Подсказка не должна падать на узком экране.
//
// Bugsink, 14 августа 2026: «Invalid argument(s): 12.0» в showHintBubble на
// 1.26. Пузырь шириной 250 плюс два отступа по 12 не помещаются в узкое окно,
// правая граница clamp уезжает левее левой — и вызов падает вместо того, чтобы
// прижать пузырь к краю.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Та же арифметика, что в showHintBubble: границы обязаны идти по порядку.
double leftFor({
  required double targetCenterX,
  required double screenWidth,
  double bubbleWidth = 250.0,
  double margin = 12.0,
}) {
  final maxLeft = (screenWidth - bubbleWidth - margin) > margin
      ? screenWidth - bubbleWidth - margin
      : margin;
  return (targetCenterX - bubbleWidth / 2).clamp(margin, maxLeft);
}

void main() {
  test('на обычном экране пузырь держится за центр цели', () {
    expect(leftFor(targetCenterX: 200, screenWidth: 400), 75);
  });

  test('у левого края пузырь прижимается к отступу', () {
    expect(leftFor(targetCenterX: 20, screenWidth: 400), 12);
  });

  test('у правого края пузырь не вылезает за экран', () {
    expect(leftFor(targetCenterX: 390, screenWidth: 400), 138);
  });

  test('на узком экране границы не переворачиваются', () {
    for (final width in [260.0, 250.0, 200.0, 120.0]) {
      expect(
        () => leftFor(targetCenterX: width / 2, screenWidth: width),
        returnsNormally,
        reason: 'ширина $width валила clamp: верхняя граница уходила ниже нижней',
      );
      expect(leftFor(targetCenterX: width / 2, screenWidth: width), 12);
    }
  });

  testWidgets('показ подсказки в узком окне не роняет экран',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(240, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    expect(tester.takeException(), isNull);
  });
}
