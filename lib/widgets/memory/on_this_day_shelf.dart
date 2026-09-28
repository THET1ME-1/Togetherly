import 'package:flutter/material.dart';

import '../../dict_strings.dart' show trKey;
import '../../models/memory.dart';
import '../../models/on_this_day.dart';
import '../storage_image.dart';

/// Подпись плитки: «Месяц назад», «Год назад», «3 года назад».
String onThisDayLabel(OnThisDayShelf s) {
  if (s.monthsAgo == 1) return trKey('otdMonthAgo');
  if (s.yearsAgo == 1) return trKey('otdYearAgo');
  final key = switch (yearsAgoForm(s.yearsAgo)) {
    'one' => 'otdYearsOne',
    'few' => 'otdYearsFew',
    _ => 'otdYearsMany',
  };
  return trKey(key).replaceAll('{n}', '${s.yearsAgo}');
}

/// Ряд плиток «В этот день» над лентой: одна плитка на период, листается
/// вбок. Касание отдаёт период наружу — лента сама решает, открыть запись
/// или список того дня.
class OnThisDayShelfRow extends StatelessWidget {
  const OnThisDayShelfRow({
    super.key,
    required this.items,
    required this.onOpen,
  });

  final List<OnThisDayShelf> items;
  final void Function(OnThisDayShelf) onOpen;

  static const double tileWidth = 118;
  static const double coverHeight = 150;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    // Подпись растёт вместе с системным шрифтом, высота ряда — за ней.
    final height = coverHeight + 6 + scaler.scale(12) * 1.3 + 6;
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) =>
            _Tile(item: items[i], onTap: () => onOpen(items[i])),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.item, required this.onTap});

  final OnThisDayShelf item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cover = item.cover;
    final count = item.memories.length;
    final fallback = ColoredBox(
      color: cs.secondaryContainer,
      child: Center(
        child: Icon(
          memoryTypeIcon(item.memories.first.type),
          size: 34,
          color: cs.onSecondaryContainer,
        ),
      ),
    );
    return SizedBox(
      width: OnThisDayShelfRow.tileWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onTap,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                width: OnThisDayShelfRow.tileWidth,
                height: OnThisDayShelfRow.coverHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (cover.isEmpty)
                      fallback
                    else
                      StorageImage(
                        imageUrl: cover,
                        fit: BoxFit.cover,
                        memCacheWidth: (OnThisDayShelfRow.tileWidth * dpr)
                            .round(),
                        placeholder: (_, __) =>
                            ColoredBox(color: cs.surfaceContainerHighest),
                        errorWidget: (_, __, ___) => fallback,
                      ),
                    Positioned(
                      left: 8,
                      top: 8,
                      right: 8,
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: cs.surface.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          // Плашка узкая: длинная подпись («Vor einem Monat»,
                          // крупный шрифт) ужимается, а не режется многоточием.
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              onThisDayLabel(item),
                              maxLines: 1,
                              softWrap: false,
                              style: TextStyle(
                                fontFamily: 'Onest',
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (count > 1)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              fontFamily: 'Onest',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.caption.isEmpty ? onThisDayLabel(item) : item.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Onest',
              fontSize: 12,
              height: 1.25,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
