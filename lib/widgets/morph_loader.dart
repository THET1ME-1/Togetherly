import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Индикатор загрузки в духе Material 3 Expressive: фигура перетекает из одной
/// в другую и одновременно вращается.
///
/// Во Flutter такого индикатора нет из коробки, поэтому рисуем сами. Смысл в
/// том, что ожидание перестаёт быть безликим кружком: форма живёт, и по ней
/// видно, что приложение не зависло.
///
/// Фигуры — скруглённые многоугольники с разным числом вершин. Переход между
/// ними идёт по общему числу точек, поэтому морфинг честный, без подрагиваний.
class MorphLoader extends StatefulWidget {
  const MorphLoader({
    super.key,
    this.size = 56,
    this.color,
    this.period = const Duration(milliseconds: 1600),
  });

  final double size;
  final Color? color;

  /// Сколько длится один шаг превращения.
  final Duration period;

  @override
  State<MorphLoader> createState() => _MorphLoaderState();
}

class _MorphLoaderState extends State<MorphLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  /// Число вершин в цепочке превращений. Начинаем с мягкой четвёрки и уходим к
  /// почти окружности — так фигура не выглядит угловатой ни в один момент.
  static const List<int> _shapes = [4, 6, 5, 8, 6, 12];

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.period)
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          // Общий прогресс гоняем по цепочке фигур: каждый оборот — один шаг.
          final total = _c.value * _shapes.length;
          final index = total.floor() % _shapes.length;
          final next = (index + 1) % _shapes.length;
          final t = Curves.easeInOutCubic.transform(total - total.floor());

          return CustomPaint(
            painter: _MorphPainter(
              from: _shapes[index],
              to: _shapes[next],
              t: t,
              // Вращение чуть медленнее морфинга: если совпадает, глаз
              // перестаёт различать превращение.
              rotation: _c.value * math.pi * 2 * 0.75,
              color: color,
            ),
          );
        },
      ),
    );
  }
}

class _MorphPainter extends CustomPainter {
  _MorphPainter({
    required this.from,
    required this.to,
    required this.t,
    required this.rotation,
    required this.color,
  });

  final int from;
  final int to;
  final double t;
  final double rotation;
  final Color color;

  /// По скольким точкам строим контур. Кратно любому числу вершин из цепочки,
  /// поэтому обе фигуры описываются одной сеткой и переход выходит плавным.
  static const int _samples = 240;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;

    final path = Path();
    for (var i = 0; i <= _samples; i++) {
      final angle = (i / _samples) * math.pi * 2 + rotation;
      final r = radius * _lerpRadius(angle);
      final p = Offset(
        center.dx + math.cos(angle) * r,
        center.dy + math.sin(angle) * r,
      );
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();

    canvas.drawPath(path, Paint()..color = color..isAntiAlias = true);
  }

  /// Радиус скруглённого многоугольника в данном направлении, с переходом
  /// между двумя формами.
  double _lerpRadius(double angle) {
    final a = _polygonRadius(angle, from);
    final b = _polygonRadius(angle, to);
    return a + (b - a) * t;
  }

  /// Мягкий многоугольник: радиус слегка гуляет по косинусу, поэтому углы
  /// получаются скруглёнными сами собой, без построения дуг.
  double _polygonRadius(double angle, int sides) {
    // Чем больше вершин, тем меньше «вмятина» — двенадцатиугольник почти круг.
    final depth = 0.14 - sides * 0.008;
    return 1 - depth.clamp(0.0, 0.14) * (1 - math.cos(angle * sides));
  }

  @override
  bool shouldRepaint(covariant _MorphPainter old) =>
      old.t != t || old.rotation != rotation || old.color != color ||
      old.from != from || old.to != to;
}
