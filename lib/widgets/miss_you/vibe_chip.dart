import 'package:flutter/material.dart';

import '../../theme/profile_theme.dart';

/// Плитка импульса на экране «Скучаю»: «Думаю о тебе», «Хочу обнять», своё
/// пожелание, «Своё желание…».
///
/// Нажатие отвечает у самой плитки (TOG-40, обращение 377): она вздрагивает,
/// над ней взлетают три её значка, а своё число сменяется сдвигом вверх.
/// Прежде сердечки взлетали у большой кнопки наверху экрана, у пальца не
/// было ничего, и человеку казалось, что кнопка не работает.
class VibeChip extends StatefulWidget {
  const VibeChip({
    super.key,
    required this.scheme,
    required this.icon,
    required this.label,
    required this.onTap,
    this.onRemove,
    this.accent = false,
    this.accentFill,
    this.accentInk,
    this.mine = 0,
    this.partner = 0,
  });

  final ColorScheme scheme;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  /// Залитая плитка «Своё желание…»: открывает лист, всплеска у неё нет.
  final bool accent;
  final Color? accentFill;
  final Color? accentInk;

  /// Сколько раз этот импульс отправляли: свои и партнёрские. Просьба тестера
  /// («было бы классно добавить счёт в остальные пункты») — до этого число
  /// стояло только у «Скучаю», хотя сервер считает каждый импульс.
  final int mine;
  final int partner;

  @override
  State<VibeChip> createState() => _VibeChipState();
}

class _VibeChipState extends State<VibeChip> with SingleTickerProviderStateMixin {
  late final AnimationController _bump = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  /// Плитка проседает и отскакивает, как большое сердце, только тише.
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.94).chain(CurveTween(curve: Curves.easeIn)), weight: 12),
    TweenSequenceItem(tween: Tween(begin: 0.94, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)), weight: 50),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 38),
  ]).animate(_bump);

  @override
  void dispose() {
    _bump.dispose();
    super.dispose();
  }

  void _tap() {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!reduce && !widget.accent) _bump.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = widget.scheme;
    final accent = widget.accent;
    final bg = accent ? (widget.accentFill ?? scheme.primary) : scheme.surfaceContainerHigh;
    final ink = accent ? (widget.accentInk ?? scheme.onPrimary) : scheme.onSurface;
    final iconColor = accent ? ink : scheme.primary;

    final chip = Material(
      color: bg,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _tap,
        onLongPress: widget.onRemove,
        child: Padding(
          padding: EdgeInsets.fromLTRB(13, 0, widget.onRemove == null ? 14 : 8, 0),
          child: SizedBox(
            height: 40,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 18, color: iconColor),
                const SizedBox(width: 7),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 190),
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: ProfileTheme.bodyFont,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: ink,
                      ),
                    ),
                  ),
                ),
                if (widget.mine > 0 || widget.partner > 0) ...[
                  const SizedBox(width: 8),
                  _VibeTally(
                    mine: widget.mine,
                    partner: widget.partner,
                    ink: ink,
                    muted: accent ? ink.withValues(alpha: 0.62) : scheme.onSurfaceVariant,
                  ),
                ],
                if (widget.onRemove != null) ...[
                  const SizedBox(width: 2),
                  IconButton(
                    onPressed: widget.onRemove,
                    icon: const Icon(Icons.close_rounded, size: 16),
                    color: scheme.onSurfaceVariant,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ScaleTransition(scale: _scale, child: chip),
        // Значки взлетают от значка плитки, туда, куда смотрел палец.
        Positioned(
          left: 13,
          top: 11,
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _bump,
              builder: (context, _) => _bump.status == AnimationStatus.forward
                  ? _Burst(key: const ValueKey('vibe-burst'), t: _bump.value, icon: widget.icon, color: iconColor)
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }
}

/// Три значка поднимаются над плиткой и гаснут. Сдвиги заданы, а не
/// случайны: всплеск одинаков от раза к разу и в снимках.
class _Burst extends StatelessWidget {
  const _Burst({super.key, required this.t, required this.icon, required this.color});

  final double t;
  final IconData icon;
  final Color color;

  static const _flights = [
    (dx: -8.0, rise: 46.0, size: 15.0, delay: 0.0),
    (dx: 12.0, rise: 60.0, size: 18.0, delay: 0.08),
    (dx: 30.0, rise: 50.0, size: 14.0, delay: 0.16),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final f in _flights)
            Builder(
              builder: (context) {
                final p = ((t - f.delay) / (1 - f.delay)).clamp(0.0, 1.0);
                final rise = Curves.easeOutCubic.transform(p);
                return Transform.translate(
                  offset: Offset(f.dx * rise, -f.rise * rise),
                  child: Opacity(
                    opacity: p <= 0 ? 0 : (1 - p).clamp(0.0, 1.0),
                    child: Icon(icon, size: f.size, color: color),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// Два числа у импульса: свои и партнёрские, тем же порядком, что в шапке
/// («мои / её»). Ноль не рисуется вовсе — пустая пилюля читалась бы поломкой.
/// Своё число сменяется сдвигом вверх: так видно, что нажатие засчитано.
class _VibeTally extends StatelessWidget {
  const _VibeTally({required this.mine, required this.partner, required this.ink, required this.muted});

  final int mine;
  final int partner;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    TextStyle style(Color color) => TextStyle(
      fontFamily: ProfileTheme.bodyFont,
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
      color: color,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.6), end: Offset.zero).animate(animation),
              child: child,
            ),
          ),
          child: Text('$mine', key: ValueKey(mine), style: style(ink)),
        ),
        Text(' · ', style: style(muted)),
        Text('$partner', style: style(muted)),
      ],
    );
  }
}
