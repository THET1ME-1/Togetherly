import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/common/animations.dart';

/// Ячейки настроек встают на место, когда экран доезжает до них.
///
/// Прежний `AnimatedSlideIn` стартовал сразу для всего списка: у дальних строк
/// движение проходило за нижней кромкой, и человек долистывал до уже стоящей
/// ячейки. Тесты держат оба конца — верхняя появляется сама, нижняя ждёт
/// прокрутки.
void main() {
  /// Насколько блок ещё не на месте. Пружина финиширует с микроскопическим
  /// остатком, поэтому «стоит на месте» — это доли точки, а не побитовый ноль.
  Offset offsetOf(WidgetTester tester, String label) {
    final transform = tester.widget<Transform>(
      find
          .ancestor(of: find.text(label), matching: find.byType(Transform))
          .first,
    );
    return Offset(
      transform.transform.getTranslation().x,
      transform.transform.getTranslation().y,
    );
  }

  Future<void> pumpList(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              for (var i = 0; i < 20; i++)
                AppearOnScroll(
                  index: i,
                  child: SizedBox(height: 80, child: Text('строка $i')),
                ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('верхняя ячейка встаёт на место сама', (tester) async {
    await pumpList(tester);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(offsetOf(tester, 'строка 0').dy.abs(), lessThan(0.5));
  });

  testWidgets('дальняя ячейка ждёт, пока до неё долистают', (tester) async {
    await pumpList(tester);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Пятнадцатая строка лежит далеко за нижней кромкой: её ещё не показывали.
    expect(find.text('строка 15'), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pump();

    // Долистали — движение только начинается, блок ещё смещён.
    expect(offsetOf(tester, 'строка 15').dy, greaterThan(0));

    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(offsetOf(tester, 'строка 15').dy.abs(), lessThan(0.5));
  });

  testWidgets('системный запрет анимаций ставит блок сразу', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(400, 800),
            disableAnimations: true,
          ),
          child: Scaffold(
            body: AppearOnScroll(child: Text('без движения')),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(offsetOf(tester, 'без движения').dy.abs(), lessThan(0.5));
  });
}
