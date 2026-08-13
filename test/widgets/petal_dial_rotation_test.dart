import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/widgets/petal_timer_dial.dart';

/// Круг должен крутиться пальцем.
///
/// 11 августа 2026 оптимизация уже ломала это: painter получал угол снимком в
/// `build`, а перерисовка шла мимо дерева — угол застыл на нуле, и круг
/// перестал вращаться. Правку пришлось откатывать целиком. Теперь painter
/// читает значения внутри `paint()`, и этот тест держит поведение.
void main() {
  testWidgets('вращение пальцем доезжает до отрисовки', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 280,
              height: 280,
              child: PetalTimerDial(
                startDate: DateTime(2024, 1, 1),
                theme: AppThemes.all.first,
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final before = PetalTimerDial.debugLastPaintedRotation;

    // Крутим круг пальцем по дуге.
    final center = tester.getCenter(find.byType(PetalTimerDial));
    final gesture = await tester.startGesture(center + const Offset(0, -100));
    for (var i = 1; i <= 8; i++) {
      await gesture.moveBy(const Offset(14, 5));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));

    expect(
      PetalTimerDial.debugLastPaintedRotation,
      isNot(closeTo(before, 0.0001)),
      reason: 'до отрисовки доехал старый угол — painter снова держит снимок',
    );
  });
}
