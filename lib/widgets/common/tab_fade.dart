import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../unfold/unfold_touch.dart' show unfoldSnapshot;

/// Смена вкладки проявлением: прежняя гаснет за 90 мс, новая проявляется
/// следом и чуть подрастает. Шапка и нижняя панель в это не входят и стоят.
///
/// Вкладки равноправны, расти им не из чего, поэтому движение спокойное и не
/// зависит от их порядка — порядок с Togetherly+ переставляют (макет
/// 11.10.2026, сцена «Вкладки», вариант «Проявление»).
///
/// Прежнюю вкладку держит её снимок, а не она сама: живой экземпляр вкладки
/// всегда один. Иначе при быстром «туда и обратно» в дереве оказались бы две
/// главные с одними и теми же `GlobalKey`.
class TabFade extends StatefulWidget {
  const TabFade({super.key, required this.index, required this.child});

  /// Номер вкладки: его смена и запускает проявление.
  final int index;
  final Widget child;

  static const double totalMs = 300;
  static const double oldMs = 90;

  static double _unit(double value) => value.clamp(0.0, 1.0).toDouble();

  static double oldOpacity(double ms) => 1 - _unit(ms / oldMs);

  static double newOpacity(double ms) =>
      _unit((ms - oldMs) / (totalMs - oldMs));

  /// Новая вкладка подрастает с 96% до полного размера.
  static double newScale(double ms) =>
      0.96 + 0.04 * Curves.easeOutCubic.transform(newOpacity(ms));

  @override
  State<TabFade> createState() => _TabFadeState();
}

class _TabFadeState extends State<TabFade> with SingleTickerProviderStateMixin {
  final GlobalKey _paint = GlobalKey();
  late final AnimationController _run;
  ui.Image? _old;

  @override
  void initState() {
    super.initState();
    _run = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: TabFade.totalMs.round()),
      value: 1,
    )..addStatusListener(_onStatus);
  }

  @override
  void didUpdateWidget(TabFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index) return;
    _dropOld();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _run.value = 1;
      return;
    }
    // Слой ещё прошлого кадра: на нём прежняя вкладка.
    final boundary = _paint.currentContext?.findRenderObject();
    if (boundary is RenderRepaintBoundary && boundary.hasSize) {
      _old = unfoldSnapshot(
        boundary,
        Offset.zero & boundary.size,
        MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
      );
    }
    _run.forward(from: 0);
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _dropOld();
  }

  void _dropOld() {
    _old?.dispose();
    _old = null;
  }

  @override
  void dispose() {
    _dropOld();
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _run,
      builder: (context, page) {
        final ms = _run.value * TabFade.totalMs;
        final resting = _run.isCompleted;
        final old = _old;
        final fading = resting ? 0.0 : TabFade.oldOpacity(ms);
        return Stack(
          fit: StackFit.expand,
          children: [
            // Место под снимок занято всегда: появлялся бы он в списке только
            // на время перехода — Flutter пересобрал бы саму вкладку.
            if (old != null && fading > 0)
              IgnorePointer(
                child: Opacity(
                  key: const ValueKey<String>('tab-fade-old'),
                  opacity: fading,
                  child: RawImage(image: old, fit: BoxFit.fill),
                ),
              )
            else
              const SizedBox.shrink(),
            Opacity(
              opacity: resting ? 1 : TabFade.newOpacity(ms),
              child: Transform.scale(
                scale: resting ? 1 : TabFade.newScale(ms),
                alignment: const Alignment(0, -0.2),
                child: page,
              ),
            ),
          ],
        );
      },
      child: RepaintBoundary(key: _paint, child: widget.child),
    );
  }
}
