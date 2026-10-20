import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/draw_replay.dart';
import 'package:love_app/models/draw_stroke.dart';

DrawStroke _stroke(String id, int points) => DrawStroke(
      id: id,
      userId: 'u',
      colorValue: 0xFF000000,
      strokeWidth: 4,
      points: List.generate(points, (i) => DrawPoint(i / 10, 0.5)),
      isEraser: false,
      isFilledShape: false,
      orderIndex: int.parse(id),
    );

void main() {
  final all = [_stroke('1', 5), _stroke('2', 3), _stroke('3', 4)];

  group('повтор рисования', () {
    test('в начале холст пуст', () {
      expect(strokesUpTo(all, 0), isEmpty);
    });

    test('целиком показанный штрих остаётся целым', () {
      final shown = strokesUpTo(all, 5);
      expect(shown, hasLength(1));
      expect(shown.first.points, hasLength(5));
    });

    test('текущий штрих дорисовывается по точкам', () {
      final shown = strokesUpTo(all, 7);
      expect(shown, hasLength(2));
      expect(shown.last.points, hasLength(2));
      expect(shown.last.id, '2');
    });

    test('к концу показаны все штрихи', () {
      expect(strokesUpTo(all, 12), hasLength(3));
      expect(strokesUpTo(all, 999), hasLength(3));
    });

    test('одинокая точка штриха не показывается огрызком', () {
      // Первая точка мазка ещё не линия: показываем со второй, иначе в начале
      // каждого штриха вспыхивает точка.
      expect(strokesUpTo(all, 6), hasLength(1));
    });

    test('фигура появляется целиком, а не растёт из угла', () {
      final shape = DrawStroke(
        id: '9',
        userId: 'u',
        colorValue: 0xFF000000,
        strokeWidth: 4,
        points: const [DrawPoint(0.1, 0.1), DrawPoint(0.8, 0.8)],
        isEraser: false,
        isFilledShape: false,
        shapeType: DrawShapeType.rect,
        orderIndex: 9,
      );
      final shown = strokesUpTo([shape], 1);
      expect(shown, hasLength(1));
      expect(shown.first.points, hasLength(2));
    });

    test('длительность растёт с числом точек, но с потолком', () {
      final short = replayDuration(60);
      final long = replayDuration(60000);
      expect(short.inSeconds, lessThan(long.inSeconds));
      expect(long.inSeconds, lessThanOrEqualTo(60));
      expect(short.inMilliseconds, greaterThanOrEqualTo(1500));
    });
  });

  group('повтор со слоями и заливкой (20.10.2026)', () {
    DrawStroke layered(String id, int order, int layer) => DrawStroke(
          id: id,
          userId: 'u',
          colorValue: 0xFF000000,
          strokeWidth: 4,
          points: const [DrawPoint(0, 0), DrawPoint(1, 1)],
          orderIndex: order,
          layer: layer,
        );
    DrawStroke fill(String id, int order) => DrawStroke(
          id: id,
          userId: 'u',
          colorValue: 0xFF000000,
          strokeWidth: 0,
          points: const [],
          orderIndex: order,
          imageUrl: 'pb://media/x/fill.png',
        );

    test('проигрывается в порядке рисования, а не по слоям', () {
      // Холст отдаёт штрихи по слоям: весь нижний, потом весь верхний.
      final canvasOrder = [layered('b', 1, 0), layered('a', 0, 1)];
      expect(replayOrder(canvasOrder).map((s) => s.id), ['a', 'b']);
    });

    test('показанное складывается по слоям, как на холсте', () {
      final shown = [layered('a', 0, 1), layered('b', 1, 0)];
      expect(byLayer(shown).map((s) => s.id), ['b', 'a']);
    });

    test('заливка появляется в своё время, а не в начале', () {
      final all = [layered('a', 0, 0), fill('f', 1)];
      expect(strokesUpTo(all, 1).map((s) => s.id), isEmpty);
      expect(strokesUpTo(all, 2).map((s) => s.id), ['a']);
      expect(strokesUpTo(all, 3).map((s) => s.id), ['a', 'f']);
      expect(totalReplayPoints(all), 3);
    });
  });
}
