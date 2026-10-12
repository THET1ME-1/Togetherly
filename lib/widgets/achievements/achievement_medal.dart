import 'package:flutter/material.dart';
import 'package:material_new_shapes/material_new_shapes.dart';

import '../../models/pair_achievement.dart';
import '../connect_expressive.dart';
import 'achievement_art.dart';

/// Форма уровня — «печенье» M3: чем выше уровень, тем больше зубцов.
///
/// До 12.10.2026 уровень читался цветом металла (бронза, серебро, золото,
/// платина) — четыре своих цвета мимо темы. Форма говорит то же самое и
/// красится ролью схемы.
RoundedPolygon achievementShape(AchievementTier tier) => switch (tier) {
  AchievementTier.bronze => MaterialShapes.cookie4Sided,
  AchievementTier.silver => MaterialShapes.cookie6Sided,
  AchievementTier.gold => MaterialShapes.cookie9Sided,
  AchievementTier.platinum => MaterialShapes.cookie12Sided,
};

/// Число-цель на фигуре неполученного. Пятизначное в фигуру не помещается,
/// поэтому десятки тысяч сокращаются.
String medalNumber(int threshold) =>
    threshold >= 10000 ? '${threshold ~/ 1000}K' : '$threshold';

/// Достижение одной фигурой: полученное — рисунок на тональной подложке,
/// неполученное — число-цель на приглушённой. Рисунок неполученного не
/// показываем намеренно: он открывается наградой.
class AchievementMedal extends StatelessWidget {
  const AchievementMedal({
    super.key,
    required this.achievement,
    required this.earned,
    required this.size,
    this.fill,
    this.animated = true,
    this.onTap,
  });

  final PairAchievement achievement;
  final bool earned;
  final double size;

  /// Своя заливка подложки полученного; по умолчанию `secondaryContainer`.
  final Color? fill;

  /// Двигается ли рисунок. В плотном ряду мелких фигур движение выключают.
  final bool animated;

  /// Касание доходит только до полученного: у неполученного открывать нечего.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final number = medalNumber(achievement.threshold);
    final medal = SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: AchievementShapePainter(
          shape: achievementShape(achievement.tier),
          color: earned
              ? (fill ?? cs.secondaryContainer)
              : cs.onSurface.withValues(alpha: 0.09),
        ),
        child: Center(
          child: earned
              ? AchievementArt(
                  achievement,
                  side: size * 0.86,
                  animated: animated,
                )
              : Text(
                  number,
                  maxLines: 1,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: size * (number.length > 3 ? 0.24 : 0.3),
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    height: 1,
                    color: cs.onSurfaceVariant,
                  ),
                ),
        ),
      ),
    );
    return Semantics(
      label: achievement.title,
      button: earned && onTap != null,
      child: earned && onTap != null
          ? GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: medal,
            )
          : medal,
    );
  }
}

/// Заливка формы M3, вписанной в размер.
class AchievementShapePainter extends CustomPainter {
  const AchievementShapePainter({required this.shape, required this.color});

  final RoundedPolygon shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      m3ShapePath(shape, size),
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(AchievementShapePainter old) =>
      old.color != color || old.shape != shape;
}
