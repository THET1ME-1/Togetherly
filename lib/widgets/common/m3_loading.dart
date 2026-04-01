import 'package:flutter/material.dart';

/// MD3 Material You bouncing dots loading indicator.
///
/// Three dots bounce in a staggered wave pattern with glow effects.
/// Adapts to any theme via [color].
class M3LoadingDots extends StatefulWidget {
  final Color color;
  final double dotSize;
  final double gap;

  const M3LoadingDots({
    super.key,
    required this.color,
    this.dotSize = 10,
    this.gap = 5,
  });

  @override
  State<M3LoadingDots> createState() => _M3LoadingDotsState();
}

class _M3LoadingDotsState extends State<M3LoadingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Bounce curve: quick rise → brief hold → smooth fall → rest.
  double _wave(double t) {
    if (t < 0.18) return Curves.easeOutQuart.transform(t / 0.18);
    if (t < 0.28) return 1.0;
    if (t < 0.48) {
      return Curves.easeInQuart.transform(1.0 - (t - 0.28) / 0.20);
    }
    return 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.dotSize;
    return SizedBox(
      height: d * 2.8,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(3, (i) {
            final phase = ((_ctrl.value - i * 0.16) % 1.0 + 1.0) % 1.0;
            final w = _wave(phase);
            final scale = 1.0 + w * 0.22;
            final opacity = w > 0.01 ? 0.55 + 0.45 * w : 0.4;

            return Padding(
              padding: EdgeInsets.only(left: i > 0 ? widget.gap : 0),
              child: Transform.translate(
                offset: Offset(0, -w * d * 1.2),
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    width: d,
                    height: d,
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: opacity),
                      shape: BoxShape.circle,
                      boxShadow: w > 0.1
                          ? [
                              BoxShadow(
                                color: widget.color.withValues(alpha: 0.3 * w),
                                blurRadius: d * w,
                                spreadRadius: d * 0.1 * w,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// Full-page centered MD3 loading indicator.
class M3PageLoading extends StatelessWidget {
  final Color color;

  const M3PageLoading({super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return Center(child: M3LoadingDots(color: color, dotSize: 12, gap: 6));
  }
}
