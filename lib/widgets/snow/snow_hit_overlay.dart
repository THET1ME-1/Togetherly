import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../dict_strings.dart';
import '../../services/snowball_service.dart';
import '../theme/theme_snow_layer.dart';

/// Попадание снежка поверх любого экрана (тема «Новый год», вариант «А. В
/// стекло», выбор владельца 27.11.2026): снежок прилетает из глубины и
/// шлёпается о стекло экрана, пятно с лучами и каплями держится, медленно
/// сползает и тает. Сверху плашка «Снежок от {имя}» и «Кинуть в ответ».
/// Всё уходит само через 3,4 с. Касания под снегом не ловятся, кроме кнопки.
class SnowHitOverlay extends StatelessWidget {
  const SnowHitOverlay({super.key, required this.child, this.onThrowBack});

  final Widget child;

  /// «Кинуть в ответ». По умолчанию — бросок в текущую пару.
  final VoidCallback? onThrowBack;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        ValueListenableBuilder<SnowHit?>(
          valueListenable: SnowballService.instance.current,
          builder: (context, hit, _) => hit == null
              ? const SizedBox.shrink()
              : _HitScene(
                  key: ValueKey(hit.serial),
                  hit: hit,
                  onBack: onThrowBack ?? () => unawaited(SnowballService.instance.throwBack()),
                ),
        ),
      ],
    );
  }
}

/// Длина попадания и когда видна плашка, секунды.
const double _kTotal = 3.4, _kPillFrom = 0.8, _kPillTo = 3.2, _kHitAt = 0.5;

class _HitScene extends StatefulWidget {
  const _HitScene({super.key, required this.hit, required this.onBack});
  final SnowHit hit;
  final VoidCallback onBack;

  @override
  State<_HitScene> createState() => _HitSceneState();
}

class _HitSceneState extends State<_HitScene> with SingleTickerProviderStateMixin {
  late final AnimationController _t =
      AnimationController(vsync: this, duration: Duration(milliseconds: (_kTotal * 1000).round()));
  final double _seed = math.Random().nextDouble() * 6.28;
  Timer? _stillTimer;
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_t.isAnimating || _stillTimer != null || _t.isCompleted) return;
    _still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_still) {
      // Без анимации — один спокойный кадр с пятном и плашкой.
      _t.value = 1.2 / _kTotal;
      _stillTimer = Timer(const Duration(milliseconds: 3400), _finish);
    } else {
      _t.forward().whenComplete(_finish);
    }
  }

  void _finish() {
    if (mounted) SnowballService.instance.done(widget.hit);
  }

  @override
  void dispose() {
    _stillTimer?.cancel();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final top = MediaQuery.paddingOf(context).top + 12;
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final t = _t.value * _kTotal;
        final pill = _still || (t >= _kPillFrom && t <= _kPillTo);
        return Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: LayoutBuilder(builder: (context, box) {
                final size = Size(box.maxWidth, box.maxHeight);
                if (t < _kHitAt) return Stack(children: [_incoming(size, t / _kHitAt)]);
                return CustomPaint(size: size, painter: SnowSplatPainter(t - _kHitAt, _seed));
              }),
            ),
            Positioned(
              left: 16,
              right: 16,
              top: top,
              child: IgnorePointer(
                ignoring: !pill,
                child: AnimatedOpacity(
                  opacity: pill ? 1 : 0,
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutCubic,
                  child: _pill(cs),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Снежок летит из глубины к стеклу и растёт по перспективе.
  Widget _incoming(Size size, double u) {
    final k = Curves.easeInOutCubic.transform(u.clamp(0.0, 1.0));
    final sx = size.width / 360, sy = size.height / 780;
    final x = (250 - 70 * k) * sx, y = (220 + 150 * k - 30 * math.sin(math.pi * k)) * sy;
    final r = (6 + 70 * k * k) * sx;
    return Positioned(
      left: x - r * 1.15,
      top: y - r * 1.15,
      width: r * 2.3,
      height: r * 2.3,
      child: Transform.rotate(angle: k * 3, child: Image.asset(kSnowballAsset, gaplessPlayback: true)),
    );
  }

  Widget _pill(ColorScheme cs) {
    final h = widget.hit;
    final name = h.from.isEmpty ? trKey('snow.partner') : h.from;
    final sub = h.count > 1 ? trKey('snow.hits').replaceAll('{n}', '${h.count}') : trKey('snow.hit');
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(26),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        child: Row(
          children: [
            Image.asset(kSnowballAsset, width: 30, height: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(trKey('snow.from').replaceAll('{name}', name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'Onest', fontWeight: FontWeight.w600, fontSize: 14.5, color: cs.onSurface)),
                  Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'Onest', fontSize: 12.5, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: widget.onBack,
              icon: const Icon(Icons.ac_unit_rounded, size: 18),
              label: Text(trKey('snow.back'), style: const TextStyle(fontFamily: 'Onest', fontWeight: FontWeight.w700, fontSize: 13)),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: const StadiumBorder(),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Пятно снега на стекле через [u] секунд после удара: пухлые языки брызг с
/// круглыми концами, тень серпом справа снизу, блик, отлетевшие капли.
/// Держится, через секунду сползает вниз и вытягивается, потом тает. Порт
/// варианта «А. В стекло» из макета (togetherly-newyear-theme-mockup).
class SnowSplatPainter extends CustomPainter {
  SnowSplatPainter(this.u, this.seed);
  final double u;
  final double seed;

  static const _ink = Color(0xFF2A2D30);

  static double _ease(double x) => x <= 0 ? 0 : x >= 1 ? 1 : 1 - math.pow(1 - x, 3).toDouble();
  static double _easeIO(double x) =>
      x <= 0 ? 0 : x >= 1 ? 1 : (x < 0.5 ? 4 * x * x * x : 1 - math.pow(-2 * x + 2, 3) / 2).toDouble();

  @override
  void paint(Canvas canvas, Size size) {
    final pop = _ease(u / 0.22), slide = _easeIO((u - 1.0) / 1.4), fade = 1 - _easeIO((u - 1.7) / 0.8);
    if (fade <= 0) return;
    final k = size.width / 360;
    final cx = size.width * 0.49, cy = size.height * 0.49 + 130 * k * slide;
    final r = 104 * k * (0.6 + 0.4 * pop);
    final arms = [
      for (var i = 0; i < 9; i++)
        () {
          final q = math.sin(seed * 7.1 + i * 12.9) * 0.5 + 0.5;
          return (
            a: i / 9 * 2 * math.pi + seed + 0.25 * math.sin(i * 4.3),
            len: (0.22 + 0.38 * q) * r * pop,
            w: 0.42 + 0.12 * math.sin(i * 2.7 + seed),
            tip: (0.2 + 0.08 * q) * r,
          );
        }(),
    ];
    double stretchAt(double a) => 1 + 0.35 * slide * math.max(0, math.sin(a));

    Path shape(double grow) {
      final p = Path();
      for (var j = 0; j <= 240; j++) {
        final a = j / 240 * 2 * math.pi;
        var rad = r * (1 + 0.05 * math.sin(5 * a + seed)) + grow;
        for (final m in arms) {
          final d = math.atan2(math.sin(a - m.a), math.cos(a - m.a)).abs();
          rad += m.len * math.pow(math.max(0, math.cos(math.min(math.pi / 2, d / m.w))), 2.2);
        }
        final pt = Offset(cx + math.cos(a) * rad, cy + math.sin(a) * rad * stretchAt(a));
        j == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
      }
      p.close();
      // Круглые кончики языков — кружки в том же пути: заливка склеивает их с
      // пятном, а обводка, перекрытая заливкой, остаётся только снаружи.
      for (final m in arms) {
        final d = r + m.len - m.tip * 0.4;
        p.addOval(Rect.fromCircle(center: Offset(cx + math.cos(m.a) * d, cy + math.sin(m.a) * d * stretchAt(m.a)), radius: m.tip + grow));
      }
      return p;
    }

    canvas.saveLayer(Offset.zero & size, Paint()..color = Colors.white.withValues(alpha: fade));
    final white = Paint()..color = Colors.white;
    canvas.drawPath(shape(6 * k), white); // белая наклейка вокруг, как у всех рисунков приложения
    final body = shape(0);
    canvas.drawPath(body, Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.6 * k
      ..strokeJoin = StrokeJoin.round);
    canvas.drawPath(body, white);
    // Тень серпом справа снизу: голубая подложка, сверху белое ядро со сдвигом.
    canvas.save();
    canvas.clipPath(body);
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFCFE0F3));
    canvas.drawOval(Rect.fromCenter(center: Offset(cx - r * 0.12, cy - r * 0.14), width: r * 3.24, height: r * 3.04), white);
    final dent = Paint()..color = const Color(0xFFE3EDF8);
    for (final (dx, dy, s) in const [(-0.3, 0.2, 6.0), (0.25, -0.25, 4.5), (0.4, 0.35, 5.0), (-0.1, -0.45, 3.5), (0.05, 0.1, 7.0)]) {
      canvas.drawOval(Rect.fromCenter(center: Offset(cx + dx * r, cy + dy * r), width: s * 2 * k, height: s * 1.4 * k), dent);
    }
    canvas.restore();
    // Блик слева сверху.
    canvas.save();
    canvas.translate(cx - r * 0.42, cy - r * 0.42);
    canvas.rotate(-0.7);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: r * 0.4, height: r * 0.18), white);
    canvas.restore();
    // Капли, отлетевшие от концов языков; после удара чуть стекают.
    final ring = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2 * k;
    for (var i = 0; i < arms.length; i += 2) {
      final m = arms[i];
      final d = r + m.len + (10 + 8 * (i % 3) + 14 * pop) * k;
      final c = Offset(cx + math.cos(m.a) * d, cy + math.sin(m.a) * d + 30 * k * _easeIO((u - 0.4) / 1.6));
      final rr = (4 + 2.5 * ((i ~/ 2) % 3)) * k;
      canvas.drawCircle(c, rr + 3 * k, white);
      canvas.drawCircle(c, rr, white);
      canvas.drawCircle(c, rr, ring);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(SnowSplatPainter old) => old.u != u || old.seed != seed;
}
