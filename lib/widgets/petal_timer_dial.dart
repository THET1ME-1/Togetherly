import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// Data for a single petal segment.
class _PetalData {
  final String label;
  final int value;
  final int maxValue;
  final double exactValue;

  const _PetalData({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.exactValue,
  });

  /// Normalised 0..1 brightness factor based on exact continuous value.
  double get factor => maxValue > 0 ? (exactValue / maxValue).clamp(0.0, 1.0) : 0.0;
}

/// A donut-like diagram with 6 rounded petal segments arranged in a ring.
///
/// Each segment represents: Years, Months, Days, Hours, Minutes, Seconds.
/// The ring can be rotated by finger drag (with physics-based inertia).
/// Segment brightness depends on their value; size is identical for all.
class PetalTimerDial extends StatefulWidget {
  /// Application theme for colours
  final AppTheme theme;

  /// Start date for computing elapsed time.
  final DateTime startDate;

  /// Whether the timer counts down instead of up.
  final bool isCountdown;

  const PetalTimerDial({
    super.key,
    required this.theme,
    required this.startDate,
    this.isCountdown = false,
  });

  @override
  State<PetalTimerDial> createState() => _PetalTimerDialState();
}

class _PetalTimerDialState extends State<PetalTimerDial>
    with TickerProviderStateMixin {
  double _rotationAngle = 0.0;
  double _prevAngle = 0.0;

  late AnimationController _flingCtrl;
  late Ticker _chaseTicker;
  List<double> _displayFactors = List.filled(6, 0.0);
  List<_PetalData> _currentPetals = [];

  @override
  void initState() {
    super.initState();
    _flingCtrl = AnimationController.unbounded(vsync: this);
    _flingCtrl.addListener(_onFlingTick);
    _chaseTicker = createTicker(_onChaseTick)..start();
  }

  void _onChaseTick(Duration elapsed) {
    _currentPetals = _computePetals();
    bool changed = false;
    for (int i = 0; i < 6; i++) {
        final target = _currentPetals[i].factor;
        final diff = target - _displayFactors[i];
        if (diff.abs() > 0.0005) {
            _displayFactors[i] += diff * 0.15;
            changed = true;
        } else if (_displayFactors[i] != target) {
            _displayFactors[i] = target;
            changed = true;
        }
    }
    if (changed && mounted) {
        setState(() {});
    }
  }

  @override
  void dispose() {
    _flingCtrl.dispose();
    _chaseTicker.dispose();
    super.dispose();
  }

  void _onFlingTick() {
    setState(() {
      _rotationAngle = _flingCtrl.value;
    });
  }

  Offset _center = Offset.zero;

  void _onPanStart(DragStartDetails d) {
    _flingCtrl.stop();
    final box = context.findRenderObject() as RenderBox;
    _center = box.size.center(Offset.zero);
    _prevAngle = _angleOf(d.localPosition);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final newAngle = _angleOf(d.localPosition);
    var delta = newAngle - _prevAngle;
    if (delta > math.pi) delta -= 2 * math.pi;
    if (delta < -math.pi) delta += 2 * math.pi;
    setState(() {
      _rotationAngle += delta;
    });
    _prevAngle = newAngle;
  }

  void _onPanEnd(DragEndDetails d) {
    final vx = d.velocity.pixelsPerSecond.dx;
    final vy = d.velocity.pixelsPerSecond.dy;
    final radius = _center.dx.abs().clamp(60.0, 200.0);
    var angularVelocity = (vx.abs() + vy.abs()) / radius;
    final sign = _tangentSign(d.velocity.pixelsPerSecond);
    angularVelocity *= sign;

    _flingCtrl.value = _rotationAngle;
    final simulation = FrictionSimulation(
      0.0008,
      _rotationAngle,
      angularVelocity,
    );
    _flingCtrl.animateWith(simulation);
  }

  double _angleOf(Offset pos) {
    return math.atan2(pos.dy - _center.dy, pos.dx - _center.dx);
  }

  double _tangentSign(Offset velocity) {
    final cross = -velocity.dx * 0.5 + velocity.dy * 0.5;
    return cross >= 0 ? 1.0 : -1.0;
  }

  List<_PetalData> _computePetals() {
    final now = DateTime.now();
    Duration diff;
    if (widget.isCountdown) {
      diff = widget.startDate.difference(now);
    } else {
      diff = now.difference(widget.startDate);
    }

    final totalMs = diff.inMilliseconds.abs();
    final totalSec = totalMs / 1000.0;

    final yearsInt = (totalSec / (365.25 * 24 * 3600)).floor();
    final monthsInt = (totalSec / (30.44 * 24 * 3600)).floor() % 12;
    final daysInt = (totalSec / 86400).floor() % 30;
    final hoursInt = (totalSec / 3600).floor() % 24;
    final minutesInt = (totalSec / 60).floor() % 60;
    final secondsInt = totalSec.floor() % 60;

    final exactSeconds = totalSec % 60.0;
    final exactMinutes = (totalSec / 60.0) % 60.0;
    final exactHours = (totalSec / 3600.0) % 24.0;
    final exactDays = (totalSec / 86400.0) % 30.0;
    final exactMonths = (totalSec / (30.44 * 24 * 3600.0)) % 12.0;
    final exactYears = totalSec / (365.25 * 24 * 3600.0);

    return [
      _PetalData(label: 'Years', value: yearsInt, maxValue: math.max(10, yearsInt.clamp(10, 100)), exactValue: exactYears),
      _PetalData(label: 'Months', value: monthsInt, maxValue: 12, exactValue: exactMonths),
      _PetalData(label: 'Days', value: daysInt, maxValue: 30, exactValue: exactDays),
      _PetalData(label: 'Hours', value: hoursInt, maxValue: 24, exactValue: exactHours),
      _PetalData(label: 'Min', value: minutesInt, maxValue: 60, exactValue: exactMinutes),
      _PetalData(label: 'Sec', value: secondsInt, maxValue: 60, exactValue: exactSeconds),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (_currentPetals.isEmpty) {
      _currentPetals = _computePetals();
      _displayFactors = _currentPetals.map((p) => p.factor).toList();
    }
    final petals = _currentPetals;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Find the maximum available square size
        final size = math.min(constraints.maxWidth, constraints.maxHeight);
        // Base scale factor. 280 was the original hardcoded size.
        final scale = size / 280.0;

        return GestureDetector(
          onScaleStart: (details) => _onPanStart(DragStartDetails(
              localPosition: details.localFocalPoint, 
              globalPosition: details.focalPoint)),
          onScaleUpdate: (details) => _onPanUpdate(DragUpdateDetails(
              localPosition: details.localFocalPoint, 
              globalPosition: details.focalPoint,
              delta: details.focalPointDelta)),
          onScaleEnd: (details) => _onPanEnd(DragEndDetails(
              velocity: details.velocity)),
          child: SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _PetalDialPainter(
                petals: petals,
                displayFactors: _displayFactors,
                rotationAngle: _rotationAngle,
                theme: widget.theme,
                scale: scale,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PetalDialPainter extends CustomPainter {
  final List<_PetalData> petals;
  final List<double> displayFactors;
  final double rotationAngle;
  final AppTheme theme;
  final double scale;

  _PetalDialPainter({
    required this.petals,
    required this.displayFactors,
    required this.rotationAngle,
    required this.theme,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    
    // Outer boundary of the entire widget
    final outerR = math.min(cx, cy) - 2;
    // Tiny hole inside, matching the photo (~15%)
    final innerR = outerR * 0.15;

    // Corner radius of EVERY edge
    final cr = 4.0 * scale;
    
    // Width of the parallel gap lines separating the petals
    final gapWidth = 6.0 * scale;

    // We shrink logical parameters to leave room for the `cr` thick round stroke.
    // When the fill+stroke is combined, the visual gap and corner radii are exactly as requested.
    final rigidInner = innerR + cr;
    final rigidOuter = outerR - cr;
    final h = (gapWidth / 2) + cr; 

    final totalAngle = 2 * math.pi / petals.length;

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(rotationAngle);

    for (int i = 0; i < petals.length; i++) {
      final petal = petals[i];
      
      // Rotate canvas per-segment so the petal is constructed along the local X-axis (angle 0).
      // i=0 is top (-pi/2), so:
      final segAngle = -math.pi / 2 + i * totalAngle;
      
      canvas.save();
      canvas.rotate(segAngle);

      // ── 1. Draw Background Track (the placeholder for max value) ──
      // Фон лепестков берётся из новой настройки темы
      final bgPath = _buildParallelRigidSector(rigidOuter, rigidInner, h);
      
      final bgPaintFill = Paint()
        ..color = theme.timerDialBackground
        ..style = PaintingStyle.fill;
      
      final bgPaintStroke = Paint()
        ..color = theme.timerDialBackground
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = cr * 2;
        
      canvas.drawPath(bgPath, bgPaintFill);
      canvas.drawPath(bgPath, bgPaintStroke);

      // ── 2. Draw Bright Value Segment ──
      final factor = displayFactors[i].clamp(0.0, 1.0);
      
      if (factor > 0.01) {
        final currentOuterR = innerR + (outerR - innerR) * factor;
        final rigidFgOuter = math.max(rigidInner + 0.1, currentOuterR - cr);
        
        final fgPath = _buildParallelRigidSector(rigidFgOuter, rigidInner, h);

        // Цвет заполнения как у иконок в навигации (theme.navActiveIcon)
        final fgColor = theme.navActiveIcon;

        final fgPaintFill = Paint()
          ..color = fgColor
          ..style = PaintingStyle.fill;
        
        final fgPaintStroke = Paint()
          ..color = fgColor
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = cr * 2;
          
        canvas.drawPath(fgPath, fgPaintFill);
        canvas.drawPath(fgPath, fgPaintStroke);
      }

      // ── 3. Draw Text ──
      final textR = (innerR + outerR) / 2;
      final txColor = Colors.white.withValues(alpha: 0.95);

      canvas.save();
      canvas.translate(textR, 0);
      canvas.rotate(-(rotationAngle + segAngle));

      _drawText(
        canvas,
        text: '${petal.value}',
        x: 0,
        y: -8 * scale,
        fontSize: 18 * scale,
        fontWeight: FontWeight.w800,
        color: txColor,
        counterRotation: 0,
      );

      _drawText(
        canvas,
        text: petal.label,
        x: 0,
        y: 10 * scale,
        fontSize: 9 * scale,
        fontWeight: FontWeight.w600,
        color: txColor.withValues(alpha: 0.65),
        counterRotation: 0,
      );

      canvas.restore();

      canvas.restore();
    }

    canvas.restore();
  }

  Path _buildParallelRigidSector(double outer, double inner, double h) {
    final path = Path();
    
    // Bounds for 6 total segments (2 * pi / 6).
    const topA = math.pi / 6;
    const botA = -math.pi / 6;

    if (outer <= h || outer <= inner) return path;

    // Outer intersections
    final tOut = math.sqrt(outer * outer - h * h);
    final pOutTop = Offset(tOut * math.cos(topA) + h * math.sin(topA), tOut * math.sin(topA) - h * math.cos(topA));
    final pOutBot = Offset(tOut * math.cos(botA) - h * math.sin(botA), tOut * math.sin(botA) + h * math.cos(botA));

    double tIn = 0;
    Offset pInTop = Offset.zero;
    Offset pInBot = Offset.zero;

    if (inner > h) {
      tIn = math.sqrt(inner * inner - h * h);
      pInTop = Offset(tIn * math.cos(topA) + h * math.sin(topA), tIn * math.sin(topA) - h * math.cos(topA));
      pInBot = Offset(tIn * math.cos(botA) - h * math.sin(botA), tIn * math.sin(botA) + h * math.cos(botA));
    } else {
      final xIntersect = h / math.sin(math.pi / 6);
      pInTop = Offset(xIntersect, 0);
      pInBot = Offset(xIntersect, 0);
    }

    final aOutTop = math.atan2(pOutTop.dy, pOutTop.dx);
    final aOutBot = math.atan2(pOutBot.dy, pOutBot.dx);

    path.moveTo(pInBot.dx, pInBot.dy);
    path.lineTo(pOutBot.dx, pOutBot.dy);
    
    if (aOutTop > aOutBot) {
      path.arcTo(Rect.fromCircle(center: Offset.zero, radius: outer),
                 aOutBot, aOutTop - aOutBot, false);
    }
    
    path.lineTo(pInTop.dx, pInTop.dy);
    
    if (inner > h) {
      final aInTop = math.atan2(pInTop.dy, pInTop.dx);
      final aInBot = math.atan2(pInBot.dy, pInBot.dx);
      path.arcTo(Rect.fromCircle(center: Offset.zero, radius: inner),
                 aInTop, aInBot - aInTop, false);
    } else {
      path.lineTo(pInBot.dx, pInBot.dy);
    }
    
    path.close();
    return path;
  }

  void _drawText(
    Canvas canvas, {
    required String text,
    required double x,
    required double y,
    required double fontSize,
    required FontWeight fontWeight,
    required Color color,
    required double counterRotation,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: GoogleFonts.rubik(
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();

    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(counterRotation);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PetalDialPainter old) =>
      old.rotationAngle != rotationAngle || 
      old.petals != petals || 
      old.displayFactors != displayFactors ||
      old.scale != scale;
}
