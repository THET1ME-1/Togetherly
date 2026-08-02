import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сторож размера пиксельного маскота.
///
/// `PixelMascotView` рисует кадр в квадрат заданной стороны, и бесконечность
/// туда отдавать нельзя: 1 августа лист действий в галерее просил превью 48,
/// а код всё равно лез в `LayoutBuilder`. В строке без ограничений по ширине
/// оттуда приходит `Infinity` — лист раздувался во весь экран и выглядел
/// пустым, хотя кнопки в нём были.
///
/// Тест сканирует исходники: каждое место, где сторона берётся у родителя,
/// обязано проверить её на конечность.
void main() {
  test('Размер маскота никогда не приходит бесконечным', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final text = entity.readAsStringSync();
      if (!text.contains('PixelMascotView')) continue;

      // Собираем строки, где сторона берётся у родителя.
      final lines = text.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('shortestSide')) continue;
        // Проверка на конечность может стоять не вплотную: сторону считают
        // отдельной строкой, а подставляют её через несколько аргументов.
        // Окно с запасом — у вызова бывает и десяток аргументов с
        // комментариями между ними.
        final around = lines
            .sublist((i - 3).clamp(0, lines.length), (i + 12).clamp(0, lines.length))
            .join('\n');
        if (!around.contains('isFinite')) {
          offenders.add('${entity.path}:${i + 1}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Сторона маскота берётся у родителя без проверки isFinite: '
          '${offenders.join(', ')}',
    );
  });
}
