import 'dart:math' as math;
import 'dart:ui';

import 'draw_stroke.dart';

/// Векторная правка нарисованного: взять мазок или фигуру и подвинуть,
/// повернуть, растянуть.
///
/// Штрих хранится точками в долях 0..1 от листа — так рисунок одинаково
/// выглядит на любом экране. Но считать в долях повороты и масштаб нельзя: на
/// холсте 4:5 доля по вертикали «длиннее» доли по горизонтали, и повёрнутый
/// круг вышел бы овалом. Поэтому всё считается в ТОЧКАХ холста, а обратно в
/// доли переводится в самом конце.
///
/// Здесь нет ни виджетов, ни состояния экрана: чистые функции проверяются
/// тестами, а жесты остаются в экране рисования.

/// За что человек тянет рамку выделения.
enum StrokeHandle { left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight }

/// Самый мелкий габарит, до которого можно сжать штрих.
///
/// Схлопнутую в точку фигуру уже не за что взять пальцем — вернуть её можно
/// было бы только отменой, а человек к этому моменту сделает ещё десять правок.
const double kMinStrokeSize = 6.0;

/// Насколько рамка выделения шире самой фигуры.
///
/// Ноль был бы честнее по геометрии, но рамка вплотную к тонкой линии сливается
/// с ней, и человек не понимает, что выделено. Число одно на отрисовку и на
/// зоны хвата: разъедутся — палец будет промахиваться мимо нарисованной ручки.
const double kSelectionPad = 6.0;

/// Насколько ручка поворота вынесена над рамкой.
///
/// Поворот нужен и одним пальцем: щипок двумя доступен не всем и невозможен
/// стилусом. Ручка стоит на отлёте, чтобы не спорить с углом рамки.
const double kSelectionSpinGap = 26.0;

Offset _toCanvas(DrawPoint p, Size canvas) =>
    Offset(p.x * canvas.width, p.y * canvas.height);

DrawPoint _toFraction(Offset o, Size canvas) =>
    DrawPoint(o.dx / canvas.width, o.dy / canvas.height);

/// Прямоугольник вокруг штриха в точках холста — ровно по точкам.
///
/// Запас на толщину кисти сюда НЕ входит: габарит участвует в растягивании и
/// масштабе, и лишние четыре точки по краям потом вылезают перекосом. Запас
/// для пальца добавляет тот, кто ловит касание.
Rect strokeBounds(DrawStroke stroke, Size canvas) {
  if (stroke.points.isEmpty) return Rect.zero;
  var left = double.infinity, top = double.infinity;
  var right = -double.infinity, bottom = -double.infinity;
  for (final p in stroke.points) {
    final o = _toCanvas(p, canvas);
    if (o.dx < left) left = o.dx;
    if (o.dx > right) right = o.dx;
    if (o.dy < top) top = o.dy;
    if (o.dy > bottom) bottom = o.dy;
  }
  // Одиночная точка — единственный случай, где габарит был бы нулевым: за
  // такую рамку не взяться, поэтому раздуваем её до самой кисти.
  if (right - left < 0.01 && bottom - top < 0.01) {
    final pad = math.max(stroke.strokeWidth / 2, 4.0);
    return Rect.fromLTRB(left - pad, top - pad, right + pad, bottom + pad);
  }
  return Rect.fromLTRB(left, top, right, bottom);
}

/// Какой штрих под пальцем. Сверху лежащий выигрывает: его рисовали позже.
///
/// Мазок ловится по близости к линии, фигура — ещё и по своей середине: в
/// тонкий контур круга пальцем не попасть, а человек тянется к фигуре целиком.
DrawStroke? strokeAtPoint(
  List<DrawStroke> strokes,
  Offset point,
  Size canvas, {
  double tolerance = 18.0,
}) {
  DrawStroke? best;
  var bestOrder = -1 << 31;
  for (final s in strokes) {
    if (s.points.isEmpty) continue;
    if (!_hits(s, point, canvas, tolerance)) continue;
    if (s.orderIndex >= bestOrder) {
      best = s;
      bestOrder = s.orderIndex;
    }
  }
  return best;
}

bool _hits(DrawStroke stroke, Offset point, Size canvas, double tolerance) {
  final bounds = strokeBounds(stroke, canvas).inflate(tolerance);
  if (!bounds.contains(point)) return false;

  // Залитая фигура и картинка — берутся всей площадью.
  if (stroke.isFilledShape || stroke.isImageStroke) return true;

  // Фигура-контур: попадание либо рядом с контуром, либо внутри — иначе в
  // круг радиусом в палец не ткнуть.
  if (stroke.shapeType != null) return true;

  // Мазок: расстояние до его отрезков.
  final pts = [for (final p in stroke.points) _toCanvas(p, canvas)];
  if (pts.length == 1) {
    return (pts.first - point).distance <= tolerance + stroke.strokeWidth;
  }
  for (var i = 0; i < pts.length - 1; i++) {
    if (_distanceToSegment(point, pts[i], pts[i + 1]) <=
        tolerance + stroke.strokeWidth / 2) {
      return true;
    }
  }
  return false;
}

double _distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final lengthSq = ab.dx * ab.dx + ab.dy * ab.dy;
  if (lengthSq == 0) return (p - a).distance;
  var t = ((p - a).dx * ab.dx + (p - a).dy * ab.dy) / lengthSq;
  t = t.clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

/// Сдвиг штриха. За край листа не выпускаем: потерянное за краем не вернуть.
DrawStroke moveStroke(DrawStroke stroke, Offset delta, Size canvas) {
  final bounds = strokeBounds(stroke, canvas);
  final clamped = Offset(
    delta.dx.clamp(-bounds.left, canvas.width - bounds.right),
    delta.dy.clamp(-bounds.top, canvas.height - bounds.bottom),
  );
  return _mapPoints(stroke, (o) => o + clamped, canvas);
}

/// Масштаб вокруг середины штриха.
DrawStroke scaleStroke(DrawStroke stroke, double factor, Size canvas) {
  final bounds = strokeBounds(stroke, canvas);
  final center = bounds.center;
  final safe = _safeFactor(bounds, factor);
  return _mapPoints(stroke, (o) => center + (o - center) * safe, canvas);
}

double _safeFactor(Rect bounds, double factor) {
  // Меряем по ДЛИННОЙ стороне: у прямой линии короткая равна нулю, и предел
  // «не мельче шести точек» превращался в множитель в сотни раз — вместо
  // защиты от схлопывания фигура прыгала на весь лист.
  final side = math.max(bounds.longestSide, 0.01);
  final min = kMinStrokeSize / side;
  if (factor <= 0) return min;
  return factor < min ? min : factor;
}

/// Поворот вокруг середины штриха, в радианах.
DrawStroke rotateStroke(DrawStroke stroke, double radians, Size canvas) {
  final center = strokeBounds(stroke, canvas).center;
  final cos = math.cos(radians), sin = math.sin(radians);
  return _mapPoints(stroke, (o) {
    final v = o - center;
    return center + Offset(v.dx * cos - v.dy * sin, v.dx * sin + v.dy * cos);
  }, canvas);
}

/// Растягивание за край рамки: противоположная сторона стоит на месте.
DrawStroke stretchStroke(
  DrawStroke stroke, {
  required StrokeHandle handle,
  required Offset delta,
  required Size canvas,
}) {
  final b = strokeBounds(stroke, canvas);
  var left = b.left, right = b.right, top = b.top, bottom = b.bottom;

  switch (handle) {
    case StrokeHandle.left:
      left += delta.dx;
    case StrokeHandle.right:
      right += delta.dx;
    case StrokeHandle.top:
      top += delta.dy;
    case StrokeHandle.bottom:
      bottom += delta.dy;
    case StrokeHandle.topLeft:
      left += delta.dx;
      top += delta.dy;
    case StrokeHandle.topRight:
      right += delta.dx;
      top += delta.dy;
    case StrokeHandle.bottomLeft:
      left += delta.dx;
      bottom += delta.dy;
    case StrokeHandle.bottomRight:
      right += delta.dx;
      bottom += delta.dy;
  }

  // Через себя не выворачиваем: перевёрнутая фигура читается как поломка, а
  // не как приём.
  if (right - left < kMinStrokeSize) {
    if (handle == StrokeHandle.left ||
        handle == StrokeHandle.topLeft ||
        handle == StrokeHandle.bottomLeft) {
      left = right - kMinStrokeSize;
    } else {
      right = left + kMinStrokeSize;
    }
  }
  if (bottom - top < kMinStrokeSize) {
    if (handle == StrokeHandle.top ||
        handle == StrokeHandle.topLeft ||
        handle == StrokeHandle.topRight) {
      top = bottom - kMinStrokeSize;
    } else {
      bottom = top + kMinStrokeSize;
    }
  }

  final sx = (right - left) / math.max(b.width, 0.01);
  final sy = (bottom - top) / math.max(b.height, 0.01);
  return _mapPoints(stroke, (o) {
    return Offset(left + (o.dx - b.left) * sx, top + (o.dy - b.top) * sy);
  }, canvas);
}

DrawStroke _mapPoints(
  DrawStroke stroke,
  Offset Function(Offset) map,
  Size canvas,
) {
  final points = [
    for (final p in stroke.points)
      () {
        final moved = map(_toCanvas(p, canvas));
        final f = _toFraction(moved, canvas);
        // Доли держим в листе: точка за краем ломает и отрисовку, и хит-тест.
        return DrawPoint(f.x.clamp(0.0, 1.0), f.y.clamp(0.0, 1.0));
      }(),
  ];
  return strokeWithPoints(stroke, points);
}

/// Тот же штрих с другими точками. Нужен отмене правки: она возвращает форму,
/// какой та была до жеста, и всё остальное — цвет, слой, порядок — обязано
/// остаться прежним.
DrawStroke strokeWithPoints(DrawStroke stroke, List<DrawPoint> points) {
  return DrawStroke(
    id: stroke.id,
    clientId: stroke.clientId,
    userId: stroke.userId,
    colorValue: stroke.colorValue,
    strokeWidth: stroke.strokeWidth,
    points: points,
    isEraser: stroke.isEraser,
    isFilledShape: stroke.isFilledShape,
    shapeType: stroke.shapeType,
    orderIndex: stroke.orderIndex,
    imageUrl: stroke.imageUrl,
    imageX: stroke.imageX,
    imageY: stroke.imageY,
    imageWidth: stroke.imageWidth,
    imageHeight: stroke.imageHeight,
    imageRotation: stroke.imageRotation,
    layer: stroke.layer,
  );
}
