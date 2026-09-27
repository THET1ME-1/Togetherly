import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Лучи за сундуком (макет «Фон за сундуком», вариант «Светлые лучи»,
/// 27.09.2026): шестнадцать лучей расходятся из центра блока и делают оборот
/// за минуту. Фон — `secondaryContainer`, лучи того же оттенка светлее, как
/// солнце из-под крышки.
///
/// Лучи выводятся из фона, а не берутся отдельной ролью: в прошлой версии
/// розовый фон и персиковые лучи из `tertiaryContainer` спорили оттенками.
/// Смесь фона с поверхностью темы светлее фона в любой из двадцати пяти
/// палитр, в тёмной теме лучи на полтона светлее за счёт основного цвета.
///
/// С отключёнными в системе анимациями лучи стоят.
class ChestRays extends StatefulWidget {
  const ChestRays({super.key, required this.scheme});

  final ColorScheme scheme;

  @override
  State<ChestRays> createState() => _ChestRaysState();
}

class _ChestRaysState extends State<ChestRays> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(minutes: 1));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _spin.stop();
    } else if (!_spin.isAnimating) {
      _spin.repeat();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.scheme;
    final bg = cs.secondaryContainer;
    final ray = cs.brightness == Brightness.dark
        ? Color.lerp(bg, cs.primary, 0.15)!
        : Color.lerp(bg, cs.surface, 0.55)!;
    return RepaintBoundary(
      child: CustomPaint(
        painter: _RaysPainter(turn: _spin, background: bg, ray: ray),
        size: Size.infinite,
      ),
    );
  }
}

class _RaysPainter extends CustomPainter {
  _RaysPainter({required this.turn, required this.background, required this.ray}) : super(repaint: turn);

  final Animation<double> turn;
  final Color background;
  final Color ray;

  static const int _count = 16;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final c = size.center(Offset.zero);
    // Луч длиннее диагонали: при любом повороте доходит до углов блока.
    final r = size.longestSide;
    final start = turn.value * 2 * math.pi;
    final path = Path();
    for (var i = 0; i < _count; i++) {
      final a0 = start + 2 * math.pi * i / _count;
      final a1 = start + 2 * math.pi * (i + 0.5) / _count;
      path
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + r * math.cos(a0), c.dy + r * math.sin(a0))
        ..lineTo(c.dx + r * math.cos(a1), c.dy + r * math.sin(a1))
        ..close();
    }
    canvas.drawPath(path, Paint()..color = ray);
  }

  @override
  bool shouldRepaint(_RaysPainter old) => old.background != background || old.ray != ray || old.turn != turn;
}
