import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/mood_pack.dart';
import '../services/catalog_service.dart';
import '../services/mood_pack_service.dart';
import '../theme/theme_scope.dart';
import 'mood_image.dart';

/// Выбор пака настроений в пикере: таблетки без обводки.
///
/// Пока паков два-три, они делят строку поровну — так строка читается как один
/// переключатель. Появится четвёртый — уезжают в горизонтальную прокрутку.
/// Ростом таблетки ниже вкладок «Настроение / Самочувствие»: выбор вкладки тут
/// главный, а пак — уточнение.
class MoodPackSelector extends StatelessWidget {
  final Color primary;

  /// Вызывается после смены пака (родитель обновляет сетку настроений).
  final ValueChanged<MoodPack>? onChanged;

  const MoodPackSelector({
    super.key,
    required this.primary,
    this.onChanged,
  });

  /// До скольких паков строка делится поровну.
  static const int _stretchUpTo = 3;
  static const double _height = 38;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(
        [MoodPackService.instance, CatalogService.instance],
      ),
      builder: (context, _) {
        final selectedId = MoodPackService.instance.selectedPackId;
        final packs = CatalogService.instance.allPacks;
        if (packs.isEmpty) return const SizedBox.shrink();

        void select(MoodPack pack) {
          if (pack.id == selectedId) return;
          HapticFeedback.selectionClick();
          MoodPackService.instance.setSelectedPack(pack.id);
          onChanged?.call(pack);
        }

        if (packs.length <= _stretchUpTo) {
          return SizedBox(
            height: _height,
            child: Row(
              children: [
                for (var i = 0; i < packs.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _PackChip(
                      pack: packs[i],
                      selected: packs[i].id == selectedId,
                      primary: primary,
                      stretched: true,
                      onTap: () => select(packs[i]),
                    ),
                  ),
                ],
              ],
            ),
          );
        }

        return SizedBox(
          height: _height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: packs.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) => _PackChip(
              pack: packs[i],
              selected: packs[i].id == selectedId,
              primary: primary,
              stretched: false,
              onTap: () => select(packs[i]),
            ),
          ),
        );
      },
    );
  }
}

class _PackChip extends StatelessWidget {
  final MoodPack pack;
  final bool selected;
  final Color primary;

  /// Таблетка занимает свою долю строки (текст по центру) или обжимается
  /// по содержимому в прокручиваемом ряду.
  final bool stretched;
  final VoidCallback onTap;

  const _PackChip({
    required this.pack,
    required this.selected,
    required this.primary,
    required this.stretched,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final cs = Theme.of(context).colorScheme;
    final gradient = pack.tileGradient;
    final fg = selected ? cs.onPrimaryContainer : t.textSecondary;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        height: MoodPackSelector._height,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : t.surfaceMuted,
          borderRadius: BorderRadius.circular(MoodPackSelector._height / 2),
        ),
        child: Row(
          mainAxisSize: stretched ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Превью пака — первое настроение набора.
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: gradient != null
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: gradient,
                      )
                    : null,
                color: gradient == null ? Colors.white : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: pack.previewImage.isNotEmpty
                  ? MoodImage(pack.previewImage, fit: BoxFit.cover)
                  : null,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                pack.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 6),
              Icon(Icons.check_rounded, size: 15, color: fg),
            ],
          ],
        ),
      ),
    );
  }
}
