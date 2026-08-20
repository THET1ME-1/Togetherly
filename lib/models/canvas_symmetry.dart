import 'dart:math' as math;

import 'draw_stroke.dart';

/// Симметрия холста: мазок повторяется зеркалами или лучами, как в Ibis Paint.
///
/// Копии считаются на устройстве автора и уходят в базу обычными штрихами —
/// отдельного поля у записи нет, и партнёр рисует их, ничего не зная про
/// режим. Живой мазок при этом едет один: копии появляются при отпускании
/// пальца, зато канал не пухнет в шесть раз.
enum SymmetryMode { none, vertical, horizontal, quad, radial }

/// Копии мазка БЕЗ оригинала. Точки — доли листа, как во всём холсте.
///
/// [aspect] — отношение ширины листа к высоте. Оно нужно лучевой симметрии:
/// в долях вытянутый лист превращает поворот в перекос, поэтому крутим в
/// единицах высоты и возвращаемся обратно.
List<List<DrawPoint>> mirrorStroke(
  List<DrawPoint> points,
  SymmetryMode mode, {
  int sectors = 6,
  double aspect = 1,
}) {
  if (points.isEmpty) return const [];
  switch (mode) {
    case SymmetryMode.none:
      return const [];
    case SymmetryMode.vertical:
      return [_map(points, (p) => DrawPoint(1 - p.x, p.y))];
    case SymmetryMode.horizontal:
      return [_map(points, (p) => DrawPoint(p.x, 1 - p.y))];
    case SymmetryMode.quad:
      return [
        _map(points, (p) => DrawPoint(1 - p.x, p.y)),
        _map(points, (p) => DrawPoint(p.x, 1 - p.y)),
        _map(points, (p) => DrawPoint(1 - p.x, 1 - p.y)),
      ];
    case SymmetryMode.radial:
      final count = sectors.clamp(2, 16);
      return [
        for (var k = 1; k < count; k++)
          _map(points, (p) => _rotate(p, 2 * math.pi * k / count, aspect)),
      ];
  }
}

DrawPoint _rotate(DrawPoint p, double angle, double aspect) {
  final scale = aspect <= 0 ? 1.0 : aspect;
  final x = (p.x - 0.5) * scale;
  final y = p.y - 0.5;
  final cos = math.cos(angle), sin = math.sin(angle);
  return DrawPoint(
    0.5 + (x * cos - y * sin) / scale,
    0.5 + (x * sin + y * cos),
  );
}

List<DrawPoint> _map(
  List<DrawPoint> points,
  DrawPoint Function(DrawPoint) f,
) =>
    [
      for (final p in points)
        () {
          final q = f(p);
          // За краем листа точку держать незачем: холст всё равно обрежет её
          // при отрисовке, а в базу уехало бы значение вне 0…1.
          return DrawPoint(q.x.clamp(0.0, 1.0), q.y.clamp(0.0, 1.0));
        }(),
    ];
