import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/pair_jar.dart';

/// Капли копилки пары той же рукой, что значки, рамки и сундук (манера
/// Overrule из мастерской `togetherly-badges-hand`): белая кайма-наклейка,
/// пастельная заливка, штриховка вдоль теневого края, блик и контур тушью с
/// нахлёстом на старте. Каждая капля чуть своя — точки дрожат от своего зерна.
///
/// Рисуется кодом, а не картинкой: цвет капли берётся из темы, а палитр
/// двадцать пять в двух яркостях.
class JarDrops extends StatelessWidget {
  const JarDrops({
    super.key,
    required this.jar,
    required this.mine,
    required this.partner,
    this.dropHeight = 20,
    this.gap = 3,
    this.popLast = false,
  });

  final PairJar jar;

  /// Заливка моих капель и капель партнёра.
  final Color mine;
  final Color partner;
  final double dropHeight;
  final double gap;

  /// Последняя упавшая капля подпрыгивает — только что положили.
  final bool popLast;

  @override
  Widget build(BuildContext context) {
    final w = dropHeight * 0.8;
    final cells = <Widget>[];
    for (var i = 0; i < jar.size; i++) {
      final filled = i < jar.count;
      final drop = SizedBox(
        width: w,
        height: dropHeight,
        child: CustomPaint(
          painter: JarDropPainter(index: i, fill: filled ? (jar.drops[i] ? mine : partner) : null),
        ),
      );
      cells.add(popLast && filled && i == jar.count - 1 ? _Pop(child: drop) : drop);
      if (i < jar.size - 1) cells.add(SizedBox(width: gap));
    }
    return Semantics(
      label: '${jar.count}/${jar.size}',
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(mainAxisSize: MainAxisSize.min, children: cells),
      ),
    );
  }
}

class _Pop extends StatefulWidget {
  const _Pop({required this.child});

  final Widget child;

  @override
  State<_Pop> createState() => _PopState();
}

class _PopState extends State<_Pop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
    ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final t = Curves.easeOut.transform(_c.value);
        final lift = math.sin(t * math.pi);
        return Transform.translate(
          offset: Offset(0, -lift * 4),
          child: Transform.scale(scale: 1 + lift * 0.18, child: child),
        );
      },
      child: widget.child,
    );
  }
}

/// Одна капля. [fill] null — пустое место: пунктир тушью без заливки.
class JarDropPainter extends CustomPainter {
  const JarDropPainter({required this.index, this.fill});

  final int index;
  final Color? fill;

  static const Color ink = Color(0xFF2A2D30);
  static const Color ink2 = Color(0xFF5D5F62);

  // Капля в клетке 16×20: острый носик сверху (две точки у носика держат его
  // острым после сглаживания), округлое брюшко снизу.
  static const List<Offset> _base = [
    Offset(8, 1.2),
    Offset(9.4, 3.6),
    Offset(11.9, 7.4),
    Offset(14.3, 12.0),
    Offset(13.5, 16.6),
    Offset(8.0, 19.2),
    Offset(2.6, 16.7),
    Offset(1.7, 12.1),
    Offset(4.1, 7.4),
    Offset(6.6, 3.6),
  ];

  /// Точки капли с дрожью руки: у каждой своё зерно, как `seed` в badges.js.
  static List<Offset> points(int index) {
    var seed = 911 + index * 131;
    double rnd() {
      seed = (seed * 16807) % 2147483647;
      return seed / 2147483647;
    }

    return [for (final p in _base) p + Offset((rnd() - 0.5) * 0.7, (rnd() - 0.5) * 0.7)];
  }

  /// Сглаживание Catmull-Rom — `cr()` из badges.js.
  static Path smooth(List<Offset> pts, {required bool closed}) {
    final n = pts.length;
    Offset at(int i) => closed ? pts[(i % n + n) % n] : pts[i.clamp(0, n - 1)];
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    final last = closed ? n : n - 1;
    for (var i = 0; i < last; i++) {
      final p0 = at(i - 1), p1 = at(i), p2 = at(i + 1), p3 = at(i + 2);
      final c1 = p1 + (p2 - p0) / 6;
      final c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    if (closed) path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final k = math.min(size.width / 16, size.height / 20);
    canvas.save();
    canvas.translate((size.width - 16 * k) / 2, (size.height - 20 * k) / 2);
    canvas.scale(k);

    final pts = points(index);
    final body = smooth(pts, closed: true);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final color = fill;
    if (color == null) {
      canvas.drawPath(body, Paint()..color = Colors.white.withValues(alpha: 0.28));
      _dashed(
        canvas,
        body,
        stroke
          ..color = ink.withValues(alpha: 0.42)
          ..strokeWidth = 1.2,
      );
      canvas.restore();
      return;
    }

    // Белая кайма-наклейка под силуэтом.
    canvas.drawPath(body, Paint()..color = Colors.white);
    canvas.drawPath(
      body,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.4
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(body, Paint()..color = color);

    // Штриховка тени: полоса вдоль правого нижнего края — форма минус её
    // копия, сдвинутая к свету, как маска `hatch()` в badges.js.
    final shadow = Path.combine(ui.PathOperation.difference, body, body.shift(const Offset(-3.2, -3.2)));
    canvas.save();
    canvas.clipPath(shadow);
    final hatch = Paint()
      ..color = ink2.withValues(alpha: 0.55)
      ..strokeWidth = 0.9
      ..strokeCap = StrokeCap.round;
    for (var t = -24.0; t < 24; t += 2.2) {
      canvas.drawLine(Offset(8 + t, 10 - 14), Offset(8 + t - 14, 10 + 14), hatch);
    }
    canvas.restore();

    // Блик.
    canvas.drawPath(
      Path()
        ..moveTo(4.6, 13.2)
        ..quadraticBezierTo(4.3, 10.4, 6.2, 7.6),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );

    // Контур маркером: круг и заход на старт с нахлёстом (`contour()`).
    final a = pts[0], b = pts[1];
    final overlap = Offset(a.dx + (b.dx - a.dx) * 0.45, a.dy + (b.dy - a.dy) * 0.45);
    canvas.drawPath(
      smooth([...pts, a, overlap], closed: false),
      stroke
        ..color = ink
        ..strokeWidth = 1.6,
    );
    canvas.restore();
  }

  static void _dashed(Canvas canvas, Path path, Paint paint) {
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 3.4) {
        canvas.drawPath(m.extractPath(d, math.min(d + 1.9, m.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(JarDropPainter old) => old.index != index || old.fill != fill;
}
