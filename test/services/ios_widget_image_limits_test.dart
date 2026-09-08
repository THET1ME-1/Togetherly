// Картинки в расширении виджета читаются со своим пределом, а не с общим.
//
// Расширению виджета на iPhone отводят около тридцати мегабайт. Аватарку в нём
// рисуют кружком в сорок-шестьдесят точек, но `WidgetImage.load` по умолчанию
// разжимает до 1200 — почти шесть мегабайт на каждую. В виджете настроения их
// до четырёх, и расширение умирает на разжатии: человек видит пустой
// прямоугольник вместо виджета.
//
// В парном виджете это уже разобрали 07.09.2026 (`LoveWidgetImage`: фото 700,
// аватарка 200, эмодзи 160), а в остальных виджетах остался общий предел.
// Тест держит правило для всех: ни один вызов `uiImage` не идёт без `maxSide`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ни один uiImage в расширении не читает картинку без предела', () {
    final dir = Directory('ios/TogetherlyWidget');
    if (!dir.existsSync()) return; // на машинах без iOS-части проверять нечего

    final offenders = <String>[];
    for (final file in dir.listSync().whereType<File>()) {
      if (!file.path.endsWith('.swift')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!line.contains('uiImage(')) continue;
        // Предел бывает на той же строке или на следующей — вызов переносят.
        final tail = i + 1 < lines.length ? lines[i + 1] : '';
        if (line.contains('maxSide') || tail.contains('maxSide')) continue;
        offenders.add('${file.path}:${i + 1}');
      }
    }

    expect(offenders, isEmpty,
        reason: 'без своего предела картинка разжимается в 1200 точек и '
            'убивает расширение: ${offenders.join(', ')}');
  });
}
