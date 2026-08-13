import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Превью виджетов в каталоге не должны вылезать за свою плитку.
///
/// Скриншот тестера 13 августа 2026: в карточке «Календарь лет 2×2» подпись
/// «601 день вместе» налезала на строку под ней. Причина простая — квадрат 2×2
/// тесный, а содержимое не ужималось.
///
/// Тест держит приём: содержимое сжимается [FittedBox], а не переполняет
/// плитку. Проверяем на макете той же формы, что у превью, — сам экран
/// каталога поднять в тесте нельзя, он тянет плагины виджетов и покупки.
void main() {
  Widget tile({required bool shrinkToFit}) {
    const numbers = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('601', style: TextStyle(fontSize: 52, height: 1.02)),
        Text('день вместе', style: TextStyle(fontSize: 14.5)),
        SizedBox(height: 3),
        Text('2-й год · 129 дней', style: TextStyle(fontSize: 12)),
      ],
    );

    // Так теперь устроено превью: крупный блок с числом ужимается целиком,
    // а сетка месяцев сверху остаётся как есть.
    final shrinking = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(height: 60, color: Colors.pink.shade100),
        const Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.bottomLeft,
            child: numbers,
          ),
        ),
      ],
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(height: 60, color: Colors.pink.shade100),
        const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('601', style: TextStyle(fontSize: 52, height: 1.02)),
            Text('день вместе', style: TextStyle(fontSize: 14.5)),
            SizedBox(height: 3),
            Text('2-й год · 129 дней', style: TextStyle(fontSize: 12)),
          ],
        ),
      ],
    );

    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 148,
            height: 148,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: shrinkToFit ? shrinking : content,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('без сжатия содержимое переполняет плитку', (tester) async {
    await tester.pumpWidget(tile(shrinkToFit: false));
    expect(tester.takeException(), isNotNull,
        reason: 'проверка бесполезна: макет и так помещается');
  });

  testWidgets('со сжатием переполнения нет', (tester) async {
    await tester.pumpWidget(tile(shrinkToFit: true));
    expect(tester.takeException(), isNull);
  });
}
