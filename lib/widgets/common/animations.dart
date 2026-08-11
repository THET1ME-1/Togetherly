import 'package:flutter/physics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/theme_scope.dart';

/// Появление блока при входе: пружина на 16 логических точек.
///
/// Три вещи, из-за которых прежний вариант выглядел плохо и подтормаживал:
///
/// 1. `SlideTransition` считает смещение В ДОЛЯХ размера ребёнка. Стояло
///    `Offset(0, 30)` — тридцать собственных высот, поэтому карточки стартовали
///    далеко за экраном и «влетали» снизу. Теперь путь задаётся в точках и
///    отрабатывается через [Transform.translate].
/// 2. Анимация запускалась из `initState` по `Future.delayed`, то есть прямо
///    посреди тяжёлого первого кадра: поднимался PocketBase, грелись картинки —
///    и первые кадры анимации терялись, отсюда рывок. Теперь старт назначается
///    после первого настоящего кадра.
/// 3. Каждая карточка перерисовывала соседей: без [RepaintBoundary] слой
///    анимации тянул за собой весь экран.
///
/// Движение — пружина M3 Expressive: блок чуть проскакивает и возвращается.
class AnimatedSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;

  /// Насколько блок сдвинут в начале, в логических точках. Плюс — снизу вверх.
  final double beginOffset;

  const AnimatedSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 520),
    this.beginOffset = 16,
  });

  @override
  State<AnimatedSlideIn> createState() => _AnimatedSlideInState();
}

class _AnimatedSlideInState extends State<AnimatedSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _started = false;

  /// Пружина: слегка недодемпфирована, поэтому даёт перелёт на пару точек и
  /// мягкий возврат. Жёстче — и получится щелчок, мягче — кисель.
  static final SpringDescription _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 260,
    ratio: 0.72,
  );

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    WidgetsBinding.instance.addPostFrameCallback((_) => _schedule());
  }

  void _schedule() {
    if (!mounted || _started) return;
    _started = true;
    if (widget.delay == Duration.zero) {
      _run();
    } else {
      Future.delayed(widget.delay, _run);
    }
  }

  void _run() {
    if (!mounted) return;
    // Системный запрет анимаций уважаем: блок просто оказывается на месте.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _ctrl.value = 1;
      return;
    }
    _ctrl.animateWith(SpringSimulation(_spring, 0, 1, 0));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          final t = _ctrl.value;
          return Opacity(
            // Прозрачность догоняет раньше движения: блок не должен мигать на
            // перелёте, поэтому к середине пути он уже непрозрачный.
            opacity: t.clamp(0.0, 1.0) < 0.55 ? (t / 0.55).clamp(0.0, 1.0) : 1.0,
            child: Transform.translate(
              offset: Offset(0, widget.beginOffset * (1 - t)),
              child: child,
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// Tap Scale wrapper for press animations
class TapScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  /// Долгое нажатие. Нужно кнопке фото на главной: тап снимает кадр,
  /// удержание пишет ролик.
  final VoidCallback? onLongPress;
  final double scale;
  final Duration duration;

  const TapScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.95,
    this.duration = const Duration(milliseconds: 150),
  });

  @override
  State<TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<TapScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _scale = Tween<double>(
      begin: 1.0,
      end: widget.scale,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _ctrl.reverse(),
      behavior: HitTestBehavior.translucent,
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}

/// Simple Tap Scale sequence (down then up) for quick clicks
class QuickTapScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  /// Долгое нажатие. Нужно кнопке фото на главной: тап снимает кадр,
  /// удержание пишет ролик.
  final VoidCallback? onLongPress;
  final double scale;
  final Duration duration;

  const QuickTapScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.95,
    this.duration = const Duration(milliseconds: 150),
  });

  @override
  State<QuickTapScale> createState() => _QuickTapScaleState();
}

class _QuickTapScaleState extends State<QuickTapScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: widget.scale,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: widget.scale,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 50,
      ),
    ]).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    _ctrl.forward(from: 0);
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      onLongPress: widget.onLongPress,
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}

/// Animated navigation bar item
class NavBarItem extends StatefulWidget {
  final IconData? icon;
  final String? svgIcon;
  final int index;
  final String label;
  final bool isActive;
  final bool showBadge;
   final Color activeColor;
  final Color activeBg;
  final Color inactiveColor;
  final Color badgeColor;
  final VoidCallback onTap;

  const NavBarItem({
    super.key,
    this.icon,
    this.svgIcon,
    required this.index,
    required this.label,
    required this.isActive,
     required this.activeColor,
    required this.activeBg,
    required this.inactiveColor,
    required this.badgeColor,
    required this.onTap,
    this.showBadge = false,
  }) : assert(
         icon != null || svgIcon != null,
         'Either icon or svgIcon must be provided',
       );

  @override
  State<NavBarItem> createState() => _NavBarItemState();
}

class _NavBarItemState extends State<NavBarItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.22,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.22,
          end: 0.90,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.90,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 35,
      ),
    ]).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    _ctrl.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          // Пунктов пять, а панель узкая: на экране 360 dp прежние отступы
          // (18/12) не помещались.
          padding: EdgeInsets.symmetric(
            horizontal: widget.isActive ? 14 : 9,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: widget.isActive ? widget.activeBg : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    transitionBuilder: (child, anim) => ScaleTransition(
                      scale: CurvedAnimation(
                        parent: anim,
                        curve: Curves.easeOutBack,
                      ),
                      child: FadeTransition(opacity: anim, child: child),
                    ),
                    child: widget.svgIcon != null
                        ? _SvgIconBuilder(
                            svgString: widget.svgIcon!,
                            size: widget.isActive ? 28 : 24,
                             color: widget.isActive
                                ? widget.activeColor
                                : widget.inactiveColor,
                          )
                        : Icon(
                            widget.icon,
                            key: ValueKey('${widget.index}_${widget.isActive}'),
                            color: widget.isActive
                                ? widget.activeColor
                                : widget.inactiveColor,
                            size: widget.isActive ? 28 : 24,
                          ),
                  ),
                  const SizedBox(height: 3),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 260),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: widget.isActive
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: widget.isActive
                          ? widget.activeColor
                          : widget.inactiveColor,
                    ),
                    child: const SizedBox.shrink(),
                  ),
                ],
              ),
              if (widget.showBadge)
                Positioned(
                  top: -2,
                  right: -4,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: widget.badgeColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Helper widget to render SVG icon from string
class _SvgIconBuilder extends StatelessWidget {
  final String svgString;
  final double size;
  final Color color;

  const _SvgIconBuilder({
    required this.svgString,
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    // Replace currentColor with the actual color in hex format
    String colorHex = color.value.toRadixString(16).padLeft(8, '0');
    colorHex = '#${colorHex.substring(2)}'; // Remove alpha, keep RGB

    final modifiedSvg = svgString.replaceAll('currentColor', colorHex);

    return SizedBox(
      width: size,
      height: size,
      child: SvgPicture.string(
        modifiedSvg,
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );
  }
}

/// Enum for mood badge position
enum MoodBadgePosition { topLeft, bottomRight }

/// Enhanced bounce button with spring animation
class BounceButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final Duration duration;

  const BounceButton({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.9,
    this.duration = const Duration(milliseconds: 300),
  });

  @override
  State<BounceButton> createState() => _BounceButtonState();
}

class _BounceButtonState extends State<BounceButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: widget.scale,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: widget.scale,
          end: 1.05,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.05,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 30,
      ),
    ]).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    _ctrl.forward(from: 0);
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}

/// Rotating icon that spins on tap
class RotatingIcon extends StatefulWidget {
  final IconData icon;
  final double size;
  final Color? color;
  final VoidCallback? onTap;
  final Duration duration;

  const RotatingIcon({
    super.key,
    required this.icon,
    this.size = 24,
    this.color,
    this.onTap,
    this.duration = const Duration(milliseconds: 600),
  });

  @override
  State<RotatingIcon> createState() => _RotatingIconState();
}

class _RotatingIconState extends State<RotatingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _rotation;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _rotation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutBack));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    _ctrl.forward(from: 0);
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: RotationTransition(
        turns: _rotation,
        child: Icon(widget.icon, size: widget.size, color: widget.color),
      ),
    );
  }
}

/// Heart/Like animation with particles
class HeartAnimation extends StatefulWidget {
  final bool isLiked;
  final VoidCallback? onTap;
  final double size;

  const HeartAnimation({
    super.key,
    required this.isLiked,
    this.onTap,
    this.size = 24,
  });

  @override
  State<HeartAnimation> createState() => _HeartAnimationState();
}

class _HeartAnimationState extends State<HeartAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.4,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.4,
          end: 0.9,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.9,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 40,
      ),
    ]).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    _ctrl.forward(from: 0);
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return GestureDetector(
      onTap: _handleTap,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          return Transform.scale(
            scale: _scale.value,
            child: Icon(
              widget.isLiked ? Icons.favorite : Icons.favorite_border,
              size: widget.size,
              color: widget.isLiked ? Colors.red : t.textMuted,
            ),
          );
        },
      ),
    );
  }
}

/// Draw Mode Option tile used in bottom sheets
class DrawModeOption extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const DrawModeOption({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    // M3: тональный контейнер без рамок и полупрозрачных заливок, крупные
    // скругления, иконка в квадрате-контейнере.
    return Material(
      color: t.surfaceMuted,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: t.primaryLight,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: t.primary, size: 23),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 13, color: t.textSecondary),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 22, color: t.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
