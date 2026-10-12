import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../models/pair_achievement.dart';
import '../../services/locale_service.dart';
import '../../theme/motion.dart';
import '../../theme/profile_theme.dart';
import '../../theme/theme_scope.dart';
import '../app_sheet.dart';
import 'achievement_art.dart';
import 'achievement_medal.dart';

/// Сколько фигур семьи помещается в лестницу листа.
const int kLadderWindow = 6;

/// Кусок семьи для лестницы листа: не больше [count] достижений подряд, и
/// [current] обязательно среди них. Семьи бывают по десять достижений, а в
/// ширину листа на 320 точках входит шесть фигур.
List<PairAchievement> ladderWindow(
  List<PairAchievement> family,
  PairAchievement current, {
  int count = kLadderWindow,
}) {
  if (family.length <= count) return family;
  final at = math.max(0, family.indexOf(current));
  final from = (at - 2).clamp(0, family.length - count);
  return family.sublist(from, from + count);
}

/// Нижний лист достижения — замена попапа по центру экрана.
///
/// [fresh] — достижение получено только что (подпись «Достижение получено!»,
/// кнопка «Отлично»); иначе лист открыт из списка («Получено», «Закрыть»).
/// [position] и [total] — место в пачке, когда открылось несколько разом.
///
/// Отдаёт true, если человек нажал главную кнопку, и null, если смахнул лист:
/// по этому очередь понимает, показывать ли следующее.
Future<bool?> showAchievementSheet(
  BuildContext context,
  PairAchievement achievement, {
  required AchievementStats stats,
  bool fresh = false,
  int position = 1,
  int total = 1,
  VoidCallback? onSeeAll,
}) {
  // Тему снимаем до открытия: лист живёт в дереве навигатора и переживает
  // экран, с которого его открыли.
  final theme = context.appTheme;
  final cs = ProfileTheme.schemeFor(theme);
  return showAppSheet<bool>(
    context,
    background: cs.surfaceContainerHigh,
    builder: (sheet) => ThemeScope(
      theme: theme,
      child: Theme(
        data: ProfileTheme.data(cs),
        child: AchievementSheetBody(
          achievement: achievement,
          stats: stats,
          fresh: fresh,
          position: position,
          total: total,
          onDone: () => Navigator.of(sheet).pop(true),
          onSeeAll: onSeeAll == null
              ? null
              : () {
                  Navigator.of(sheet).pop(true);
                  onSeeAll();
                },
        ),
      ),
    ),
  );
}

/// Содержимое листа достижения: рисунок на фигуре уровня, название, вся семья
/// по порядку и ближайшая цель.
class AchievementSheetBody extends StatelessWidget {
  const AchievementSheetBody({
    super.key,
    required this.achievement,
    required this.stats,
    this.fresh = false,
    this.position = 1,
    this.total = 1,
    this.onDone,
    this.onSeeAll,
  });

  final PairAchievement achievement;
  final AchievementStats stats;
  final bool fresh;
  final int position;
  final int total;
  final VoidCallback? onDone;
  final VoidCallback? onSeeAll;

  bool get _last => position >= total;

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final cs = Theme.of(context).colorScheme;
    final a = achievement;
    final over = fresh ? s.achievementUnlocked : s.achFilterUnlocked;
    final main = !_last ? s.welcomeNext : (fresh ? s.great : s.close);

    return SheetScaffold(
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: onDone, child: Text(main)),
          ),
          if (onSeeAll != null && _last)
            TextButton(
              onPressed: onSeeAll,
              child: Text(
                s.achSeeAll,
                style: const TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Text(
                  over.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: ProfileTheme.sectionLabel(cs),
                ),
                if (total > 1)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      s.achProgressOf(position, total),
                      style: TextStyle(
                        fontFamily: 'Onest',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        color: cs.onSecondaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _AchievementHero(key: ValueKey(a.id), achievement: a),
            const SizedBox(height: 12),
            Text(
              a.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Unbounded',
                fontSize: 24,
                height: 1.12,
                fontWeight: FontWeight.w800,
                fontVariations: const [FontVariation('wght', 800)],
                letterSpacing: -0.4,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              a.description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Onest',
                fontSize: 15,
                height: 1.3,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            _family(context, cs, s),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  /// Семья по порядку и ближайшая цель: видно, что уже есть и сколько осталось.
  Widget _family(BuildContext context, ColorScheme cs, AppStrings s) {
    final family = PairAchievement.family(achievement.metric);
    final shown = ladderWindow(family, achievement);
    final next = PairAchievement.nextGoal(achievement.metric, stats);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, box) {
              const gap = 6.0;
              final fit = (box.maxWidth - gap * (shown.length - 1)) /
                  shown.length;
              final size = fit.clamp(24.0, 44.0);
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final x in shown)
                    AchievementMedal(
                      achievement: x,
                      earned: x.isUnlockedBy(stats),
                      size: size,
                      // В лестнице фигуры мелкие и их шесть: движение здесь
                      // спорило бы с рисунком наверху листа.
                      animated: false,
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          if (next == null)
            Text(
              s.achAllCollected,
              style: TextStyle(
                fontFamily: 'Onest',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            )
          else
            AchievementGoal(goal: next, stats: stats),
        ],
      ),
    );
  }
}

/// Ближайшая цель семьи: название, «45 из 100» и ровная полоса.
///
/// Полоса обычная, не волновая: волна значит «процесс идёт прямо сейчас», а
/// тут счёт, который стоит на месте.
class AchievementGoal extends StatelessWidget {
  const AchievementGoal({super.key, required this.goal, required this.stats});

  final PairAchievement goal;
  final AchievementStats stats;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final value = goal.currentValue(stats);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                goal.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              LocaleService.current.achProgressOf(value, goal.threshold),
              style: TextStyle(
                fontFamily: 'Onest',
                fontSize: 13,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: goal.progress(stats),
            minHeight: 6,
            backgroundColor: cs.onSurface.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation<Color>(
              context.appTheme.fillColor,
            ),
          ),
        ),
      ],
    );
  }
}

/// Рисунок на фигуре уровня цвета темы. Фигура встаёт на место пружиной с
/// доворотом, следом вырастает рисунок — только размером, без прозрачности.
/// Конфетти и искр нет: двигается сам рисунок.
class _AchievementHero extends StatefulWidget {
  const _AchievementHero({super.key, required this.achievement});

  final PairAchievement achievement;

  @override
  State<_AchievementHero> createState() => _AchievementHeroState();
}

class _AchievementHeroState extends State<_AchievementHero>
    with TickerProviderStateMixin {
  static const double _side = 176;

  late final AnimationController _shape = AnimationController.unbounded(
    vsync: this,
    value: 0,
  );
  late final AnimationController _art = AnimationController.unbounded(
    vsync: this,
    value: 0,
  );
  Timer? _artDelay;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _shape.value = 1;
      _art.value = 1;
      return;
    }
    _shape.animateWith(SpringSimulation(Motion.spatial, 0, 1, 0));
    _artDelay = Timer(Motion.short4, () {
      if (mounted) _art.animateWith(SpringSimulation(Motion.spatial, 0, 1, 0));
    });
  }

  @override
  void dispose() {
    _artDelay?.cancel();
    _shape.dispose();
    _art.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.achievement;
    final fill = context.appTheme.fillColor;
    return SizedBox.square(
      dimension: _side,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _shape,
            builder: (_, child) => Transform.rotate(
              angle: (1 - _shape.value) * -0.7,
              child: Transform.scale(
                scale: 0.55 + 0.45 * _shape.value,
                child: child,
              ),
            ),
            child: RepaintBoundary(
              child: CustomPaint(
                size: const Size.square(_side),
                painter: AchievementShapePainter(
                  shape: achievementShape(a.tier),
                  color: fill,
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _art,
            builder: (_, child) => Transform.scale(
              scale: math.max(0, _art.value),
              child: child,
            ),
            child: AchievementArt(a, side: _side * 0.84),
          ),
        ],
      ),
    );
  }
}
