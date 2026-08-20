import 'dart:math' as math;
import 'dart:ui';

import '../models/draw_stroke.dart';

/// Ровные фигуры из кривой руки — приём Procreate: нарисовал круг, задержал
/// палец, и линия схлопывается в идеальную форму.
///
/// Разбор чисто геометрический и без состояния: на вход точки мазка в
/// экранных координатах, на выход — фигура и прямоугольник, в котором её
/// рисовать. Пары `start`/`end` хватает, потому что холст рисует фигуры
/// ровно по двум точкам (`_drawShape`), и треугольник ставит вершину на
/// сторону `start`.
class QuickShape {
  const QuickShape(this.type, this.start, this.end);

  final DrawShapeType type;
  final Offset start;
  final Offset end;
}

/// Ищет фигуру в мазке. `null` — рука вела что-то своё, трогать не надо.
///
/// [minLength] — короче этого пути мазок считается точкой или чёрточкой,
/// [tolerance] — какую долю от размера фигуры прощаем среднему отклонению.
QuickShape? recognizeQuickShape(
  List<Offset> points, {
  double minLength = 40,
  double tolerance = 0.14,
}) {
  if (points.length < 8) return null;

  var pathLength = 0.0;
  for (var i = 1; i < points.length; i++) {
    pathLength += (points[i] - points[i - 1]).distance;
  }
  if (pathLength < minLength) return null;

  var left = points.first.dx, right = points.first.dx;
  var top = points.first.dy, bottom = points.first.dy;
  for (final p in points) {
    left = math.min(left, p.dx);
    right = math.max(right, p.dx);
    top = math.min(top, p.dy);
    bottom = math.max(bottom, p.dy);
  }
  final size = math.max(right - left, bottom - top);
  if (size < minLength / 2) return null;

  final first = points.first;
  final last = points.last;
  final closed = (last - first).distance <= size * 0.35;

  if (!closed) {
    // Незамкнутый мазок бывает только прямой: дуга, галка и всё остальное
    // остаются собой.
    final chord = (last - first).distance;
    if (chord < minLength) return null;
    var worst = 0.0;
    for (final p in points) {
      worst = math.max(worst, _distanceToSegment(p, first, last));
    }
    if (worst <= chord * tolerance) return QuickShape(DrawShapeType.line, first, last);
    return null;
  }

  final rect = Rect.fromLTRB(left, top, right, bottom);
  final candidates = <(DrawShapeType, Offset, Offset, double)>[
    (
      DrawShapeType.rect,
      rect.topLeft,
      rect.bottomRight,
      _meanError(points, (p) => _distanceToRect(p, rect)),
    ),
    (
      DrawShapeType.circle,
      rect.topLeft,
      rect.bottomRight,
      _meanError(points, (p) => _distanceToEllipse(p, rect)),
    ),
    (
      DrawShapeType.triangle,
      rect.topLeft,
      rect.bottomRight,
      _meanError(points, (p) => _distanceToTriangle(p, rect, pointUp: true)),
    ),
    (
      // Вершина вниз: холст ставит её на сторону `start`, поэтому
      // прямоугольник отдаём перевёрнутым.
      DrawShapeType.triangle,
      Offset(rect.left, rect.bottom),
      Offset(rect.right, rect.top),
      _meanError(points, (p) => _distanceToTriangle(p, rect, pointUp: false)),
    ),
  ];

  // Углы решают спор эллипса с прямоугольником. Средние отклонения у них
  // бывают почти равны — овал лежит внутри своего прямоугольника, — и тогда
  // выбор скакал от одной формы к другой. У прямоугольника рука проходит по
  // углам, у овала они пусты: этот признак не путается.
  final corners = _filledCorners(points, rect);
  final adjusted = <(DrawShapeType, Offset, Offset, double)>[
    for (final c in candidates)
      (
        c.$1,
        c.$2,
        c.$3,
        switch (c.$1) {
          DrawShapeType.rect when corners <= 1 => c.$4 * 2.2,
          DrawShapeType.circle when corners >= 4 => c.$4 * 2.2,
          _ => c.$4,
        },
      ),
  ];

  adjusted.sort((a, b) => a.$4.compareTo(b.$4));
  final best = adjusted.first;
  if (best.$4 > size * tolerance) return null;
  return QuickShape(best.$1, best.$2, best.$3);
}

/// Сколько углов прямоугольника рука действительно обошла.
int _filledCorners(List<Offset> points, Rect rect) {
  final reach = math.min(rect.width, rect.height) * 0.22;
  final corners = [
    rect.topLeft,
    rect.topRight,
    rect.bottomRight,
    rect.bottomLeft,
  ];
  var filled = 0;
  for (final corner in corners) {
    for (final p in points) {
      if ((p - corner).distance <= reach) {
        filled++;
        break;
      }
    }
  }
  return filled;
}

double _meanError(List<Offset> points, double Function(Offset) distance) {
  var sum = 0.0;
  for (final p in points) {
    sum += distance(p);
  }
  return sum / points.length;
}

double _distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
  if (lengthSquared == 0) return (p - a).distance;
  final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lengthSquared)
      .clamp(0.0, 1.0);
  return (p - Offset(a.dx + ab.dx * t, a.dy + ab.dy * t)).distance;
}

double _distanceToRect(Offset p, Rect r) {
  if (r.contains(p)) {
    return math.min(
      math.min(p.dx - r.left, r.right - p.dx),
      math.min(p.dy - r.top, r.bottom - p.dy),
    );
  }
  final nearest = Offset(
    p.dx.clamp(r.left, r.right),
    p.dy.clamp(r.top, r.bottom),
  );
  return (p - nearest).distance;
}

/// Расстояние до овала, вписанного в прямоугольник, — приближение через
/// нормированный радиус. Точного решения тут не нужно: сравниваются формы
/// между собой, а не измеряется зазор.
double _distanceToEllipse(Offset p, Rect r) {
  final rx = r.width / 2, ry = r.height / 2;
  if (rx <= 0 || ry <= 0) return double.infinity;
  final nx = (p.dx - r.center.dx) / rx;
  final ny = (p.dy - r.center.dy) / ry;
  final norm = math.sqrt(nx * nx + ny * ny);
  return (norm - 1).abs() * math.min(rx, ry);
}

double _distanceToTriangle(Offset p, Rect r, {required bool pointUp}) {
  final apex = Offset(r.center.dx, pointUp ? r.top : r.bottom);
  final baseY = pointUp ? r.bottom : r.top;
  final b = Offset(r.left, baseY);
  final c = Offset(r.right, baseY);
  return math.min(
    _distanceToSegment(p, apex, b),
    math.min(_distanceToSegment(p, b, c), _distanceToSegment(p, c, apex)),
  );
}
