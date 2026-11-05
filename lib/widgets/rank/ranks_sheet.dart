import 'package:flutter/material.dart';

import '../../dict_strings.dart';
import '../../models/rank.dart';
import '../../theme/profile_theme.dart';
import '../app_sheet.dart';
import 'rank_emblem.dart';

/// Лист званий (макет «Звания за часы», 05.11.2026): сверху текущее звание,
/// часы и полоска до следующего, ниже лестница из 14 ступеней — пройденные в
/// цвете, будущие серыми. Лист открывается на текущем звании.
Future<void> showRanksSheet(
  BuildContext context, {
  required ColorScheme cs,
  required int seconds,
  required List<num> hours,
  bool mine = true,
}) {
  // Проектный лист: высокий не дорастает до строки состояния (TOG-39).
  return showModalSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: cs.surfaceContainerLow,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) =>
        RanksSheet(cs: cs, seconds: seconds, hours: hours, mine: mine),
  );
}

class RanksSheet extends StatefulWidget {
  const RanksSheet({
    super.key,
    required this.cs,
    required this.seconds,
    required this.hours,
    this.mine = true,
  });

  final ColorScheme cs;
  final int seconds;
  final List<num> hours;
  final bool mine;

  /// Высота строки лестницы: по ней лист прокручивается к текущему званию.
  static const double rowHeight = 76;

  @override
  State<RanksSheet> createState() => _RanksSheetState();
}

class _RanksSheetState extends State<RanksSheet> {
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    final rank = rankFor(widget.seconds, widget.hours);
    // Шапка с текущим званием видна, пока текущая ступень в первой трети
    // лестницы; дальше лист сразу едет к ней.
    _scroll = ScrollController(
      initialScrollOffset: rank < 5
          ? 0
          : 200 + (rank - 3) * RanksSheet.rowHeight,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    final p = progressOf(widget.seconds, widget.hours);
    final h = MediaQuery.sizeOf(context).height;
    return SizedBox(
      height: h * 0.82,
      child: ListView(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          _Now(cs: cs, progress: p, seconds: widget.seconds, mine: widget.mine),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              trKey('hrankHow'),
              style: TextStyle(
                fontFamily: ProfileTheme.bodyFont,
                fontSize: 13,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < widget.hours.length; i++)
            _Step(cs: cs, rank: i, current: p.rank, hours: widget.hours[i]),
        ],
      ),
    );
  }
}

class _Now extends StatelessWidget {
  const _Now({
    required this.cs,
    required this.progress,
    required this.seconds,
    required this.mine,
  });

  final ColorScheme cs;
  final RankProgress progress;
  final int seconds;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final next = progress.next;
    final left = next == null
        ? trKey('hrankTop')
        : trKey('hrankTo')
              .replaceAll('{0}', hourRankName(next))
              .replaceAll('{1}', hourRankHours(progress.leftSeconds));
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 14, 16, 14),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          RankEmblem(progress.rank, side: 104),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trKey(mine ? 'hrankYour' : 'hrankPartner'),
                  style: TextStyle(
                    fontFamily: ProfileTheme.bodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onPrimaryContainer.withValues(alpha: 0.8),
                  ),
                ),
                Text(
                  hourRankName(progress.rank),
                  style: TextStyle(
                    fontFamily: ProfileTheme.displayFont,
                    fontSize: 20,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hourRankHours(seconds),
                  style: TextStyle(
                    fontFamily: ProfileTheme.displayFont,
                    fontSize: 26,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  // Дорожка во всю ширину (заметна и на светлом
                  // контейнере), заливка — доля пути от неё.
                  child: Container(
                    height: 10,
                    width: double.infinity,
                    color: cs.onPrimaryContainer.withValues(alpha: 0.24),
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: progress.fraction,
                      heightFactor: 1,
                      child: ColoredBox(color: cs.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  left,
                  style: TextStyle(
                    fontFamily: ProfileTheme.bodyFont,
                    fontSize: 13,
                    color: cs.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.cs,
    required this.rank,
    required this.current,
    required this.hours,
  });

  final ColorScheme cs;
  final int rank;
  final int current;
  final num hours;

  @override
  Widget build(BuildContext context) {
    final got = rank <= current, now = rank == current;
    final line = got ? cs.primary : cs.outlineVariant;
    final when = hours == 0
        ? trKey('hrankFromStart')
        : trKey(
            'hrankH',
          ).replaceAll('{0}', hours % 1 == 0 ? '${hours.toInt()}' : '$hours');
    // Высота строки — не меньше rowHeight, при крупном шрифте растёт.
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: Container(
            constraints: const BoxConstraints(
              minHeight: RanksSheet.rowHeight - 8,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: now ? cs.surfaceContainerHigh : null,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                RankEmblem(rank, side: 58, locked: !got),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              hourRankName(rank),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: ProfileTheme.bodyFont,
                                fontSize: 16.5,
                                fontWeight: now
                                    ? FontWeight.w700
                                    : (got ? FontWeight.w600 : FontWeight.w500),
                                color: got ? cs.onSurface : cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          if (now) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: cs.primary,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                trKey('hrankNow'),
                                style: TextStyle(
                                  fontFamily: ProfileTheme.bodyFont,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onPrimary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        when,
                        style: TextStyle(
                          fontFamily: ProfileTheme.bodyFont,
                          fontSize: 13.5,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Отрезок лестницы от прошлой ступени: пройденные — цветом темы.
        if (rank > 0)
          Positioned(
            left: 36,
            top: 0,
            child: Container(
              width: 3,
              height: 8,
              decoration: BoxDecoration(
                color: line,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
      ],
    );
  }
}
