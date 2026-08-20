import 'dart:ui';

import '../../models/draw_stroke.dart';

/// Отрисовка штрихов холста. Вынесена из экрана рисования, чтобы повтор
/// («Как рисовали») показывал ровно ту же линию, что и живой холст: две копии
/// одного кода разошлись бы на первой же правке кисти.

void paintShape(
  Canvas canvas,
  List<DrawPoint> points,
  int colorValue,
  double strokeWidth,
  DrawShapeType shapeType,
  Size size, {
  double alpha = 1.0,
  required bool isFilledShape,
}) {
  if (points.length < 2) return;
  final c = Color(colorValue);
  final paint = Paint()
    ..color = alpha < 1.0 ? c.withValues(alpha: c.a * alpha) : c
    ..strokeWidth = strokeWidth
    ..strokeCap = StrokeCap.round
    ..style = isFilledShape ? PaintingStyle.fill : PaintingStyle.stroke;

  final s = points.first.toOffset(size);
  final e = points.last.toOffset(size);

  switch (shapeType) {
    case DrawShapeType.line:
      canvas.drawLine(s, e, paint);
    case DrawShapeType.rect:
      canvas.drawRect(Rect.fromPoints(s, e), paint);
    case DrawShapeType.circle:
      canvas.drawOval(Rect.fromPoints(s, e), paint);
    case DrawShapeType.triangle:
      final path = Path();
      path.moveTo((s.dx + e.dx) / 2, s.dy); // Top center
      path.lineTo(s.dx, e.dy); // Bottom left
      path.lineTo(e.dx, e.dy); // Bottom right
      path.close();
      canvas.drawPath(path, paint);
  }
}


/// Пиксельный штрих: точки — номера клеток, между ними шагаем алгоритмом
/// Брезенхэма, иначе при быстром движении пальца в дорожке остаются дыры.
void paintPixelStroke(
  Canvas canvas,
  List<DrawPoint> points,
  int colorValue,
  bool isEraser,
  Size size,
  int cols,
  int rows, {
  double alpha = 1.0,
}) {
  if (points.isEmpty || cols < 1 || rows < 1) return;
  final cw = size.width / cols;
  final ch = size.height / rows;
  final c = Color(colorValue);
  final paint = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = false
    ..color = isEraser
        ? const Color(0xFF000000)
        : (alpha < 1.0 ? c.withValues(alpha: c.a * alpha) : c);
  if (isEraser) paint.blendMode = BlendMode.dstOut;

  final cells = <int>{};
  int? prevX, prevY;
  for (final p in points) {
    final cx = (p.x * cols).floor().clamp(0, cols - 1);
    final cy = (p.y * rows).floor().clamp(0, rows - 1);
    if (prevX != null && prevY != null && (prevX != cx || prevY != cy)) {
      int x0 = prevX, y0 = prevY;
      final dx = (cx - x0).abs(), sx = x0 < cx ? 1 : -1;
      final dy = -(cy - y0).abs(), sy = y0 < cy ? 1 : -1;
      int err = dx + dy;
      while (true) {
        cells.add(y0 * cols + x0);
        if (x0 == cx && y0 == cy) break;
        final e2 = 2 * err;
        if (e2 >= dy) { err += dy; x0 += sx; }
        if (e2 <= dx) { err += dx; y0 += sy; }
      }
    }
    cells.add(cy * cols + cx);
    prevX = cx;
    prevY = cy;
  }

  // +0.5 к стороне — чтобы между соседними клетками не просвечивали щели
  // после округления координат.
  for (final key in cells) {
    final x = key % cols;
    final y = key ~/ cols;
    canvas.drawRect(
      Rect.fromLTWH(x * cw, y * ch, cw + 0.5, ch + 0.5),
      paint,
    );
  }
}


void paintStroke(
  Canvas canvas,
  List<DrawPoint> points,
  int colorValue,
  double strokeWidth,
  bool isEraser,
  Size size, {
  double alpha = 1.0,
  int? pixelCols,
  int? pixelRows,
}) {
  if (points.isEmpty) return;
  // Пиксельный холст: клетки вместо сглаженной кривой.
  if (pixelCols != null && pixelRows != null) {
    paintPixelStroke(canvas, points, colorValue, isEraser, size,
        pixelCols, pixelRows, alpha: alpha);
    return;
  }
  final paint = Paint()
    ..strokeWidth = strokeWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;

  if (isEraser) {
    // Ластик СНИМАЕТ краску, а не красит цветом фона. Прежний способ был
    // дешевле, но затирал и фон холста: на сетке и узорах после ластика
    // оставалась белая плешь. Работает только внутри `saveLayer` — снаружи
    // стирать нечего, и дыра уйдёт до самого низа.
    paint
      ..color = const Color(0xFF000000)
      ..blendMode = BlendMode.dstOut;
  } else {
    final c = Color(colorValue);
    paint.color = alpha < 1.0 ? c.withValues(alpha: c.a * alpha) : c;
  }

  if (points.length == 1) {
    if (!isEraser) {
      canvas.drawCircle(
        points.first.toOffset(size),
        strokeWidth / 2,
        paint..style = PaintingStyle.fill,
      );
    }
    return;
  }

  final path = Path();
  final first = points.first.toOffset(size);
  path.moveTo(first.dx, first.dy);

  for (int i = 1; i < points.length - 1; i++) {
    final p0 = points[i].toOffset(size);
    final p1 = points[i + 1].toOffset(size);
    final mid = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
    path.quadraticBezierTo(p0.dx, p0.dy, mid.dx, mid.dy);
  }

  final last = points.last.toOffset(size);
  path.lineTo(last.dx, last.dy);
  canvas.drawPath(path, paint..style = PaintingStyle.stroke);
}
