import 'package:flutter/material.dart';

import '../../models/rank.dart';
import '../../theme/profile_theme.dart';
import 'rank_emblem.dart';

/// Звание под именем в шапке профиля: эмблема, название и часы. Стоит рядом
/// с чипом «N дней вместе» и выглядит так же, касание открывает лист званий.
class RankChip extends StatelessWidget {
  const RankChip({
    super.key,
    required this.cs,
    required this.seconds,
    required this.hours,
    this.onTap,
  });

  final ColorScheme cs;
  final int seconds;
  final List<num> hours;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final rank = rankFor(seconds, hours);
    return Semantics(
      button: onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 3, 11, 3),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RankEmblem(rank, side: 26),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  '${hourRankName(rank)} · ${hourRankHours(seconds)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: ProfileTheme.bodyFont,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                    color: cs.onSurfaceVariant,
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
