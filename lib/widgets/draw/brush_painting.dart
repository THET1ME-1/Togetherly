import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../models/draw_stroke.dart';
import '../../models/stroke_brush.dart';

/// Кисти холста, кроме пера: маркер, карандаш, аэрограф, каллиграфия и мягкий
/// ластик. Перо рисует `paintStroke` прежним путём.
///
/// Всё считается от той же кривой, что у пера, поэтому мазок любой кистью
/// идёт там же, где вёл палец.

/// Кривая мазка: квадратичные дуги через середины соседних точек.
Path strokeCurve(List<DrawPoint> points, Size size) {
  final path = Path();
  final first = points.first.toOffset(size);
  path.moveTo(first.dx, first.dy);
  for (var i = 1; i < points.length - 1; i++) {
    final p0 = points[i].toOffset(size);
    final p1 = points[i + 1].toOffset(size);
    path.quadraticBezierTo(p0.dx, p0.dy, (p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
  }
  final last = points.last.toOffset(size);
  path.lineTo(last.dx, last.dy);
  return path;
}

/// Перо каллиграфа держат под −45°: мазок вниз-вправо выходит толстым,
/// вверх-вправо — волосным.
const double _nibAngle = -math.pi / 4;

void paintBrushStroke(
  Canvas canvas,
  List<DrawPoint> points,
  int colorValue,
  double width,
  bool isEraser,
  Size size, {
  required StrokeBrush brush,
  double alpha = 1.0,
  int seed = 0,
}) {
  if (points.isEmpty) return;
  final dot = points.every((p) => p.x == points.first.x && p.y == points.first.y);
  final curve = strokeCurve(points, size);

  if (isEraser) {
    // Мягкий ластик снимает краску с размытым краем. Точку ластик не стирает,
    // как и твёрдый: такой мазок и не сохраняется.
    if (dot) return;
    canvas.drawPath(
      curve,
      _line(width)
        ..color = const Color(0xFF000000)
        ..blendMode = BlendMode.dstOut
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, _softSigma(width)),
    );
    return;
  }

  final base = Color(colorValue);
  Color tint(double share) => base.withValues(alpha: base.a * share * alpha);
  final center = points.first.toOffset(size);

  switch (brush) {
    case StrokeBrush.marker:
      // Один путь — одно покрытие: внутри мазка краска не темнеет, темнеет
      // только наложение разных мазков.
      final paint = Paint()..color = tint(0.5);
      if (dot) {
        canvas.drawRect(Rect.fromCenter(center: center, width: width * 1.6, height: width * 1.6), paint);
      } else {
        canvas.drawPath(curve, _line(width * 1.6, cap: StrokeCap.butt)..color = tint(0.5));
      }
    case StrokeBrush.pencil:
      final core = math.max(1.0, width * 0.45);
      if (dot) {
        canvas.drawCircle(center, core / 2 + 0.5, Paint()..color = tint(0.55));
      } else {
        canvas.drawPath(curve, _line(core)..color = tint(0.55));
      }
      _paintGrain(canvas, dot ? [center] : _samples(curve, 0.9), core, base, alpha, seed);
    case StrokeBrush.airbrush:
      final blur = MaskFilter.blur(BlurStyle.normal, _softSigma(width));
      if (dot) {
        canvas.drawCircle(center, width * 0.65, Paint()..color = tint(0.55)..maskFilter = blur);
      } else {
        canvas.drawPath(curve, _line(width * 1.3)..color = tint(0.55)..maskFilter = blur);
      }
    case StrokeBrush.calligraphy:
      _paintCalligraphy(canvas, dot ? [center] : _samples(curve, 1.5), curve, width, tint(1), dot);
    case StrokeBrush.pen:
      // Перо рисует `paintStroke`; сюда оно не доходит.
      canvas.drawPath(curve, _line(width)..color = tint(1));
  }
}

Paint _line(double width, {StrokeCap cap = StrokeCap.round}) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = cap
  ..strokeJoin = StrokeJoin.round;

double _softSigma(double width) => math.max(1.0, width * 0.4);

/// Точки вдоль кривой с шагом [step] точек, включая конец.
List<Offset> _samples(Path curve, double step) {
  final out = <Offset>[];
  for (final metric in curve.computeMetrics()) {
    for (var d = 0.0; d < metric.length; d += step) {
      final tangent = metric.getTangentForOffset(d);
      if (tangent != null) out.add(tangent.position);
    }
    final end = metric.getTangentForOffset(metric.length);
    if (end != null) out.add(end.position);
  }
  return out;
}

/// Крошки графита вокруг линии. Три силы нажима — три вызова, а не тысяча
/// отдельных квадратиков.
void _paintGrain(Canvas canvas, List<Offset> along, double core, Color base, double alpha, int seed) {
  final random = BrushRandom(seed);
  final buckets = [<double>[], <double>[], <double>[]];
  final spread = core * 0.9 + 0.6;
  for (final p in along) {
    for (var k = 0; k < 2; k++) {
      final angle = random.next() * 2 * math.pi;
      final radius = random.next() * spread;
      final bucket = buckets[math.min(2, (random.next() * 3).floor())];
      bucket
        ..add(p.dx + math.cos(angle) * radius)
        ..add(p.dy + math.sin(angle) * radius);
    }
  }
  const strength = [0.22, 0.4, 0.62];
  for (var i = 0; i < 3; i++) {
    if (buckets[i].isEmpty) continue;
    canvas.drawRawPoints(
      PointMode.points,
      Float32List.fromList(buckets[i]),
      Paint()
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.square
        ..color = base.withValues(alpha: base.a * strength[i] * alpha),
    );
  }
}

/// Лента плоского пера: на каждом шаге — четырёхугольник между положениями
/// насадки. Все они обходятся в одну сторону, иначе при заливке «ненулевым»
/// правилом встречные сократились бы и в линии остались дыры.
void _paintCalligraphy(Canvas canvas, List<Offset> along, Path curve, double width, Color color, bool dot) {
  final half = width * 0.75;
  final nib = Offset(math.cos(_nibAngle) * half, math.sin(_nibAngle) * half);
  final hairline = _line(math.max(1.0, width * 0.12))..color = color;
  if (dot || along.length < 2) {
    final c = along.first;
    canvas.drawLine(c - nib, c + nib, hairline);
    return;
  }
  final ribbon = Path();
  for (var i = 1; i < along.length; i++) {
    final a = along[i - 1];
    final b = along[i];
    final quad = [a + nib, b + nib, b - nib, a - nib];
    ribbon.addPolygon(_area(quad) >= 0 ? quad : quad.reversed.toList(), true);
  }
  canvas.drawPath(ribbon, Paint()..color = color);
  // Вдоль пера лента сходит в ноль — волосная линия не даёт мазку пропасть.
  canvas.drawPath(curve, hairline);
}

double _area(List<Offset> polygon) {
  var sum = 0.0;
  for (var i = 0; i < polygon.length; i++) {
    final a = polygon[i];
    final b = polygon[(i + 1) % polygon.length];
    sum += a.dx * b.dy - b.dx * a.dy;
  }
  return sum / 2;
}
