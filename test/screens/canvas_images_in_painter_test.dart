import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сторож порядка картинок на холсте.
///
/// Заливка ведром и вставленное фото — это штрихи с картинкой, и до 25.08.2026
/// холст рисовал их отдельными виджетами ПОВЕРХ `CustomPaint`, а painter
/// выбрасывал их фильтром. Из-за этого ни `orderIndex`, ни слой на них не
/// действовали: залитое пятно лежало сверху всего, что нарисовано позже, а
/// ластик его не брал. Жалоба звучала как «слои не работают».
///
/// Вернуть виджеты — значит вернуть тот же баг, поэтому здесь стоит проверка по
/// исходнику: картинки рисует тот же painter, что и мазки.
void main() {
  final source = File('lib/screens/draw_screen.dart').readAsStringSync();

  test('painter не выбрасывает картинки из списка штрихов', () {
    expect(
      source.contains('.list.where((s) => !s.isImageStroke)'),
      isFalse,
      reason: 'картинки должны идти общим списком со штрихами, в своём порядке',
    );
    expect(
      source.contains('final strokeList = snapshot.list;'),
      isTrue,
      reason: 'painter рисует весь состав подряд',
    );
  });

  test('картинки не рисуются виджетами поверх холста', () {
    for (final widget in ['Image.file(', 'StorageImage(']) {
      expect(
        source.contains(widget),
        isFalse,
        reason: '$widget поверх CustomPaint снова положит заливку сверху всего',
      );
    }
  });

  test('painter получает кэш растров', () {
    expect(source.contains('images: _images'), isTrue);
    expect(source.contains('imageOf: _imageOf'), isTrue);
  });
}
