import 'package:flutter/material.dart';

import '../../l10n/dates_text.dart';
import '../../models/pair_date.dart';
import '../../models/symbol_catalog.dart';
import '../../services/locale_service.dart';
import '../../theme/fonts.dart';

/// Карточка «Ближайшая дата» над календарём настроений (вариант «В» макета
/// https://claude.ai/artifact/A4pbED46avBz9QhigtEX6F): крупное число дней,
/// название и подпись. Касание открывает дату.
class NextDateCard extends StatelessWidget {
  const NextDateCard({
    super.key,
    required this.occurrence,
    required this.line,
    required this.scheme,
    required this.now,
    required this.onTap,
  });

  final DateOccurrence occurrence;

  /// «4 декабря, пятница · 19:00 · добавила Лиза».
  final String line;
  final ColorScheme scheme;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = scheme;
    final days = daysBetween(now, occurrence.day);
    final fg = cs.onPrimaryContainer;
    return Material(
      key: const ValueKey('next-date-card'),
      color: cs.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(dt('dt.next'), style: AppFonts.onest(size: 13, weight: 700, color: fg)),
                  ),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: SymbolIcon(occurrence.date.symbol, size: 24, color: cs.primaryContainer),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              if (days >= 2)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '$days',
                      style: AppFonts.unbounded(size: 72, weight: 800, height: 1.08, letterSpacing: -3, color: fg),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        dtCount('dt.daysWord', days),
                        style: AppFonts.unbounded(size: 22, weight: 700, color: fg),
                      ),
                    ),
                  ],
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 2),
                  child: Text(
                    untilText(days),
                    style: AppFonts.unbounded(size: 44, weight: 800, letterSpacing: -1.5, color: fg),
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                dateTitle(occurrence.date, occurrence.day),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppFonts.onest(size: 19, weight: 700, color: cs.onSurface),
              ),
              if (line.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(line, style: AppFonts.onest(size: 13.5, color: fg)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Следующие даты чипами под карточкой и «Все даты» в конце ряда.
class UpcomingDatesRow extends StatelessWidget {
  const UpcomingDatesRow({
    super.key,
    required this.occurrences,
    required this.scheme,
    required this.onOpen,
    required this.onAll,
  });

  final List<DateOccurrence> occurrences;
  final ColorScheme scheme;
  final ValueChanged<DateOccurrence> onOpen;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    final cs = scheme;
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          for (final o in occurrences) ...[
            _Chip(
              color: cs.surfaceContainerHigh,
              onTap: () => onOpen(o),
              child: Row(
                children: [
                  SymbolIcon(o.date.symbol, size: 20, color: cs.tertiary),
                  const SizedBox(width: 10),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        LocaleService.current.dayLogDate(o.day),
                        style: AppFonts.onest(size: 12, weight: 800, color: cs.primary),
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 180),
                        child: Text(
                          dateTitle(o.date, o.day),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppFonts.onest(size: 13.5, weight: 600, color: cs.onSurface),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
          _Chip(
            key: const ValueKey('dates-all-chip'),
            color: cs.surfaceContainerHighest,
            onTap: onAll,
            child: Row(
              children: [
                Text(dt('dt.all'), style: AppFonts.onest(size: 13.5, weight: 700, color: cs.onSurfaceVariant)),
                const SizedBox(width: 2),
                Icon(Icons.chevron_right_rounded, size: 20, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.color, required this.onTap, required this.child});

  final Color color;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: child),
      ),
    );
  }
}

/// Пока дат нет: строка-приглашение вместо крупной карточки.
class EmptyDatesCard extends StatelessWidget {
  const EmptyDatesCard({super.key, required this.scheme, required this.onAdd});

  final ColorScheme scheme;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final cs = scheme;
    return Material(
      key: const ValueKey('dates-empty-card'),
      color: cs.tertiaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onAdd,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.onTertiaryContainer.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.event_rounded, size: 24, color: cs.onTertiaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dt('dt.legend'), style: AppFonts.onest(size: 16, weight: 700, color: cs.onTertiaryContainer)),
                    const SizedBox(height: 2),
                    Text(
                      dt('dt.eventEmpty'),
                      style: AppFonts.onest(size: 13, color: cs.onTertiaryContainer.withValues(alpha: 0.8)),
                    ),
                  ],
                ),
              ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: cs.onTertiaryContainer, shape: BoxShape.circle),
                child: Icon(Icons.add_rounded, size: 22, color: cs.tertiaryContainer),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Флажок даты в углу клетки календаря.
class DateFlag extends StatelessWidget {
  const DateFlag({super.key, required this.symbol, required this.scheme, required this.ring});

  final String symbol;
  final ColorScheme scheme;

  /// Цвет обводки — фон карточки календаря, чтобы флажок не сливался с клеткой.
  final Color ring;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 17,
      height: 17,
      decoration: BoxDecoration(
        color: scheme.tertiary,
        shape: BoxShape.circle,
        border: Border.all(color: ring, width: 2),
      ),
      alignment: Alignment.center,
      child: SymbolIcon(symbol, size: 10, color: scheme.onTertiary),
    );
  }
}
