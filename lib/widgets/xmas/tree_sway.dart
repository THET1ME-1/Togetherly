import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/xmas_tree_geometry.dart';
import 'tree_draw.dart';

/// Поворот ёлки в момент [phase] (доля семисекундного круга) при размахе
/// [amp] (0 — стоит, 1 — качается во всю силу), как `xt3Sway` в макете:
/// ±0,07 рад вокруг оси.
double xtSwayYaw(double phase, double amp) => xtQuantizeYaw(kXtYaw + 0.07 * amp * math.sin(phase * math.pi * 2));

/// Покачивание ёлки (макет «Наряжаем ёлку»: «ёлка чуть покачивается, игрушки
/// висят на хвое и едут вместе с ней»). [builder] получает поворот; кадр
/// перестраивается, только когда поворот сменил шаг [kXtYawStep].
///
/// [calm] — ёлка плавно встаёт в обычный поворот: игрушка в руке, вешать на
/// качающиеся ветки неудобно. Без анимаций в системе ёлка стоит.
class XtSway extends StatefulWidget {
  const XtSway({super.key, this.calm = false, required this.builder});

  final bool calm;
  final Widget Function(BuildContext context, double yaw) builder;

  @override
  State<XtSway> createState() => _XtSwayState();
}

class _XtSwayState extends State<XtSway> with TickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(vsync: this, duration: const Duration(seconds: 7));
  late final AnimationController _amp = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
    value: widget.calm ? 0 : 1,
  );
  final ValueNotifier<double> _yaw = ValueNotifier(kXtYaw);
  bool _still = false;

  @override
  void initState() {
    super.initState();
    _clock.addListener(_tick);
    _amp.addListener(_tick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    if (_still) {
      _clock.stop();
      _yaw.value = kXtYaw;
    } else if (!_clock.isAnimating) {
      _clock.repeat();
    }
  }

  @override
  void didUpdateWidget(XtSway old) {
    super.didUpdateWidget(old);
    if (old.calm != widget.calm) _amp.animateTo(widget.calm ? 0 : 1, curve: Curves.easeInOut);
  }

  void _tick() {
    if (_still) return;
    _yaw.value = xtSwayYaw(_clock.value, _amp.value);
  }

  @override
  void dispose() {
    _clock.dispose();
    _amp.dispose();
    _yaw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: _yaw,
      builder: (context, yaw, _) => widget.builder(context, yaw),
    );
  }
}
