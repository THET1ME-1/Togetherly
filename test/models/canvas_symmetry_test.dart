import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/canvas_symmetry.dart';
import 'package:love_app/models/draw_stroke.dart';

void main() {
  group('симметрия холста', () {
    const line = [DrawPoint(0.2, 0.3), DrawPoint(0.4, 0.35)];

    test('без симметрии копий нет', () {
      expect(mirrorStroke(line, SymmetryMode.none), isEmpty);
    });

    test('вертикальная ось отражает вбок', () {
      final copies = mirrorStroke(line, SymmetryMode.vertical);
      expect(copies, hasLength(1));
      expect(copies.first[0].x, closeTo(0.8, 1e-9));
      expect(copies.first[0].y, closeTo(0.3, 1e-9));
      expect(copies.first[1].x, closeTo(0.6, 1e-9));
    });

    test('горизонтальная ось отражает вниз', () {
      final copies = mirrorStroke(line, SymmetryMode.horizontal);
      expect(copies, hasLength(1));
      expect(copies.first[0].x, closeTo(0.2, 1e-9));
      expect(copies.first[0].y, closeTo(0.7, 1e-9));
    });

    test('четыре оси дают три копии', () {
      expect(mirrorStroke(line, SymmetryMode.quad), hasLength(3));
    });

    test('лучевая симметрия даёт копии по числу секторов', () {
      final copies = mirrorStroke(line, SymmetryMode.radial, sectors: 6);
      expect(copies, hasLength(5));
    });

    test('поворот на полный круг возвращает точку на место', () {
      final copies = mirrorStroke(
        const [DrawPoint(0.75, 0.5)],
        SymmetryMode.radial,
        sectors: 2,
      );
      expect(copies.first.first.x, closeTo(0.25, 1e-6));
      expect(copies.first.first.y, closeTo(0.5, 1e-6));
    });

    test('на вытянутом листе луч не растягивает рисунок', () {
      // Точка на 0.1 выше центра при листе 2:1 после поворота на 90°
      // должна отойти от центра на ту же длину в пикселях, то есть на
      // половину доли по ширине.
      final copies = mirrorStroke(
        const [DrawPoint(0.5, 0.4)],
        SymmetryMode.radial,
        sectors: 4,
        aspect: 2,
      );
      final p = copies.first.first;
      expect(p.y, closeTo(0.5, 1e-6));
      expect(p.x, closeTo(0.55, 1e-6));
    });

    test('копии остаются на листе', () {
      final copies = mirrorStroke(
        const [DrawPoint(0.99, 0.99)],
        SymmetryMode.radial,
        sectors: 3,
      );
      for (final copy in copies) {
        for (final p in copy) {
          expect(p.x, inInclusiveRange(0, 1));
          expect(p.y, inInclusiveRange(0, 1));
        }
      }
    });
  });
}
