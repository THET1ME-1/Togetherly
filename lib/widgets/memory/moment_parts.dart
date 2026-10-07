import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/fonts.dart';
import '../../theme/profile_theme.dart';

/// Детали обложки открытого воспоминания: макет «Открытые пины», вариант A
/// «Обложка во всю ширину» (07.10.2026). Обложка стоит там же, где кадр у
/// фото, ниже название крупно, факты пилюлями и связанная группа кнопок.
///
/// Прежние экраны музыки, книги, кино и места были карточкой в карточке с
/// рамкой и градиентом, рейтинг Кинопоиска красился оранжевым. Здесь всё в
/// цветах темы и без рамок.

/// Название крупно, под ним автор, исполнитель или оригинальное название.
class MomentHead extends StatelessWidget {
  const MomentHead({super.key, required this.scheme, required this.title, this.sub});

  final ColorScheme scheme;
  final String title;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final s = sub?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: ProfileTheme.displayFont,
              fontSize: 23,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              height: 1.2,
              color: scheme.onSurface,
            ),
          ),
          if (s.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                s,
                style: AppFonts.onest(size: 15, weight: 500, color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

/// Факт пилюлей: год, издатель, жанр. [strong] — заливка темы, ею выделен
/// рейтинг Кинопоиска вместо прежней оранжевой плашки.
class MomentPill extends StatelessWidget {
  const MomentPill({
    super.key,
    required this.scheme,
    required this.fill,
    required this.label,
    this.icon,
    this.strong = false,
  });

  final ColorScheme scheme;
  final Color fill;
  final String label;
  final IconData? icon;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final bg = strong ? fill : scheme.secondaryContainer;
    final fg = strong
        ? AppThemes.onColor(fill, mode: scheme.brightness)
        : scheme.onSecondaryContainer;
    return Container(
      constraints: const BoxConstraints(minHeight: 32),
      padding: EdgeInsets.fromLTRB(icon == null ? 12 : 9, 6, 12, 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.onest(size: 13, weight: 600, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ряд пилюль: переносится, а не уезжает вбок.
class MomentPills extends StatelessWidget {
  const MomentPills({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Wrap(spacing: 6, runSpacing: 6, children: children),
    );
  }
}

/// Оценка автора записи пятью звёздами цвета темы. Подписано именем автора,
/// а не «Ваша оценка»: открытую запись смотрит и партнёр.
class MomentStars extends StatelessWidget {
  const MomentStars({
    super.key,
    required this.scheme,
    required this.fill,
    required this.rating,
    required this.who,
  });

  final ColorScheme scheme;
  final Color fill;
  final int rating;
  final String who;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          Flexible(
            child: Text(
              who,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.onest(size: 13.5, weight: 600, color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 8),
          for (var i = 1; i <= 5; i++)
            Icon(
              Icons.star_rounded,
              size: 20,
              color: i <= rating ? fill : fill.withValues(alpha: 0.28),
            ),
        ],
      ),
    );
  }
}

/// Действие кнопки: значок, подпись и что делать.
class MomentAction {
  const MomentAction(this.icon, this.label, this.onTap);

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// Связанная группа кнопок M3 Expressive: главная залита цветом темы, вторая
/// — тональный значок с подсказкой. Внутренние углы малые, внешние круглые.
class MomentButtons extends StatelessWidget {
  const MomentButtons({
    super.key,
    required this.scheme,
    required this.fill,
    required this.primary,
    this.secondary,
  });

  final ColorScheme scheme;
  final Color fill;
  final MomentAction primary;
  final MomentAction? secondary;

  static const double _h = 52;

  @override
  Widget build(BuildContext context) {
    final onFill = AppThemes.onColor(fill, mode: scheme.brightness);
    final two = secondary != null;
    return Row(
      children: [
        Expanded(
          child: Material(
            color: fill,
            borderRadius: BorderRadius.horizontal(
              left: const Radius.circular(_h / 2),
              right: Radius.circular(two ? 8 : _h / 2),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: primary.onTap,
              child: SizedBox(
                height: _h,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(primary.icon, size: 20, color: onFill),
                        const SizedBox(width: 8),
                        Text(
                          primary.label,
                          maxLines: 1,
                          style: AppFonts.onest(size: 15, weight: 700, color: onFill),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (two) ...[
          const SizedBox(width: 2),
          Tooltip(
            message: secondary!.label,
            child: Material(
              color: scheme.secondaryContainer,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(8),
                right: Radius.circular(_h / 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: secondary!.onTap,
                child: SizedBox(
                  width: 56,
                  height: _h,
                  child: Icon(secondary!.icon, size: 22, color: scheme.onSecondaryContainer),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Постер или обложка книги: портрет 2:3 по центру тонального поля — так
/// он стоит на месте кадра и не растягивается во всю ширину на полэкрана.
class MomentPosterFrame extends StatelessWidget {
  const MomentPosterFrame({super.key, required this.scheme, required this.child});

  final ColorScheme scheme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(width: 180, height: 270, child: child),
        ),
      ),
    );
  }
}

/// Заглушка обложки, когда картинки нет: тональная заливка и значок типа.
class MomentArtPlaceholder extends StatelessWidget {
  const MomentArtPlaceholder({super.key, required this.scheme, required this.icon});

  final ColorScheme scheme;
  final IconData icon;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: Center(
          child: Icon(icon, size: 56, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
        ),
      );
}
