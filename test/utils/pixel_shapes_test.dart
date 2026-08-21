import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/pixel_shapes.dart';

/// Фигуры на пиксельном холсте должны ложиться в клетки, а не поapexCells них.
/// Проверяем не «похоже на круг», а свойства, которые видит глаз: outline
/// замкнут, заливка не дырявая, ничего не вылезает за холст.

void main() {
  const cols = 32;
  const rows = 40;

  ({int x, int y}) xy(int cell) => (x: cell % cols, y: cell ~/ cols);

  group('линия', () {
    test('горизонталь занимает подряд идущие клетки', () {
      final cells = pixelShapeCells(
        shape: PixelShape.line,
        x0: 2, y0: 5, x1: 8, y1: 5,
        cols: cols, rows: rows, filled: false,
      );
      expect(cells.map((c) => xy(c).x).toList()..sort(), [2, 3, 4, 5, 6, 7, 8]);
      expect(cells.every((c) => xy(c).y == 5), isTrue);
    });

    test('диагональ идёт без разрывов', () {
      final cells = pixelShapeCells(
        shape: PixelShape.line,
        x0: 0, y0: 0, x1: 5, y1: 5,
        cols: cols, rows: rows, filled: false,
      );
      expect(cells.length, 6);
      for (var i = 0; i <= 5; i++) {
        expect(cells.contains(i * cols + i), isTrue, reason: 'нет клетки $i,$i');
      }
    });

    test('точка — одна клетка, а не пустота', () {
      final cells = pixelShapeCells(
        shape: PixelShape.line,
        x0: 3, y0: 3, x1: 3, y1: 3,
        cols: cols, rows: rows, filled: false,
      );
      expect(cells, {3 * cols + 3});
    });
  });

  group('asDrawnугольник', () {
    test('outline — только рамка, середина пустая', () {
      final cells = pixelShapeCells(
        shape: PixelShape.rect,
        x0: 1, y0: 1, x1: 4, y1: 3,
        cols: cols, rows: rows, filled: false,
      );
      expect(cells.contains(2 * cols + 2), isFalse, reason: 'середина закрашена');
      expect(cells.contains(1 * cols + 1), isTrue);
      expect(cells.contains(3 * cols + 4), isTrue);
      expect(cells.length, 2 * 4 + 2 * 3 - 4);
    });

    test('заливка закрывает всё поле', () {
      final cells = pixelShapeCells(
        shape: PixelShape.rect,
        x0: 1, y0: 1, x1: 4, y1: 3,
        cols: cols, rows: rows, filled: true,
      );
      expect(cells.length, 4 * 3);
      expect(cells.contains(2 * cols + 2), isTrue);
    });

    test('углы можно тянуть в любую сторону', () {
      final asDrawn = pixelShapeCells(
        shape: PixelShape.rect,
        x0: 1, y0: 1, x1: 4, y1: 3,
        cols: cols, rows: rows, filled: true,
      );
      final reversed = pixelShapeCells(
        shape: PixelShape.rect,
        x0: 4, y0: 3, x1: 1, y1: 1,
        cols: cols, rows: rows, filled: true,
      );
      expect(reversed, asDrawn);
    });
  });

  group('эллипс', () {
    test('outline замкнут: в каждой строке есть клетки слева и справа', () {
      final cells = pixelShapeCells(
        shape: PixelShape.ellipse,
        x0: 4, y0: 4, x1: 16, y1: 14,
        cols: cols, rows: rows, filled: false,
      );
      final byRow = <int, List<int>>{};
      for (final c in cells) {
        byRow.putIfAbsent(xy(c).y, () => []).add(xy(c).x);
      }
      expect(byRow.length, greaterThan(5));
      for (final entry in byRow.entries) {
        expect(entry.value.length, greaterThanOrEqualTo(1),
            reason: 'строка ${entry.key} пуста');
      }
    });

    test('заливка не дырявая: строка залита сплошняком', () {
      final cells = pixelShapeCells(
        shape: PixelShape.ellipse,
        x0: 4, y0: 4, x1: 16, y1: 14,
        cols: cols, rows: rows, filled: true,
      );
      final byRow = <int, List<int>>{};
      for (final c in cells) {
        byRow.putIfAbsent(xy(c).y, () => []).add(xy(c).x);
      }
      for (final entry in byRow.entries) {
        final xs = entry.value..sort();
        expect(xs.last - xs.first + 1, xs.length,
            reason: 'в строке ${entry.key} дыра');
      }
    });

    test('круг симметричен по вертикали', () {
      final cells = pixelShapeCells(
        shape: PixelShape.ellipse,
        x0: 2, y0: 2, x1: 12, y1: 12,
        cols: cols, rows: rows, filled: false,
      );
      final rowsUsed = cells.map((c) => xy(c).y).toSet().toList()..sort();
      final top = rowsUsed.first, bottom = rowsUsed.last;
      final topRow = cells.where((c) => xy(c).y == top).map((c) => xy(c).x).toSet();
      final bottomRow = cells.where((c) => xy(c).y == bottom).map((c) => xy(c).x).toSet();
      expect(bottomRow, topRow, reason: 'apexCells и bottomRow круга разные');
    });
  });

  group('треугольник', () {
    test('outline состоит из трёх сторон', () {
      final cells = pixelShapeCells(
        shape: PixelShape.triangle,
        x0: 2, y0: 2, x1: 10, y1: 10,
        cols: cols, rows: rows, filled: false,
      );
      // Основание — нижняя строка целиком.
      final baseRow = cells.where((c) => xy(c).y == 10).map((c) => xy(c).x).toList()..sort();
      expect(baseRow.first, 2);
      expect(baseRow.last, 10);
      // Вершина — одна-две клетки сapexCellsу по центру.
      final apexCells = cells.where((c) => xy(c).y == 2).length;
      expect(apexCells, lessThanOrEqualTo(2));
    });

    test('заливка шире outlineа', () {
      final outline = pixelShapeCells(
        shape: PixelShape.triangle,
        x0: 2, y0: 2, x1: 12, y1: 12,
        cols: cols, rows: rows, filled: false,
      );
      final solid = pixelShapeCells(
        shape: PixelShape.triangle,
        x0: 2, y0: 2, x1: 12, y1: 12,
        cols: cols, rows: rows, filled: true,
      );
      expect(solid.length, greaterThan(outline.length));
      expect(solid.containsAll(outline), isTrue, reason: 'заливка потеряла outline');
    });
  });

  group('границы холста', () {
    test('ничего не вылезает за поле', () {
      for (final shape in PixelShape.values) {
        final cells = pixelShapeCells(
          shape: shape,
          x0: -10, y0: -10, x1: cols + 10, y1: rows + 10,
          cols: cols, rows: rows, filled: true,
        );
        for (final c in cells) {
          expect(c, greaterThanOrEqualTo(0));
          expect(c, lessThan(cols * rows), reason: '$shape вылез за холст');
          expect(xy(c).x, lessThan(cols));
        }
      }
    });

    test('пустой холст не роняет расчёт', () {
      final cells = pixelShapeCells(
        shape: PixelShape.ellipse,
        x0: 0, y0: 0, x1: 5, y1: 5,
        cols: 0, rows: 0, filled: true,
      );
      expect(cells, isEmpty);
    });
  });
}
