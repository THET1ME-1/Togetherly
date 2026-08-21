import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/draw_stroke.dart';
import 'package:love_app/models/stroke_transform.dart';

/// Векторная правка нарисованного: выделить мазок или фигуру и двигать её,
/// крутить, растягивать. Точки штриха лежат в долях 0..1 от листа, поэтому
/// считать всё это «как есть» нельзя — на неквадратном холсте поворот сплющит
/// круг. Здесь и проверяется, что пересчёт идёт через точки холста.

const _canvas = Size(400, 500); // намеренно НЕ квадрат

DrawStroke _line() => const DrawStroke(
      id: 's1',
      userId: 'u1',
      colorValue: 0xFF000000,
      strokeWidth: 4,
      orderIndex: 0,
      points: [DrawPoint(0.2, 0.2), DrawPoint(0.6, 0.2)],
    );

DrawStroke _circle() => const DrawStroke(
      id: 's2',
      userId: 'u1',
      colorValue: 0xFF000000,
      strokeWidth: 4,
      orderIndex: 1,
      shapeType: DrawShapeType.circle,
      points: [DrawPoint(0.2, 0.2), DrawPoint(0.6, 0.6)],
    );

void main() {
  group('габарит', () {
    test('прямоугольник вокруг мазка', () {
      final r = strokeBounds(_line(), _canvas);
      expect(r.left, closeTo(80, 0.01));
      expect(r.right, closeTo(240, 0.01));
      expect(r.top, closeTo(100, 0.01));
    });

    test('у точки габарит не нулевой: за неё должно быть чем взяться', () {
      final dot = DrawStroke(
        id: 'd',
        userId: 'u',
        colorValue: 0,
        strokeWidth: 10,
        orderIndex: 0,
        points: const [DrawPoint(0.5, 0.5)],
      );
      final r = strokeBounds(dot, _canvas);
      expect(r.width, greaterThan(0));
      expect(r.height, greaterThan(0));
    });
  });

  group('что под пальцем', () {
    test('палец на линии — попал', () {
      final hit = strokeAtPoint([_line()], const Offset(160, 100), _canvas);
      expect(hit?.id, 's1');
    });

    test('палец мимо — никого', () {
      final hit = strokeAtPoint([_line()], const Offset(160, 300), _canvas);
      expect(hit, isNull);
    });

    test('сверху лежащий выигрывает: рисовали его позже', () {
      final under = _line();
      final over = DrawStroke(
        id: 'top',
        userId: 'u',
        colorValue: 0,
        strokeWidth: 4,
        orderIndex: 5,
        points: const [DrawPoint(0.3, 0.19), DrawPoint(0.5, 0.21)],
      );
      final hit = strokeAtPoint([under, over], const Offset(160, 100), _canvas);
      expect(hit?.id, 'top');
    });

    test('фигуру берём и за середину — иначе в неё не попасть пальцем', () {
      final hit = strokeAtPoint([_circle()], const Offset(160, 200), _canvas);
      expect(hit?.id, 's2');
    });
  });

  group('перемещение', () {
    test('сдвиг переносит все точки', () {
      final moved = moveStroke(_line(), const Offset(40, 50), _canvas);
      expect(moved.points.first.x, closeTo(0.3, 0.001));
      expect(moved.points.first.y, closeTo(0.3, 0.001));
      expect(moved.points.last.x, closeTo(0.7, 0.001));
    });

    test('за край не уводим: рисунок нельзя потерять за листом', () {
      final moved = moveStroke(_line(), const Offset(10000, 10000), _canvas);
      for (final p in moved.points) {
        expect(p.x, lessThanOrEqualTo(1.0));
        expect(p.y, lessThanOrEqualTo(1.0));
        expect(p.x, greaterThanOrEqualTo(0.0));
      }
    });
  });

  group('масштаб', () {
    test('вдвое крупнее — вдвое шире габарит', () {
      final before = strokeBounds(_line(), _canvas);
      final after = strokeBounds(
        scaleStroke(_line(), 2.0, _canvas),
        _canvas,
      );
      expect(after.width, closeTo(before.width * 2, 0.5));
    });

    test('центр остаётся на месте', () {
      final before = strokeBounds(_line(), _canvas).center;
      final after = strokeBounds(scaleStroke(_line(), 2.0, _canvas), _canvas)
          .center;
      expect(after.dx, closeTo(before.dx, 0.5));
      expect(after.dy, closeTo(before.dy, 0.5));
    });

    test('в ноль не схлопываем: исчезнувшую фигуру не вернуть', () {
      final tiny = scaleStroke(_line(), 0.0001, _canvas);
      expect(strokeBounds(tiny, _canvas).width, greaterThan(0.5));
    });
  });

  group('поворот', () {
    test('на девяносто градусов горизонталь встаёт вертикалью', () {
      final turned = rotateStroke(_line(), math.pi / 2, _canvas);
      final r = strokeBounds(turned, _canvas);
      expect(r.height, greaterThan(r.width),
          reason: 'линия осталась горизонтальной');
    });

    test('поворот не сплющивает: длина сохраняется на неквадратном холсте', () {
      final before = strokeBounds(_line(), _canvas).width;
      final turned = rotateStroke(_line(), math.pi / 2, _canvas);
      final after = strokeBounds(turned, _canvas).height;
      expect(after, closeTo(before, 1.0));
    });

    test('полный оборот возвращает как было', () {
      final turned = rotateStroke(_line(), math.pi * 2, _canvas);
      for (var i = 0; i < turned.points.length; i++) {
        expect(turned.points[i].x, closeTo(_line().points[i].x, 0.002));
        expect(turned.points[i].y, closeTo(_line().points[i].y, 0.002));
      }
    });
  });

  group('растягивание за угол', () {
    test('тянем правый край — левый стоит', () {
      final before = strokeBounds(_line(), _canvas);
      final stretched = stretchStroke(
        _line(),
        handle: StrokeHandle.right,
        delta: const Offset(80, 0),
        canvas: _canvas,
      );
      final after = strokeBounds(stretched, _canvas);
      expect(after.left, closeTo(before.left, 0.5));
      expect(after.right, closeTo(before.right + 80, 1.0));
    });

    test('тянем низ — верх стоит', () {
      final before = strokeBounds(_circle(), _canvas);
      final stretched = stretchStroke(
        _circle(),
        handle: StrokeHandle.bottom,
        delta: const Offset(0, 60),
        canvas: _canvas,
      );
      final after = strokeBounds(stretched, _canvas);
      expect(after.top, closeTo(before.top, 0.5));
      expect(after.bottom, closeTo(before.bottom + 60, 1.0));
    });

    test('через себя не выворачиваем', () {
      final stretched = stretchStroke(
        _circle(),
        handle: StrokeHandle.right,
        delta: const Offset(-10000, 0),
        canvas: _canvas,
      );
      expect(strokeBounds(stretched, _canvas).width, greaterThan(0.5));
    });
  });

  group('замена точек', () {
    test('всё, кроме формы, остаётся прежним — это нужно отмене правки', () {
      const before = [DrawPoint(0.1, 0.1), DrawPoint(0.9, 0.9)];
      final same = strokeWithPoints(_circle(), before);
      expect(same.points, before);
      expect(same.id, _circle().id);
      expect(same.colorValue, _circle().colorValue);
      expect(same.strokeWidth, _circle().strokeWidth);
      expect(same.shapeType, _circle().shapeType);
      expect(same.orderIndex, _circle().orderIndex);
    });
  });
}
