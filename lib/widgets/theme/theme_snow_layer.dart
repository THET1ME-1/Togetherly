import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/snow_fall.dart';
import '../../theme/app_theme.dart';

/// Снегопад темы «Новый год» за интерфейсом, под всеми вкладками: хлопья в
/// три глубины и изредка снежки.
///
/// Касаний слой не ловит: снежок ловится касанием пустого места, его главная
/// передаёт через [ThemeSnowLayerState.catchAt] (тот же путь, что ладонь у
/// хэллоуинского фона). Пойманный снежок рассыпается крошками на месте.
/// Выключенная в телефоне анимация останавливает снег, снежки не падают.
class ThemeSnowLayer extends StatefulWidget {
  const ThemeSnowLayer({super.key, required this.theme});

  final AppTheme theme;

  @override
  State<ThemeSnowLayer> createState() => ThemeSnowLayerState();
}

/// Картинка снежка — тот же снежок мастерской, что на значке темы.
const String kSnowballAsset = 'assets/images/themes/newyear_badge.webp';

class ThemeSnowLayerState extends State<ThemeSnowLayer> with SingleTickerProviderStateMixin {
  // Часы снегопада: длиннее любого полёта, дальше идут по кругу.
  late final AnimationController _clock =
      AnimationController(vsync: this, duration: const Duration(seconds: 3600));
  final List<SnowFlake> _flakes = snowFlakes();
  final Set<int> _caught = {};
  final List<_Poof> _poofs = [];
  Size _size = Size.zero;
  bool _still = false;

  double get _seconds => _clock.value * 3600;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    if (_still) {
      _clock.stop();
    } else if (!_clock.isAnimating && widget.theme.bgSnow != null) {
      _clock.repeat();
    }
  }

  @override
  void didUpdateWidget(ThemeSnowLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final on = widget.theme.bgSnow != null && !_still;
    if (on && !_clock.isAnimating) _clock.repeat();
    if (!on && _clock.isAnimating) _clock.stop();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  /// Поймать снежок под точкой [local] (координаты слоя). true — поймали:
  /// снежок рассыпался, вызывающий бросает его партнёру.
  bool catchAt(Offset local) {
    if (widget.theme.bgSnow == null || _still || _size == Size.zero) return false;
    final t = _seconds;
    final balls = snowballsAt(_size, t, _caught);
    final id = snowballHit(balls, local);
    if (id == null) return false;
    final ball = balls.firstWhere((b) => b.id == id);
    setState(() {
      _caught.add(id);
      _poofs.add(_Poof(ball.at, t));
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final snow = widget.theme.bgSnow;
    if (snow == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: LayoutBuilder(builder: (context, box) {
            _size = Size(box.maxWidth, box.maxHeight);
            return AnimatedBuilder(
              animation: _clock,
              builder: (context, _) {
                final t = _still ? 4.0 : _seconds;
                _poofs.removeWhere((p) => t - p.born > 0.9 || t < p.born);
                final balls = _still ? const <Snowball>[] : snowballsAt(_size, t, _caught);
                return Opacity(
                  opacity: snow.opacity,
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      Positioned.fill(child: CustomPaint(painter: _FlakesPainter(_flakes, t, snow.rim))),
                      for (final b in balls)
                        Positioned(
                          left: b.at.dx - b.radius * 1.15,
                          top: b.at.dy - b.radius * 1.15,
                          width: b.radius * 2.3,
                          height: b.radius * 2.3,
                          child: Transform.rotate(
                            angle: b.turn,
                            child: Image.asset(kSnowballAsset, gaplessPlayback: true, filterQuality: FilterQuality.medium),
                          ),
                        ),
                      if (_poofs.isNotEmpty) Positioned.fill(child: CustomPaint(painter: _PoofPainter(_poofs, t))),
                    ],
                  ),
                );
              },
            );
          }),
        ),
      ),
    );
  }
}

class _Poof {
  _Poof(this.at, this.born);
  final Offset at;
  final double born;
}

class _FlakesPainter extends CustomPainter {
  _FlakesPainter(this.flakes, this.t, this.rim);
  final List<SnowFlake> flakes;
  final double t;
  final Color rim;

  @override
  void paint(Canvas canvas, Size size) {
    final white = Paint();
    final edge = Paint();
    final hasRim = rim.a > 0;
    for (final f in flakes) {
      final p = flakePosition(f, size, t);
      if (hasRim) {
        edge.color = rim.withValues(alpha: rim.a * f.alpha);
        canvas.drawCircle(p, f.radius + 0.9, edge);
      }
      white.color = Colors.white.withValues(alpha: f.alpha);
      canvas.drawCircle(p, f.radius, white);
    }
  }

  @override
  bool shouldRepaint(_FlakesPainter old) => old.t != t || old.rim != rim;
}

/// Крошки пойманного снежка: десять комочков разлетаются и падают за 0,9 с.
class _PoofPainter extends CustomPainter {
  _PoofPainter(this.poofs, this.t);
  final List<_Poof> poofs;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = Colors.white;
    final ink = Paint()
      ..color = const Color(0xFF2A2D30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (final p in poofs) {
      final u = (t - p.born).clamp(0.0, 0.9);
      final fade = 1 - u / 0.9;
      for (var i = 0; i < 10; i++) {
        final a = i / 10 * 2 * math.pi + 0.3 * math.sin(i * 2.7);
        final speed = 60 + 40 * ((i * 37) % 10) / 10;
        final at = p.at + Offset(math.cos(a) * speed * u, math.sin(a) * speed * u - 40 * u + 130 * u * u);
        final r = (2 + (i % 3)) * (0.6 + 0.4 * fade);
        fill.color = Colors.white.withValues(alpha: fade);
        ink.color = const Color(0xFF2A2D30).withValues(alpha: fade);
        canvas.drawCircle(at, r, fill);
        canvas.drawCircle(at, r, ink);
      }
    }
  }

  @override
  bool shouldRepaint(_PoofPainter old) => true;
}
