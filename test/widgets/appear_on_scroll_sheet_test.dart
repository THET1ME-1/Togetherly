import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/common/animations.dart';

/// Ячейки настроек появляются каскадом, «когда экран доехал до них».
///
/// В нижнем листе это оборачивалось пустым экраном: на первом кадре лист ещё
/// едет снизу, содержимое физически ниже экрана, а прокручивать короткий
/// список нечего — второго повода проверить видимость не наступало никогда.
/// Так выглядел раздел «Уведомления»: заголовок, пустота и кнопка внизу
/// (жалоба со скриншотом 13 августа 2026).
void main() {
  testWidgets('содержимое нижнего листа видно после его появления',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppearOnScroll(index: 0, child: Text('Скучаю')),
                      AppearOnScroll(index: 1, child: Text('Чат')),
                    ],
                  ),
                ),
                child: const Text('открыть'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();

    for (final label in ['Скучаю', 'Чат']) {
      final opacity = tester.widget<Opacity>(
        find.ancestor(of: find.text(label), matching: find.byType(Opacity)).first,
      );
      expect(opacity.opacity, 1.0, reason: 'строка «$label» осталась невидимой');
    }
  });
}
