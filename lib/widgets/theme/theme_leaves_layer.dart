import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Один лист листопада: где по ширине падает, какого размера, сколько секунд
/// летит сверху донизу и насколько сдвинут по времени от соседей.
class FallingLeaf {
  final double x;
  final double size;
  final double seconds;
  final double delay;

  const FallingLeaf(this.x, this.size, this.seconds, this.delay);
}

/// Листья макета «Б. Листопад»: семь штук по ширине экрана, от 14 до 26
/// точек, каждый со своей скоростью (9–14 с на весь экран).
const kFallingLeaves = <FallingLeaf>[
  FallingLeaf(0.08, 22, 9, 0),
  FallingLeaf(0.31, 18, 11, 3),
  FallingLeaf(0.54, 26, 10, 6),
  FallingLeaf(0.77, 20, 12, 2),
  FallingLeaf(0.18, 16, 13, 8),
  FallingLeaf(0.64, 18, 9.5, 5),
  FallingLeaf(0.41, 14, 14, 10),
];

/// Где лист в момент [seconds] на экране [size]: верхний левый угол и угол
/// поворота. Как в макете: лист выходит из-за верхнего края, по пути чуть
/// покачивается вбок и за полёт поворачивается почти на целый оборот.
({Offset at, double turn}) leafPosition(FallingLeaf l, Size size, double seconds) {
  final t = ((seconds + l.delay) % l.seconds) / l.seconds;
  final y = -l.size * 2 + (size.height + l.size * 4) * t;
  final x = l.x * size.width + 18 * math.sin(math.pi * t) - 6 * t;
  return (at: Offset(x, y), turn: t * 320 * math.pi / 180);
}

/// Листопад за интерфейсом, под всеми вкладками (тема «Уютная осень»).
///
/// У темы без листопада слой пустой, но место в дереве за ним остаётся, как у
/// узора: смена темы не пересоздаёт соседей. Касания идут сквозь листья.
/// Выключенная в телефоне анимация останавливает листья на месте.
class ThemeLeavesLayer extends StatelessWidget {
  final AppTheme theme;

  const ThemeLeavesLayer({super.key, required this.theme});

  @override
  Widget build(BuildContext context) {
    final leaves = theme.bgLeaves;
    if (leaves == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: _Fall(leaves: leaves, still: MediaQuery.disableAnimationsOf(context)),
        ),
      ),
    );
  }
}

class _Fall extends StatefulWidget {
  final ThemeLeaves leaves;
  final bool still;

  const _Fall({required this.leaves, required this.still});

  @override
  State<_Fall> createState() => _FallState();
}

class _FallState extends State<_Fall> with SingleTickerProviderStateMixin {
  // Часы листопада: длиннее любого полёта, дальше идут по кругу.
  late final AnimationController _clock =
      AnimationController(vsync: this, duration: const Duration(seconds: 600));

  @override
  void initState() {
    super.initState();
    if (!widget.still) _clock.repeat();
  }

  @override
  void didUpdateWidget(_Fall old) {
    super.didUpdateWidget(old);
    if (widget.still && _clock.isAnimating) _clock.stop();
    if (!widget.still && !_clock.isAnimating) _clock.repeat();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final assets = widget.leaves.assets;
    return LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        return Opacity(
          opacity: widget.leaves.opacity,
          child: AnimatedBuilder(
            animation: _clock,
            builder: (context, _) {
              // Без анимации листья застывают там, где были бы на 4-й секунде.
              final seconds = widget.still ? 4.0 : _clock.value * 600;
              return Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  for (var i = 0; i < kFallingLeaves.length; i++)
                    _leaf(kFallingLeaves[i], assets[i % assets.length], size, seconds),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _leaf(FallingLeaf l, String asset, Size size, double seconds) {
    final p = leafPosition(l, size, seconds);
    return Positioned(
      left: p.at.dx,
      top: p.at.dy,
      width: l.size,
      height: l.size,
      child: Transform.rotate(
        angle: p.turn,
        child: Image.asset(asset, fit: BoxFit.contain, filterQuality: FilterQuality.medium, gaplessPlayback: true),
      ),
    );
  }
}
