import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/love_test.dart';

/// Фигура «Умение любить»: шесть оценок одним замкнутым контуром.
///
/// Сетка — шестиугольник с лучами: у теста шесть граней, и шестиугольник сам их
/// называет, вершина на каждую. Контур сглажен сплайном Кэтмулла-Рома, поэтому
/// читается как фигура, а не как диаграмма из отчёта: где грань сильнее, там он
/// тянется наружу. Число стоит рядом — фигура запоминается, число нет.
class LoveShape extends StatelessWidget {
  const LoveShape({
    super.key,
    required this.mine,
    this.theirs,
    this.mineColor,
    this.theirsColor,
    this.gridColor,
    this.labelColor,
    this.showLabels = true,
    this.center,
    this.centerColor,
  });

  final LoveTestResult mine;

  /// Фигура партнёра рисуется контуром поверх своей заливки: две заливки друг
  /// на друге сливаются в кашу.
  final LoveTestResult? theirs;

  final Color? mineColor;
  final Color? theirsColor;
  final Color? gridColor;
  final Color? labelColor;
  final bool showLabels;

  /// Число в середине. Пусто — середина остаётся пустой (так в карточке пары,
  /// где чисел два).
  final String? center;
  final Color? centerColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        final side = math.min(
          c.maxWidth.isFinite ? c.maxWidth : 320.0,
          c.maxHeight.isFinite ? c.maxHeight : 320.0,
        );
        return SizedBox(
          width: side,
          height: side,
          child: CustomPaint(
            painter: _LoveShapePainter(
              mine: mine,
              theirs: theirs,
              mineColor: mineColor ?? scheme.primary,
              theirsColor: theirsColor ?? scheme.tertiary,
              gridColor: gridColor ?? scheme.outlineVariant,
              labelColor: labelColor ?? scheme.onSurfaceVariant,
              showLabels: showLabels,
              center: center,
              centerColor: centerColor ?? scheme.onSurface,
              textDirection: Directionality.of(context),
            ),
          ),
        );
      },
    );
  }
}

class _LoveShapePainter extends CustomPainter {
  _LoveShapePainter({
    required this.mine,
    required this.theirs,
    required this.mineColor,
    required this.theirsColor,
    required this.gridColor,
    required this.labelColor,
    required this.showLabels,
    required this.center,
    required this.centerColor,
    required this.textDirection,
  });

  final LoveTestResult mine;
  final LoveTestResult? theirs;
  final Color mineColor;
  final Color theirsColor;
  final Color gridColor;
  final Color labelColor;
  final bool showLabels;
  final String? center;
  final Color centerColor;
  final TextDirection textDirection;

  /// Ядро: даже нулевая грань оставляет фигуру фигурой, а не звездой с
  /// провалом до центра.
  static const double _base = .12;

  static final int _n = LoveFacet.values.length;
  static final double _step = math.pi * 2 / _n;
  static const double _start = -math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final cx = size.width / 2;
    final cy = size.height / 2;
    // Место под подписи по краям: без него длинная «Благодарность» срезается.
    final pad = showLabels ? size.width * .21 : size.width * .06;
    final r = math.min(cx, cy) - pad;
    if (r <= 0) return;

    _paintGrid(canvas, cx, cy, r);

    final minePath = _shape(mine, cx, cy, r);
    canvas.drawPath(
      minePath,
      Paint()
        ..shader = RadialGradient(
          colors: [
            mineColor.withValues(alpha: .5),
            mineColor.withValues(alpha: .18),
          ],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)),
    );
    canvas.drawPath(
      minePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .012
        ..strokeJoin = StrokeJoin.round
        ..color = mineColor,
    );

    final other = theirs;
    if (other != null) {
      canvas.drawPath(
        _shape(other, cx, cy, r),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * .014
          ..strokeJoin = StrokeJoin.round
          ..color = theirsColor,
      );
    } else {
      _paintKnots(canvas, cx, cy, r, size);
    }

    if (showLabels) _paintLabels(canvas, cx, cy, r, size);
    _paintCenter(canvas, cx, cy, size);
  }

  void _paintGrid(Canvas canvas, double cx, double cy, double r) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = gridColor.withValues(alpha: .6);
    final fill = Paint()..color = gridColor.withValues(alpha: .1);

    for (var k = 3; k >= 1; k--) {
      final path = _hex(cx, cy, r * k / 3);
      if (k == 3) canvas.drawPath(path, fill);
      canvas.drawPath(path, line);
    }
    for (var i = 0; i < _n; i++) {
      final a = _start + _step * i;
      canvas.drawLine(
        Offset(cx, cy),
        Offset(cx + math.cos(a) * r, cy + math.sin(a) * r),
        line..color = gridColor.withValues(alpha: .4),
      );
    }
  }

  Path _hex(double cx, double cy, double r) {
    final path = Path();
    for (var i = 0; i < _n; i++) {
      final a = _start + _step * i;
      final p = Offset(cx + math.cos(a) * r, cy + math.sin(a) * r);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  List<Offset> _points(LoveTestResult res, double cx, double cy, double r) {
    return [
      for (var i = 0; i < _n; i++)
        () {
          final v = res.of(LoveFacet.values[i]).clamp(0, 100) / 100;
          final rr = r * (_base + (1 - _base) * v);
          final a = _start + _step * i;
          return Offset(cx + math.cos(a) * rr, cy + math.sin(a) * rr);
        }(),
    ];
  }

  /// Замкнутый сплайн Кэтмулла-Рома по шести точкам: натяжение 1/5 держит
  /// контур выпуклым и не даёт ему завязываться петлями на резких перепадах.
  Path _shape(LoveTestResult res, double cx, double cy, double r) {
    final pts = _points(res, cx, cy, r);
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (var i = 0; i < _n; i++) {
      final p0 = pts[(i - 1 + _n) % _n];
      final p1 = pts[i];
      final p2 = pts[(i + 1) % _n];
      final p3 = pts[(i + 2) % _n];
      path.cubicTo(
        p1.dx + (p2.dx - p0.dx) / 5, p1.dy + (p2.dy - p0.dy) / 5,
        p2.dx - (p3.dx - p1.dx) / 5, p2.dy - (p3.dy - p1.dy) / 5,
        p2.dx, p2.dy,
      );
    }
    return path..close();
  }

  void _paintKnots(Canvas canvas, double cx, double cy, double r, Size size) {
    final ring = Paint()..color = Colors.white.withValues(alpha: .9);
    final dot = Paint()..color = mineColor;
    for (final p in _points(mine, cx, cy, r)) {
      canvas.drawCircle(p, size.width * .022, ring);
      canvas.drawCircle(p, size.width * .014, dot);
    }
  }

  void _paintLabels(Canvas canvas, double cx, double cy, double r, Size size) {
    final fontSize = math.max(10.0, size.width * .042);
    for (var i = 0; i < _n; i++) {
      final a = _start + _step * i;
      final tp = TextPainter(
        text: TextSpan(
          text: LoveFacet.values[i].title,
          style: TextStyle(
            fontFamily: 'Onest',
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: labelColor,
          ),
        ),
        textDirection: textDirection,
        textAlign: TextAlign.center,
        maxLines: 2,
      )..layout(maxWidth: size.width * .26);

      final x = cx + math.cos(a) * (r + size.width * .09) - tp.width / 2;
      final y = cy + math.sin(a) * (r + size.width * .08) - tp.height / 2;
      tp.paint(canvas, Offset(x, y));
    }
  }

  void _paintCenter(Canvas canvas, double cx, double cy, Size size) {
    final text = center;
    if (text == null || text.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'Unbounded',
          fontSize: size.width * .17,
          fontWeight: FontWeight.w600,
          color: centerColor,
          height: 1,
        ),
      ),
      textDirection: textDirection,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _LoveShapePainter old) =>
      old.mine != mine ||
      old.theirs != theirs ||
      old.mineColor != mineColor ||
      old.theirsColor != theirsColor ||
      old.gridColor != gridColor ||
      old.center != center ||
      old.showLabels != showLabels;
}
