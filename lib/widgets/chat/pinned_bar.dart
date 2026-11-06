import 'package:flutter/material.dart';

import '../../dict_strings.dart' show trKey;
import '../../theme/profile_theme.dart';

/// Полоска закреплённого под шапкой чата (06.11.2026, как в Telegram).
/// Касание ведёт к сообщению, и полоска переходит к предыдущему
/// закреплённому; кнопка справа открывает экран со всеми. Шкала слева
/// показывает, какое по счёту видно сейчас.
class PinnedBar extends StatelessWidget {
  const PinnedBar({
    super.key,
    required this.index,
    required this.count,
    required this.preview,
    required this.onTap,
    required this.onOpenAll,
  });

  /// Номер показанного закреплённого, с нуля, от старого к новому.
  final int index;
  final int count;
  final String preview;
  final VoidCallback onTap;
  final VoidCallback onOpenAll;

  /// Делений на шкале не больше четырёх: дальше они не различаются глазом.
  static const int _maxSegments = 4;

  static const Duration _motion = Duration(milliseconds: 240);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final motion = MediaQuery.of(context).disableAnimations ? Duration.zero : _motion;
    final segments = count.clamp(1, _maxSegments);
    final active = count <= _maxSegments ? index : (index * (segments - 1) / (count - 1)).round();
    final title = count > 1
        ? trKey('cpBarTitle').replaceAll('{0}', '${index + 1}').replaceAll('{1}', '$count')
        : trKey('cpBarSingle');
    return Material(
      color: cs.surfaceContainer,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.surfaceContainerHighest))),
          padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
          child: Row(
            children: [
              SizedBox(
                width: 3,
                height: 38,
                child: Column(
                  children: [
                    for (var s = 0; s < segments; s++) ...[
                      if (s > 0) const SizedBox(height: 2),
                      Expanded(
                        // Деление перетекает к новому месту вместе с текстом.
                        child: AnimatedContainer(
                          duration: motion,
                          curve: Curves.easeOutCubic,
                          decoration: BoxDecoration(
                            color: s == active ? cs.primary : cs.primary.withValues(alpha: 0.28),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                // Смена закреплённого: новое въезжает снизу, прежнее гаснет,
                // как в Telegram. Ключ — номер, чтобы правка текста того же
                // сообщения не дёргала полоску.
                child: AnimatedSwitcher(
                  duration: motion,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [...previous, ?current],
                  ),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween(begin: const Offset(0, 0.35), end: Offset.zero).animate(anim),
                      child: child,
                    ),
                  ),
                  child: Column(
                  key: ValueKey('pin_$index'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: ProfileTheme.bodyFont,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                      ),
                    ),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: ProfileTheme.bodyFont, fontSize: 14.5, color: cs.onSurface),
                    ),
                  ],
                ),
                ),
              ),
              IconButton(
                onPressed: onOpenAll,
                tooltip: trKey('cpAll'),
                icon: Icon(Icons.push_pin_outlined, color: cs.onSurfaceVariant, size: 22),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
