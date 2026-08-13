import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Внутрь `CarouselView` кнопки класть нельзя.
///
/// Карусель ловит нажатие на весь элемент, и кнопка на обложке до своего
/// обработчика не доживает — даже когда у самой карусели `onTap` не задан.
/// В экране совместного просмотра на этом сломалось удаление ролика: человек
/// жал корзину, попадал в комнату просмотра и встречал там рекламу («не
/// работает кнопка удаления видео, просит посмотреть рекламу и перекидывает на
/// кинотеатр», 13 августа 2026). Поэтому действия по ролику ушли в нижний лист:
/// «Смотреть вместе» и «Удалить».
///
/// Тест держит это знание. Если однажды он упадёт, значит Flutter пропускает
/// нажатия внутрь элементов карусели — тогда кнопку можно вернуть на обложку.
void main() {
  testWidgets('кнопка внутри карусели не получает нажатие', (tester) async {
    var pressed = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 200,
            child: CarouselView.weighted(
              flexWeights: const [3, 2, 1],
              children: [
                for (var i = 0; i < 3; i++)
                  Stack(
                    fit: StackFit.expand,
                    children: [
                      const ColoredBox(color: Colors.black12),
                      Positioned(
                        top: 6,
                        left: 6,
                        child: IconButton(
                          onPressed: () => pressed++,
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
    await tester.pumpAndSettle();

    expect(pressed, 0,
        reason: 'карусель пропустила нажатие внутрь — кнопку можно вернуть');
  });
}
