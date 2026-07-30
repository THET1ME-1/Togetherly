import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/pair_achievement.dart';

/// Медаль достижения — правильный многоугольник со скруглёнными углами.
///
/// Форма читается как ранг: чем выше уровень, тем больше граней. Органических
/// «клякс» здесь нет намеренно — достижение это отметка о заслуге, ей идёт
/// строгая геометрия, а не мягкое пятно.
class AchievementMedal extends StatelessWidget {
  const AchievementMedal({
    super.key,
    required this.tier,
    required this.unlocked,
    required this.label,
    required this.size,
    required this.fill,
    required this.onFill,
  });

  final AchievementTier tier;
  final bool unlocked;

  /// Что внутри: эмодзи достижения или число-порог.
  final String label;

  final double size;

  /// Заливка фигуры и цвет содержимого.
  final Color fill;
  final Color onFill;

  @override
  Widget build(BuildContext context) {
    final shape = achievementShapeFor(tier);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PolygonPainter(shape: shape, color: fill),
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontFamily: 'Onest',
              fontSize: size * (label.length > 2 ? 0.28 : 0.36),
              fontWeight: FontWeight.w800,
              color: onFill,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _PolygonPainter extends CustomPainter {
  const _PolygonPainter({required this.shape, required this.color});

  final AchievementShape shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final c = Offset(size.width / 2, size.height / 2);
    final path = Path();

    // Скругление углов делаем дугами между сторонами: так фигура остаётся
    // правильной, а не превращается в звёздочку с обрубленными вершинами.
    final step = 2 * math.pi / shape.sides;
    final corner = r * shape.corner;
    for (var i = 0; i < shape.sides; i++) {
      final a = shape.rotation + i * step;
      final p = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
      final prev = Offset(
        c.dx + r * math.cos(a - step),
        c.dy + r * math.sin(a - step),
      );
      final next = Offset(
        c.dx + r * math.cos(a + step),
        c.dy + r * math.sin(a + step),
      );
      final toPrev = (prev - p);
      final toNext = (next - p);
      final inPrev = p + toPrev / toPrev.distance * corner;
      final inNext = p + toNext / toNext.distance * corner;

      if (i == 0) {
        path.moveTo(inPrev.dx, inPrev.dy);
      } else {
        path.lineTo(inPrev.dx, inPrev.dy);
      }
      path.quadraticBezierTo(p.dx, p.dy, inNext.dx, inNext.dy);
    }
    path.close();

    canvas.drawPath(path, Paint()..color = color..isAntiAlias = true);
  }

  @override
  bool shouldRepaint(_PolygonPainter old) =>
      old.color != color || old.shape.sides != shape.sides;
}
