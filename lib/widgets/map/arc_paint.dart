import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Точки дуги между двумя людьми: круглые, через 11 точек, на подложке цвета
/// поверхности, чтобы читались на любом месте карты. Этим же рисуются дуга
/// на глобусе, на развёртке и на плоской карте — выглядят одинаково.
void paintDottedArc(
  Canvas canvas,
  List<Offset> pts, {
  required Color color,
  required Color halo,
  double gap = 11,
}) {
  if (pts.length < 2) return;
  final haloPaint = Paint()..color = halo;
  final dotPaint = Paint()..color = color;
  var carry = 0.0;
  for (var i = 1; i < pts.length; i++) {
    final a = pts[i - 1], b = pts[i];
    final seg = (b - a).distance;
    if (seg <= 0) continue;
    var s = carry;
    while (s <= seg) {
      final p = Offset.lerp(a, b, s / seg)!;
      canvas.drawCircle(p, 4.5, haloPaint);
      canvas.drawCircle(p, 2.5, dotPaint);
      s += gap;
    }
    carry = s - seg;
  }
}

/// Точка на ломаной на доле [t] её длины.
Offset pointAlong(List<Offset> pts, double t) {
  if (pts.isEmpty) return Offset.zero;
  if (pts.length == 1) return pts.first;
  var total = 0.0;
  for (var i = 1; i < pts.length; i++) {
    total += (pts[i] - pts[i - 1]).distance;
  }
  var want = total * t.clamp(0.0, 1.0);
  for (var i = 1; i < pts.length; i++) {
    final seg = (pts[i] - pts[i - 1]).distance;
    if (want <= seg && seg > 0) return Offset.lerp(pts[i - 1], pts[i], want / seg)!;
    want -= seg;
  }
  return pts.last;
}

/// Сердце «Скучаю», бегущее по дуге: на кружке поверхности, чуть растёт на
/// середине пути.
void paintFlyingHeart(
  Canvas canvas,
  List<Offset> pts,
  double t, {
  required Color color,
  required Color halo,
}) {
  if (pts.length < 2) return;
  final p = pointAlong(pts, 1 - math.pow(1 - t, 3).toDouble());
  final scale = 1 + .15 * math.sin(t * math.pi);
  canvas.drawCircle(p, 15 * scale, Paint()..color = halo);
  final icon = Icons.favorite_rounded;
  final tp = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        fontSize: 20 * scale,
        color: color,
        height: 1,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
}
