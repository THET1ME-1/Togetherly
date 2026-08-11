import 'package:flutter/material.dart';

import '../../services/locale_service.dart';

/// Окно наведения поверх камеры: тёмная вуаль с чистым квадратом в середине,
/// уголки по углам и бегущая полоса.
///
/// Квадрат тут не украшение: по [kQrWindowFraction] и рисуется рамка, и
/// режется область распознавания (`scanWindow` у сканера). Разъедутся — человек
/// наводит код в одну область, а читается другая.
///
/// Доля короткой стороны, которую занимает окно наведения.
const double kQrWindowFraction = 0.72;

class QrViewfinder extends StatefulWidget {
  const QrViewfinder({super.key, this.hint});

  /// Подпись под окном. По умолчанию — «Наведите на код партнёра».
  final String? hint;

  @override
  State<QrViewfinder> createState() => _QrViewfinderState();
}

class _QrViewfinderState extends State<QrViewfinder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep;

  @override
  void initState() {
    super.initState();
    _sweep = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hint = widget.hint ?? LocaleService.current.qrPointAtCode;
    final still = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return LayoutBuilder(
      builder: (context, constraints) {
        final short = constraints.biggest.shortestSide;
        final side = short * kQrWindowFraction;

        return Stack(
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _sweep,
                builder: (context, _) => CustomPaint(
                  painter: _ViewfinderPainter(
                    side: side,
                    sweep: still ? -1 : _sweep.value,
                  ),
                ),
              ),
            ),
            // Подпись под окном, а не поверх кадра: поверх её не прочесть ни
            // на светлом коде, ни на тёмном столе.
            Positioned(
              left: 24,
              right: 24,
              top: constraints.biggest.height / 2 + side / 2 + 26,
              child: Text(
                hint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ViewfinderPainter extends CustomPainter {
  _ViewfinderPainter({required this.side, required this.sweep});

  final double side;

  /// Доля пути бегущей полосы, `-1` — не рисовать её вовсе.
  final double sweep;

  static const double _radius = 28;
  static const double _cornerLength = 34;
  static const double _cornerWidth = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: side,
      height: side,
    );
    final window = RRect.fromRectAndRadius(rect, const Radius.circular(_radius));

    // Вуаль с дыркой: чётно-нечётное правило вырезает окно из залитого
    // прямоугольника одним слоем, без наложения четырёх полос по краям.
    final veil = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(window)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(veil, Paint()..color = const Color(0x99000000));

    final corner = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = _cornerWidth
      ..strokeCap = StrokeCap.round;

    // Уголки рисуем дугой в углу и двумя отрезками от неё: так они ложатся
    // ровно на скругление окна, а не срезают его.
    void drawCorner(Offset pivot, double dx, double dy, double startAngle) {
      final arcRect = Rect.fromCircle(
        center: pivot + Offset(dx * _radius, dy * _radius),
        radius: _radius,
      );
      canvas.drawArc(arcRect, startAngle, 1.5708, false, corner);
      canvas.drawLine(
        pivot + Offset(dx * _radius, 0),
        pivot + Offset(dx * (_radius + _cornerLength), 0),
        corner,
      );
      canvas.drawLine(
        pivot + Offset(0, dy * _radius),
        pivot + Offset(0, dy * (_radius + _cornerLength)),
        corner,
      );
    }

    drawCorner(rect.topLeft, 1, 1, 3.1416);
    drawCorner(rect.topRight, -1, 1, 4.7124);
    drawCorner(rect.bottomRight, -1, -1, 0);
    drawCorner(rect.bottomLeft, 1, -1, 1.5708);

    if (sweep < 0) return;
    // Полоса ходит внутри окна и гаснет к краям: показывает, что сканер жив,
    // и не спорит с самим кодом за внимание.
    final y = rect.top + rect.height * sweep;
    final line = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0x00FFFFFF), Color(0xCCFFFFFF), Color(0x00FFFFFF)],
      ).createShader(Rect.fromLTWH(rect.left, y - 1, rect.width, 2))
      ..strokeWidth = 2;
    canvas.save();
    canvas.clipRRect(window);
    canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), line);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ViewfinderPainter old) =>
      old.side != side || old.sweep != sweep;
}
