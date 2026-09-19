import 'package:flutter/material.dart';
import 'package:material_new_shapes/material_new_shapes.dart';

import '../../models/memory.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/profile_theme.dart';
import '../../utils/color_distance.dart';
import '../common/animations.dart';
import '../common/halftone_painter.dart';
import '../connect_expressive.dart';

/// Меньше этой разницы цветов (ΔE) фигура полки сливается с листом.
///
/// Замер по всем 25 палитрам (19.09.2026): у `secondaryContainer` на фоне
/// листа в светлой теме ΔE 8–14, у «Монохрома» 5,6 — фигуру там почти не
/// видно. Восьмёрка — значение из утверждённого макета на розовой теме.
const double kShelfMinDelta = 8;

/// Цвет фигуры на полке: контейнер схемы, а если он теряется на листе —
/// тот же контейнер, чуть сдвинутый к цвету роли [toward].
///
/// Заметный контейнер не трогаем: так лист остаётся ровно таким, каким его
/// утвердили в макете, а подтягиваются только бледные палитры.
Color shelfTint(Color container, {required Color toward, required Color on}) {
  if (deltaE(container, on) >= kShelfMinDelta) return container;
  for (var t = 0.05; t <= 1.0; t += 0.05) {
    final c = Color.lerp(container, toward, t)!;
    if (deltaE(c, on) >= kShelfMinDelta) return c;
  }
  return toward;
}

/// Кегль подписи на полке: 12,5, но самое длинное слово обязано влезть в
/// ячейку целиком.
///
/// На 320 точках при системном шрифте 1,3 ячейке достаётся 54 точки, и
/// Flutter рвал слово посреди: «Музык/а», «ссылк/е», «Musiqu/e». Подпись из
/// пары слов пусть переносится по словам, а само слово — нет: кегль
/// уменьшается ровно настолько, чтобы оно встало, но не мельче 9.
double shelfLabelSize(
  String label, {
  required double maxWidth,
  required TextScaler scaler,
}) {
  const base = 12.5;
  var widest = 0.0;
  for (final word in label.split(RegExp(r'\s+'))) {
    if (word.isEmpty) continue;
    final tp = TextPainter(
      text: TextSpan(
        text: word,
        style: const TextStyle(
          fontFamily: 'Onest',
          fontSize: base,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    if (tp.width > widest) widest = tp.width;
    tp.dispose();
  }
  // Точка запаса: ширина строки в абзаце выходит чуть больше замеренной.
  if (widest <= maxWidth - 1 || widest == 0) return base;
  final fitted = base * (maxWidth - 1) / widest;
  return fitted < 9 ? 9 : fitted;
}

/// Лист «Добавить воспоминание»: главное и полка (макет А, 19.09.2026).
///
/// Снимком делятся чаще всего, поэтому фото, видео и заметка — одна большая
/// кнопка в заливке темы. Пять реже нужных типов стоят на полке под ней,
/// каждый в своей форме M3, подписи короткие. Капсула отдельно, тёмной
/// пилюлей: это письмо в будущее, а не ещё один тип записи.
///
/// У прежнего листа не было боковых полей: плитки лежали на краях экрана.
/// Здесь поля по 16 точек, а высоту полки задаёт сама подпись, без
/// заданного отношения сторон, поэтому крупный системный шрифт её не режет.
class AddMemorySheetBody extends StatelessWidget {
  const AddMemorySheetBody({
    super.key,
    required this.scheme,
    required this.fill,
    required this.onType,
    required this.onCapsule,
  });

  /// Схема темы пары.
  final ColorScheme scheme;

  /// Заливка темы (`AppTheme.fillColor`). Контейнеры схемы у рисованных тем
  /// почти совпадают с фоном, а сплошной блок обязан быть виден.
  final Color fill;

  final ValueChanged<MemoryType> onType;
  final VoidCallback onCapsule;

  /// Полка слева направо.
  static const shelfTypes = [
    MemoryType.video,
    MemoryType.location,
    MemoryType.music,
    MemoryType.book,
    MemoryType.movie,
  ];

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final cs = scheme;
    final sc = shelfTint(
      cs.secondaryContainer,
      toward: cs.secondary,
      on: cs.surfaceContainer,
    );
    final tc = shelfTint(
      cs.tertiaryContainer,
      toward: cs.tertiary,
      on: cs.surfaceContainer,
    );

    final shelf = [
      (
        MemoryType.video,
        s.addShelfVideo,
        MaterialShapes.pill,
        sc,
        cs.onSecondaryContainer,
        memoryTypeIcon(MemoryType.videoLink),
      ),
      (
        MemoryType.location,
        s.addShelfPlace,
        MaterialShapes.arch,
        tc,
        cs.onTertiaryContainer,
        memoryTypeIcon(MemoryType.location),
      ),
      (
        MemoryType.music,
        s.music,
        MaterialShapes.clover4Leaf,
        sc,
        cs.onSecondaryContainer,
        memoryTypeIcon(MemoryType.music),
      ),
      (
        MemoryType.book,
        s.addShelfBook,
        MaterialShapes.gem,
        tc,
        cs.onTertiaryContainer,
        memoryTypeIcon(MemoryType.book),
      ),
      (
        MemoryType.movie,
        s.addShelfMovie,
        MaterialShapes.pentagon,
        sc,
        cs.onSecondaryContainer,
        memoryTypeIcon(MemoryType.movie),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.addMemoryTitle,
            style: TextStyle(
              fontFamily: ProfileTheme.displayFont,
              fontSize: 21,
              fontWeight: FontWeight.w700,
              fontVariations: const [FontVariation('wght', 700)],
              letterSpacing: -0.2,
              height: 1.2,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          _Hero(
            key: const ValueKey('add-hero'),
            fill: fill,
            ink: AppThemes.onColor(fill, mode: cs.brightness),
            dark: cs.brightness == Brightness.dark,
            title: s.addHeroTitle,
            subtitle: s.addHeroSub,
            onTap: () => onType(MemoryType.photo),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, box) {
              // Кегль один на всю полку: подписи разного размера рядом читаются
              // небрежностью. Берём самый мелкий из тех, что нужны каждому слову.
              final cell =
                  (box.maxWidth - 4 * (shelf.length - 1)) / shelf.length;
              final scaler = MediaQuery.textScalerOf(context);
              var size = 12.5;
              for (final item in shelf) {
                final fit = shelfLabelSize(
                  item.$2,
                  maxWidth: cell,
                  scaler: scaler,
                );
                if (fit < size) size = fit;
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < shelf.length; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    Expanded(
                      child: _ShelfItem(
                        key: ValueKey('add-${shelf[i].$1.name}'),
                        label: shelf[i].$2,
                        shape: shelf[i].$3,
                        color: shelf[i].$4,
                        ink: shelf[i].$5,
                        icon: shelf[i].$6,
                        textColor: cs.onSurface,
                        fontSize: size,
                        onTap: () => onType(shelf[i].$1),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          _Capsule(
            key: const ValueKey('add-capsule'),
            scheme: cs,
            title: s.timeCapsule,
            subtitle: s.capsuleAddSub,
            onTap: onCapsule,
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    super.key,
    required this.fill,
    required this.ink,
    required this.dark,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Color fill;
  final Color ink;
  final bool dark;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      excludeSemantics: true,
      child: QuickTapScale(
        scale: 0.97,
        onTap: onTap,
        child: Material(
          color: fill,
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          // Растр под подписью (макет «Узор кнопки», 19.09.2026): точки
          // цветом подписи растут к правому краю, левая треть чистая.
          child: CustomPaint(
            painter: HalftonePainter(color: ink, dark: dark),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 104),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontFamily: 'Onest',
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                              color: ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontFamily: 'Onest',
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              height: 1.3,
                              color: ink.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    _ShapeIcon(
                      size: 64,
                      shape: MaterialShapes.cookie9Sided,
                      color: ink,
                      icon: memoryTypeIcon(MemoryType.photo),
                      iconSize: 28,
                      iconColor: fill,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShelfItem extends StatelessWidget {
  const _ShelfItem({
    super.key,
    required this.label,
    required this.shape,
    required this.color,
    required this.ink,
    required this.icon,
    required this.textColor,
    required this.fontSize,
    required this.onTap,
  });

  final double fontSize;
  final String label;
  final RoundedPolygon shape;
  final Color color;
  final Color ink;
  final IconData icon;
  final Color textColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: QuickTapScale(
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, box) {
            // На 320 точках на ячейку остаётся 54 — фигура ужимается вместе
            // с ней, а не вылезает к соседке.
            final side = box.maxWidth < 56 ? box.maxWidth : 56.0;
            final style = TextStyle(
              fontFamily: 'Onest',
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              height: 1.2,
              color: textColor,
            );
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ShapeIcon(
                  size: side,
                  shape: shape,
                  color: color,
                  icon: icon,
                  iconSize: 24,
                  iconColor: ink,
                ),
                const SizedBox(height: 8),
                Text(label, textAlign: TextAlign.center, style: style),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Capsule extends StatelessWidget {
  const _Capsule({
    super.key,
    required this.scheme,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final ColorScheme scheme;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = scheme;
    final ink = cs.onInverseSurface;
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      excludeSemantics: true,
      child: QuickTapScale(
        scale: 0.97,
        onTap: onTap,
        child: Material(
          color: cs.inverseSurface,
          shape: const StadiumBorder(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: cs.inversePrimary,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.mail_rounded,
                      size: 20,
                      color: AppThemes.onColor(
                        cs.inversePrimary,
                        mode: cs.brightness,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontFamily: 'Onest',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                            color: ink,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontFamily: 'Onest',
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            height: 1.25,
                            color: ink.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 24, color: ink),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Значок внутри формы M3.
class _ShapeIcon extends StatelessWidget {
  const _ShapeIcon({
    required this.size,
    required this.shape,
    required this.color,
    required this.icon,
    required this.iconSize,
    required this.iconColor,
  });

  final double size;
  final RoundedPolygon shape;
  final Color color;
  final IconData icon;
  final double iconSize;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: ClipPath(
              clipper: M3ShapeClipper(shape),
              child: ColoredBox(color: color),
            ),
          ),
          Icon(icon, size: iconSize, color: iconColor),
        ],
      ),
    );
  }
}
