import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/stroke_stabilizer.dart';

void main() {
  group('стабилизатор линии', () {
    test('первая точка мазка идёт как есть', () {
      final s = StrokeStabilizer(strength: 0.5);
      expect(s.begin(const Offset(10, 20)), const Offset(10, 20));
    });

    test('сглаженная точка отстаёт от пальца', () {
      final s = StrokeStabilizer(strength: 0.5);
      s.begin(Offset.zero);
      expect(s.update(const Offset(10, 0)), const Offset(5, 0));
    });

    test('без силы точки проходят нетронутыми', () {
      final s = StrokeStabilizer(strength: 0);
      s.begin(Offset.zero);
      expect(s.update(const Offset(10, 0)), const Offset(10, 0));
      expect(s.update(const Offset(10.1, 0)), const Offset(10.1, 0));
    });

    test('дрожание меньше шага новой точки не даёт', () {
      final s = StrokeStabilizer(strength: 0.5, minStep: 1);
      s.begin(Offset.zero);
      expect(s.update(const Offset(0.2, 0)), isNull);
      expect(s.update(const Offset(0.3, 0)), isNull);
    });

    test('хвост дотягивает линию до пальца', () {
      final s = StrokeStabilizer(strength: 0.6, minStep: 0.5);
      s.begin(Offset.zero);
      s.update(const Offset(40, 0));
      final tail = s.finish();
      expect(tail, isNotEmpty);
      expect((tail.last - const Offset(40, 0)).distance, lessThan(1));
    });

    test('стоящий палец хвоста не оставляет', () {
      final s = StrokeStabilizer(strength: 0.5, minStep: 0.5);
      s.begin(const Offset(5, 5));
      expect(s.finish(), isEmpty);
    });

    // Разброс меряем на установившемся ходу: первые точки фильтр ещё
    // догоняет, и стартовая по определению равна сырой.
    test('зигзаг дрожащей руки выпрямляется', () {
      double wobble(List<Offset> pts) {
        var worst = 0.0;
        for (final p in pts.skip(pts.length - 20)) {
          if (p.dy.abs() > worst) worst = p.dy.abs();
        }
        return worst;
      }

      final raw = <Offset>[];
      for (var i = 0; i <= 40; i++) {
        raw.add(Offset(i * 2, i.isEven ? 2 : -2));
      }

      final s = StrokeStabilizer(strength: 0.7, minStep: 0);
      s.begin(raw.first);
      final smoothed = <Offset>[];
      for (final p in raw.skip(1)) {
        final out = s.update(p);
        if (out != null) smoothed.add(out);
      }

      expect(wobble(smoothed), lessThan(wobble(raw) / 2));
    });

    test('линия остаётся той же длины: хвост не заворачивает назад', () {
      final s = StrokeStabilizer(strength: 0.7, minStep: 0.5);
      s.begin(Offset.zero);
      for (var i = 1; i <= 20; i++) {
        s.update(Offset(i * 5, 0));
      }
      final tail = s.finish();
      for (var i = 1; i < tail.length; i++) {
        expect(tail[i].dx, greaterThanOrEqualTo(tail[i - 1].dx));
      }
    });
  });
}
