import 'package:flutter/physics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/motion.dart';
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
    this.duration = Motion.entrance,
    this.beginOffset = 16,
  });

  @override
  State<AnimatedSlideIn> createState() => _AnimatedSlideInState();
}

class _AnimatedSlideInState extends State<AnimatedSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _started = false;

  /// Пружина входа берётся из общего набора: этими же числами теперь движется
  /// всё, что встаёт на место, — см. [Motion.spatial].
  static final SpringDescription _spring = Motion.spatial;

  @override
  void initState() {
    super.initState();
    // Верхняя граница выше единицы — иначе контроллер срезает перелёт, и
    // пружина превращается в обычный подъём.
    _ctrl = AnimationController(
      vsync: this,
      duration: widget.duration,
      upperBound: Motion.spatialOvershoot,
    );
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
            opacity: t < 0.55 ? (t / 0.55).clamp(0.0, 1.0) : 1.0,
            child: Transform.translate(
              // Выше единицы блок уходит за своё место — это и есть перелёт,
              // после которого пружина возвращает его назад.
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

/// Блок, который встаёт на место, когда экран доезжает до него.
///
/// [AnimatedSlideIn] запускается сразу, поэтому в длинном списке половина
/// движения происходит за нижней кромкой экрана: человек долистывает до
/// ячейки, а она уже стоит. Здесь пружина та же (см. [Motion.spatial]), но
/// старт назначает первая встреча с областью видимости.
///
/// Каскад даётся только тому, что было на экране с самого начала: при заходе
/// на настройки ячейки встают по очереди, а долистанная снизу появляется без
/// ожидания — иначе прокрутка выглядела бы залипающей. Границу держит
/// [_staggerWindow]: видимость, случившаяся позже, считается прокруткой.
class AppearOnScroll extends StatefulWidget {
  const AppearOnScroll({
    super.key,
    required this.child,
    this.index = 0,
    this.step = const Duration(milliseconds: 40),
    this.beginOffset = 24,
    this.duration = Motion.entrance,
  });

  final Widget child;

  /// Место в группе — по нему считается задержка каскада.
  final int index;

  /// Задержка между соседями.
  final Duration step;

  /// Путь снизу вверх, в логических точках.
  final double beginOffset;
  final Duration duration;

  @override
  State<AppearOnScroll> createState() => _AppearOnScrollState();
}

class _AppearOnScrollState extends State<AppearOnScroll>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _started = false;
  ScrollPosition? _position;

  /// Появление маршрута, внутри которого живёт блок.
  ///
  /// Нижний лист въезжает снизу, и на первом кадре его содержимое физически
  /// ниже экрана: проверка «доехал ли» отвечает «нет», а второго повода
  /// проверить не наступает — короткий список никто не прокручивает. Так
  /// раздел «Уведомления» показывал заголовок, пустоту и кнопку внизу
  /// (жалоба со скриншотом 13 августа 2026). Пока лист едет, эта анимация
  /// тикает каждый кадр, и блок замечает, что попал на экран.
  Animation<double>? _routeAnim;

  /// Сколько ждём после первого кадра, прежде чем считать появление
  /// прокруткой, а не заходом на экран.
  static const Duration _staggerWindow = Duration(milliseconds: 400);

  /// Насколько «ниже нуля» стартует соседняя ячейка. Пока значение
  /// отрицательное, блок стоит на месте старта — это и есть задержка каскада,
  /// только без единого таймера: `Future.delayed` пережил бы конец
  /// виджет-теста и уронил бы чужие прогоны на «pending timers».
  static const double _staggerStep = 0.14;

  /// Дальше пятой ячейки каскад не растёт: иначе низ списка ждал бы секунду.
  static const int _staggerCap = 5;

  late final DateTime _born;

  @override
  void initState() {
    super.initState();
    _born = DateTime.now();
    _ctrl = AnimationController(
      vsync: this,
      duration: widget.duration,
      // Ниже нуля — пауза каскада, выше единицы — перелёт пружины. Обычный
      // диапазон 0…1 срезал бы и то, и другое.
      lowerBound: -_staggerStep * _staggerCap,
      upperBound: Motion.spatialOvershoot,
      value: 0,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ждём кромку экрана своими силами: `VisibilityDetector` держит на каждый
    // блок собственный таймер, а он переживает конец виджет-теста и роняет
    // чужие прогоны на «pending timers». Здесь ни одного таймера нет —
    // положение считается по прокрутке и по первому кадру.
    _position?.removeListener(_check);
    _position = Scrollable.maybeOf(context)?.position;
    _position?.addListener(_check);
    _routeAnim?.removeListener(_check);
    _routeAnim = ModalRoute.of(context)?.animation;
    _routeAnim?.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _position?.removeListener(_check);
    _routeAnim?.removeListener(_check);
    _ctrl.dispose();
    super.dispose();
  }

  /// Доехал ли экран до блока.
  void _check() {
    if (_started || !mounted) return;
    // Ни прокрутки, ни анимации маршрута — ждать нечего и некого: блок стоит
    // там, где стоит. Иначе он остался бы прозрачным навсегда, а нажатия при
    // этом проходят: `Opacity(0)` их не блокирует. Так и выглядела жалоба
    // «на всех попапах не отображается текст, хотя он есть и кликабельный».
    if (_position == null && _routeAnim == null) {
      _started = true;
      _run(0);
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;
    final screen = MediaQuery.sizeOf(context).height;
    // Блок считается дошедшим, когда его верхняя кромка вошла в экран. Нижнюю
    // границу тоже проверяем: то, что уже уехало вверх, показывать поздно.
    // Нулевая высота экрана бывает только в странной среде — там показываем
    // сразу, лучше без анимации, чем невидимая ячейка навсегда.
    if (screen > 0 && (top >= screen || bottom <= 0)) return;

    _started = true;
    _position?.removeListener(_check);
    _routeAnim?.removeListener(_check);
    // Каскад достаётся только тому, что было на экране с самого начала:
    // долистанная снизу ячейка появляется без ожидания, иначе прокрутка
    // выглядела бы залипающей.
    final scrolled = DateTime.now().difference(_born) > _staggerWindow;
    final steps = scrolled ? 0 : widget.index.clamp(0, _staggerCap);
    _run(-_staggerStep * steps);
  }

  void _run(double from) {
    if (!mounted) return;
    // Системный запрет анимаций уважаем: блок просто оказывается на месте.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _ctrl.value = 1;
      return;
    }
    _ctrl.animateWith(SpringSimulation(Motion.spatial, from, 1, 0));
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          // Отрицательные значения — пауза каскада: блок ещё стоит на месте
          // старта и невидим. Выше единицы — перелёт, его не срезаем.
          final t = _ctrl.value < 0 ? 0.0 : _ctrl.value;
          return Opacity(
            // Прозрачность догоняет раньше движения: на перелёте блок уже
            // непрозрачен, иначе он мигал бы у самой точки остановки.
            opacity: t < 0.55 ? (t / 0.55).clamp(0.0, 1.0) : 1.0,
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
    this.duration = Motion.tap,
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
    this.duration = Motion.tap,
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
      duration: Motion.medium4,
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
          duration: Motion.medium1,
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
                    duration: Motion.medium1,
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
                    duration: Motion.medium1,
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
    this.duration = Motion.medium2,
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
    this.duration = Motion.long4,
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
      duration: Motion.long4,
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
