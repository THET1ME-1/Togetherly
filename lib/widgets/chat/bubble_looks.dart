import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../models/chat_look.dart';

/// Тушь и её светлый тон — те же, что у значков (`badges.js`).
const Color kStickerInk = Color(0xFF2A2D30);
const Color kStickerInk2 = Color(0xFF5D5F62);

/// Поля вокруг тела наклейки: туда ложатся белая кайма и контур.
const double kStickerInset = 5;

/// Общие часы дрожи для всех наклеек экрана.
///
/// Один тикер на экран, а не на пузырь: кадр меняется восемь раз в секунду, и
/// каждая наклейка перерисовывается по [frame] через `repaint`, дерево виджетов
/// не пересобирается. Скрытый экран тикер глушит сам (`TickerMode`), при
/// «уменьшить движение» он не запускается вовсе.
class StickerBoilScope extends StatefulWidget {
  const StickerBoilScope({
    super.key,
    required this.active,
    required this.child,
  });

  /// Идёт ли дрожь: только когда выбрана «Наклейка».
  final bool active;
  final Widget child;

  /// Кадр дрожи ближайшей области; вне области — null (наклейка стоит).
  static ValueListenable<int>? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_BoilInherited>()?.frame;

  @override
  State<StickerBoilScope> createState() => _StickerBoilScopeState();
}

class _StickerBoilScopeState extends State<StickerBoilScope>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<int> _frame = ValueNotifier(0);
  late final Ticker _ticker = createTicker((e) {
    final f = stickerFrameAt(e);
    if (f != _frame.value) _frame.value = f;
  });

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  void _sync() {
    final run = widget.active && !_still;
    if (run && !_ticker.isActive) {
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
      _frame.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(StickerBoilScope old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _BoilInherited(frame: _frame, child: widget.child);
}

class _BoilInherited extends InheritedWidget {
  const _BoilInherited({required this.frame, required super.child});
  final ValueNotifier<int> frame;
  @override
  bool updateShouldNotify(_BoilInherited old) => old.frame != frame;
}

/// Готовая геометрия одной наклейки: тело, штриховка и три кадра контура.
class _StickerShape {
  _StickerShape(this.body, this.hatchClip, this.hatch, this.lines);
  final Path body;
  final Path hatchClip;
  final Path hatch;
  final List<Path> lines;
}

/// Геометрия считается один раз на пузырь и размер, дальше кадр только
/// переключается. Кэш ограничен: лента длинная, а видно десяток пузырей.
final LinkedHashMap<String, _StickerShape> _shapes = LinkedHashMap();
const int _kShapeCacheLimit = 160;

_StickerShape _shapeFor(Size size, int seed) {
  final key = '$seed|${size.width.round()}|${size.height.round()}';
  final hit = _shapes.remove(key);
  if (hit != null) return _shapes[key] = hit;

  final rect = Rect.fromLTWH(
    kStickerInset,
    kStickerInset,
    size.width - 2 * kStickerInset,
    size.height - 2 * kStickerInset,
  );
  final base = handRoundRect(rect, 16, HandRandom(seed), wobble: 0);
  List<Offset> shake(List<Offset> pts, double a, int s) {
    final r = HandRandom(s);
    return [
      for (final p in pts)
        Offset(p.dx + (r.next() - .5) * 2 * a, p.dy + (r.next() - .5) * 2 * a),
    ];
  }

  final body = handCurve(shake(base, .5, seed), closed: true);
  // Штриховка ложится полосой по теневому краю: форма минус её копия,
  // сдвинутая к свету — как маска в `hatch()` мастерской.
  final hatchClip = Path.combine(
    PathOperation.difference,
    body,
    body.shift(const Offset(-5, -6)),
  );
  final hatch = Path();
  final r = HandRandom(seed + 11);
  const ang = 35 * math.pi / 180;
  final dx = math.cos(ang), dy = math.sin(ang);
  final len = size.longestSide + 30;
  final c = size.center(Offset.zero);
  for (var t = -len; t < len; t += 4.4) {
    final cx = c.dx - dy * t, cy = c.dy + dx * t;
    final l1 = len * (.45 + r.next() * .1), l2 = len * (.45 + r.next() * .1);
    hatch
      ..moveTo(cx - dx * l1, cy - dy * l1)
      ..lineTo(cx + dx * l2, cy + dy * l2);
  }
  final lines = [
    for (var k = 0; k < kStickerFrames; k++)
      handContour(
        shake(base, .9, seed + k * 977),
        HandRandom(seed + k * 977 + 5),
      ),
  ];
  final shape = _StickerShape(body, hatchClip, hatch, lines);
  _shapes[key] = shape;
  if (_shapes.length > _kShapeCacheLimit) _shapes.remove(_shapes.keys.first);
  return shape;
}

/// Пузырь-наклейка: белая кайма, заливка, штриховка, контур тушью.
class StickerBubblePainter extends CustomPainter {
  StickerBubblePainter({required this.color, required this.seed, this.frame})
    : super(repaint: frame);

  final Color color;
  final int seed;

  /// Кадр дрожи; null — наклейка стоит на первом кадре.
  final ValueListenable<int>? frame;

  static final Paint _rim = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 10
    ..strokeJoin = StrokeJoin.round;
  static final Paint _hatch = Paint()
    ..color = kStickerInk2.withValues(alpha: .5)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2
    ..strokeCap = StrokeCap.round;
  static final Paint _line = Paint()
    ..color = kStickerInk
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.6
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 24 || size.height < 24) return;
    final s = _shapeFor(size, seed);
    canvas.drawPath(s.body, _rim);
    canvas.drawPath(s.body, Paint()..color = color);
    canvas
      ..save()
      ..clipPath(s.hatchClip)
      ..drawPath(s.hatch, _hatch)
      ..restore();
    canvas.drawPath(s.lines[(frame?.value ?? 0) % kStickerFrames], _line);
  }

  @override
  bool shouldRepaint(StickerBubblePainter old) =>
      old.color != color || old.seed != seed || old.frame != frame;
}

/// Пузырь «Пиксель»: ступенчатые углы и хвостик-лесенка со стороны автора.
class PixelBubblePainter extends CustomPainter {
  const PixelBubblePainter({required this.color, required this.tailLeft});

  final Color color;
  final bool tailLeft;

  static const double step = 6;

  /// Сколько места снизу занимает хвостик.
  static const double tailDrop = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final bodyH = size.height - tailDrop;
    final paint = Paint()
      ..color = color
      ..isAntiAlias = false;
    canvas.drawPath(
      pixelRect(Rect.fromLTWH(0, 0, size.width, bodyH), step),
      paint,
    );
    final x = tailLeft ? step : size.width - 3 * step;
    canvas.drawRect(Rect.fromLTWH(x, bodyH - 1, 2 * step, step + 1), paint);
    canvas.drawRect(
      Rect.fromLTWH(
        tailLeft ? 0 : size.width - step,
        bodyH + step - 1,
        step,
        step + 1,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(PixelBubblePainter old) =>
      old.color != color || old.tailLeft != tailLeft;
}
