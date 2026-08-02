import 'package:flutter/material.dart';

import '../../models/cycle_tip.dart';
import '../../services/locale_service.dart';

/// Лента советов под блоком цикла: как себе помочь в дни месячных.
///
/// Горизонтальная, потому что вертикальный список из семи карточек растянул бы
/// и без того длинный календарь ещё на экран. Карточки одной ширины, чтобы
/// край следующей выглядывал и было понятно, что лента листается.
class CycleTipsStrip extends StatelessWidget {
  const CycleTipsStrip({
    super.key,
    required this.scheme,
    required this.accent,
  });

  final ColorScheme scheme;

  /// Цвет отметки месячных — тот же, которым календарь красит эти дни.
  final Color accent;

  static const double _cardWidth = 196;

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final tips = CycleTip.all(s);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            s.cycleTipsTitle,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.06,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            physics: const BouncingScrollPhysics(),
            itemCount: tips.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) => _TipCard(
              tip: tips[i],
              scheme: scheme,
              accent: accent,
              width: _cardWidth,
            ),
          ),
        ),
      ],
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard({
    required this.tip,
    required this.scheme,
    required this.accent,
    required this.width,
  });

  final CycleTip tip;
  final ColorScheme scheme;
  final Color accent;
  final double width;

  @override
  Widget build(BuildContext context) {
    // Подложка значка — тот же красный, что у отметки месячных, но разбавленный
    // поверхностью: сплошной цвет семь раз подряд кричал бы на весь календарь.
    final iconBg = Color.alphaBlend(accent.withValues(alpha: 0.14), scheme.surface);

    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(tip.icon, size: 18, color: accent),
          ),
          const SizedBox(height: 9),
          Text(
            tip.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 3),
          Expanded(
            child: Text(
              tip.body,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
