import 'package:flutter/material.dart';

import '../../models/pair_achievement.dart';
import '../common/gift_image.dart';

/// Рисунок достижения: живая анимация из серверного каталога, а пока её нет
/// (каталог не пришёл, нет сети) — неподвижный кадр из сборки.
///
/// Рисуется и запекается в мастерской `togetherly-badges-hand`
/// (`achievements.js`, `bake_ach.py`) той же рукой, что значки и подарки. В
/// каталоге это запись вида `art` с ключом `ach_<id>`; её приложение разбирает
/// тем же кодом, что картинки подарков, поэтому показ идёт через [GiftImage].
class AchievementArt extends StatelessWidget {
  const AchievementArt(
    this.achievement, {
    super.key,
    required this.side,
    this.animated = true,
  });

  final PairAchievement achievement;

  /// Сторона рисунка на экране, в логических точках.
  final double side;

  /// false — неподвижный кадр. «Уменьшить движение» в системе даёт его же.
  final bool animated;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return GiftImage(
      achievement.artKey,
      side: side,
      animated: animated && !still,
      stillAsset: achievement.stillAsset,
    );
  }
}
