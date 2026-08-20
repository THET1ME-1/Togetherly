import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/draw_stroke.dart';
import 'package:love_app/utils/quick_shape.dart';

/// Точки вдоль отрезка, как их набирает палец.
List<Offset> _segment(Offset a, Offset b, int steps, {double jitter = 0}) {
  final out = <Offset>[];
  for (var i = 0; i <= steps; i++) {
    final t = i / steps;
    final p = Offset.lerp(a, b, t)!;
    final wobble = jitter == 0 ? 0.0 : (i.isEven ? jitter : -jitter);
    out.add(Offset(p.dx, p.dy + wobble));
  }
  return out;
}

void main() {
  group('ровные фигуры', () {
    test('дрожащая прямая становится линией', () {
      final shape = recognizeQuickShape(
        _segment(const Offset(20, 100), const Offset(220, 104), 40, jitter: 2),
      );
      expect(shape?.type, DrawShapeType.line);
      expect((shape!.start - const Offset(20, 100)).distance, lessThan(12));
      expect((shape.end - const Offset(220, 104)).distance, lessThan(12));
    });

    test('круг от руки становится овалом', () {
      final pts = <Offset>[];
      for (var i = 0; i <= 48; i++) {
        final a = i / 48 * 2 * math.pi;
        final r = 80 + (i.isEven ? 3 : -3);
        pts.add(Offset(150 + r * math.cos(a), 150 + r * math.sin(a)));
      }
      expect(recognizeQuickShape(pts)?.type, DrawShapeType.circle);
    });

    test('четыре стороны становятся прямоугольником', () {
      final pts = <Offset>[
        ..._segment(const Offset(40, 40), const Offset(240, 44), 12, jitter: 2),
        ..._segment(const Offset(240, 44), const Offset(236, 160), 12),
        ..._segment(const Offset(236, 160), const Offset(44, 156), 12),
        ..._segment(const Offset(44, 156), const Offset(40, 42), 12),
      ];
      final shape = recognizeQuickShape(pts);
      expect(shape?.type, DrawShapeType.rect);
      expect(shape!.start.dx, lessThan(shape.end.dx));
      expect(shape.start.dy, lessThan(shape.end.dy));
    });

    test('три стороны становятся треугольником', () {
      final pts = <Offset>[
        ..._segment(const Offset(140, 30), const Offset(240, 190), 16, jitter: 2),
        ..._segment(const Offset(240, 190), const Offset(40, 190), 16),
        ..._segment(const Offset(40, 190), const Offset(140, 30), 16),
      ];
      expect(recognizeQuickShape(pts)?.type, DrawShapeType.triangle);
    });

    test('треугольник вершиной вниз рисуется вершиной вниз', () {
      final pts = <Offset>[
        ..._segment(const Offset(40, 40), const Offset(240, 40), 16, jitter: 2),
        ..._segment(const Offset(240, 40), const Offset(140, 200), 16),
        ..._segment(const Offset(140, 200), const Offset(40, 40), 16),
      ];
      final shape = recognizeQuickShape(pts);
      expect(shape?.type, DrawShapeType.triangle);
      expect(shape!.start.dy, greaterThan(shape.end.dy));
    });

    test('кривой круг пальцем остаётся кругом', () {
      // Радиус гуляет, начало и конец не сходятся, вверху угол — так круг
      // выходит на живом холсте.
      final pts = <Offset>[];
      for (var i = 0; i <= 42; i++) {
        final a = (i / 44) * 2 * math.pi - math.pi / 2;
        final r = 100 + math.sin(i * 1.7) * 11 + (i > 38 ? 9 : 0);
        pts.add(Offset(160 + r * math.cos(a), 170 + r * math.sin(a) * 0.94));
      }
      expect(recognizeQuickShape(pts)?.type, DrawShapeType.circle);
    });

    test('вытянутый овал остаётся овалом, а не прямоугольником', () {
      // Ровно тот случай из жалобы: рисуешь овал, получаешь прямоугольник.
      final pts = <Offset>[];
      for (var i = 0; i <= 44; i++) {
        final a = (i / 44) * 2 * math.pi;
        pts.add(Offset(
          170 + 130 * math.cos(a) + math.sin(i * 2.3) * 5,
          150 + 62 * math.sin(a) + math.cos(i * 1.9) * 5,
        ));
      }
      expect(recognizeQuickShape(pts)?.type, DrawShapeType.circle);
    });

    test('квадрат пальцем не превращается в круг', () {
      final pts = <Offset>[
        ..._segment(const Offset(50, 46), const Offset(210, 50), 14, jitter: 3),
        ..._segment(const Offset(210, 50), const Offset(206, 200), 14, jitter: 3),
        ..._segment(const Offset(206, 200), const Offset(48, 196), 14, jitter: 3),
        ..._segment(const Offset(48, 196), const Offset(50, 52), 14, jitter: 3),
      ];
      expect(recognizeQuickShape(pts)?.type, DrawShapeType.rect);
    });

    test('скруглённый прямоугольник остаётся прямоугольником', () {
      // У него углы заполнены, у овала — пусты; на этом их и различаем.
      final pts = <Offset>[
        ..._segment(const Offset(70, 40), const Offset(210, 40), 10, jitter: 2),
        ..._segment(const Offset(230, 60), const Offset(230, 170), 8, jitter: 2),
        ..._segment(const Offset(210, 190), const Offset(70, 190), 10, jitter: 2),
        ..._segment(const Offset(50, 170), const Offset(50, 60), 8, jitter: 2),
      ];
      expect(recognizeQuickShape(pts)?.type, DrawShapeType.rect);
    });

    test('овал с прямыми боками не становится прямоугольником', () {
      final pts = <Offset>[];
      for (var i = 0; i <= 40; i++) {
        final a = (i / 40) * 2 * math.pi;
        // Бока чуть прямее, чем у эллипса: так рисуют овал пальцем.
        final c = math.cos(a), s2 = math.sin(a);
        pts.add(Offset(
          180 + 120 * c.sign * math.pow(c.abs(), 0.82).toDouble(),
          150 + 70 * s2,
        ));
      }
      expect(recognizeQuickShape(pts)?.type, DrawShapeType.circle);
    });

    test('каракули ничем не становятся', () {
      final pts = <Offset>[
        ..._segment(const Offset(20, 200), const Offset(70, 40), 10),
        ..._segment(const Offset(70, 40), const Offset(120, 200), 10),
        ..._segment(const Offset(120, 200), const Offset(170, 40), 10),
        ..._segment(const Offset(170, 40), const Offset(220, 200), 10),
      ];
      expect(recognizeQuickShape(pts), isNull);
    });

    test('короткий мазок не превращается', () {
      expect(
        recognizeQuickShape(_segment(const Offset(10, 10), const Offset(28, 10), 10)),
        isNull,
      );
    });

    test('пары точек мало для разбора', () {
      expect(
        recognizeQuickShape(const [Offset(0, 0), Offset(200, 0)]),
        isNull,
      );
    });
  });
}
