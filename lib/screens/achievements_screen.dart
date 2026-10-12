import 'package:flutter/material.dart';

import '../models/pair_achievement.dart';
import '../services/achievement_service.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import '../theme/profile_theme.dart';
import '../widgets/achievements/achievement_medal.dart';
import '../widgets/achievements/achievement_sheet.dart';

/// Экран «Достижения пары» — «Полки».
///
/// Пять блоков по семьям вместо тридцати восьми строк: в каждом вся семья по
/// порядку и ближайшая цель. Человек открывает экран за двумя ответами — что
/// уже есть и сколько до следующего, — и оба видны без прокрутки списка и без
/// фильтров (прежние «Все · Получено · В процессе» отвечали на то же самое).
///
/// Полученное — рисунок от руки на фигуре уровня, неполученное — число-цель.
/// Касание по рисунку открывает его лист. Макет:
/// https://claude.ai/artifact/BFi4jzBm3SMzskCgKmTFSW, вариант «Полки».
class AchievementsScreen extends StatelessWidget {
  final AppTheme theme;

  const AchievementsScreen({super.key, required this.theme});

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final cs = ProfileTheme.schemeFor(theme);
    return Theme(
      data: ProfileTheme.data(cs),
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: cs.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          iconTheme: IconThemeData(color: cs.onSurface),
          title: Text(
            s.achievementsTitle,
            style: TextStyle(
              fontFamily: 'Unbounded',
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
        ),
        body: ValueListenableBuilder<AchievementStats>(
          valueListenable: AchievementService.instance.stats,
          builder: (context, stats, _) {
            final unlocked =
                PairAchievement.all.where((a) => a.isUnlockedBy(stats)).length;
            return ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                MediaQuery.of(context).padding.bottom + 28,
              ),
              children: [
                _summary(s, unlocked),
                for (final metric in AchievementMetric.values)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: AchievementShelf(
                      metric: metric,
                      title: _metricTitle(s, metric),
                      stats: stats,
                      onOpen: (a) =>
                          showAchievementSheet(context, a, stats: stats),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _metricTitle(AppStrings s, AchievementMetric m) => switch (m) {
        AchievementMetric.daysTogether => s.achMetricDays,
        AchievementMetric.memories => s.achMetricMemories,
        AchievementMetric.messages => s.achMetricMessages,
        AchievementMetric.drawings => s.achMetricDrawings,
        AchievementMetric.streakDays => s.achMetricStreak,
      };

  /// Сводка — сплошной цвет темы. `primaryContainer` тут не годится: у палитр,
  /// нарисованных руками, он почти равен фону страницы, и блок пропадает.
  Widget _summary(AppStrings s, int unlocked) {
    final total = PairAchievement.all.length;
    final fill = theme.fillColor;
    final on = AppThemes.onColor(fill, mode: theme.brightness);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$unlocked / $total',
            style: TextStyle(
              fontFamily: 'Unbounded',
              fontSize: 40,
              height: 1,
              fontWeight: FontWeight.w800,
              fontVariations: const [FontVariation('wght', 800)],
              letterSpacing: -1,
              color: on,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            s.achievementsUnlockedOf(unlocked, total),
            style: TextStyle(
              fontFamily: 'Onest',
              fontSize: 13,
              color: on.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: total == 0 ? 0.0 : unlocked / total,
              minHeight: 8,
              backgroundColor: on.withValues(alpha: 0.26),
              valueColor: AlwaysStoppedAnimation<Color>(on),
            ),
          ),
        ],
      ),
    );
  }
}

/// Полка одной семьи: заголовок, сколько получено, вся семья лентой и
/// ближайшая цель.
class AchievementShelf extends StatelessWidget {
  const AchievementShelf({
    super.key,
    required this.metric,
    required this.title,
    required this.stats,
    required this.onOpen,
  });

  final AchievementMetric metric;
  final String title;
  final AchievementStats stats;

  /// Касание по полученному достижению.
  final ValueChanged<PairAchievement> onOpen;

  /// Сторона фигуры в ленте и зазор между ними.
  static const double _medal = 64;
  static const double _gap = 8;
  static const double _side = 18;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final family = PairAchievement.family(metric);
    final have = family.where((a) => a.isUnlockedBy(stats)).length;
    final next = PairAchievement.nextGoal(metric, stats);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _side),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: ProfileTheme.sectionLabel(cs),
                  ),
                ),
                const SizedBox(width: 8),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$have',
                        style: TextStyle(
                          fontFamily: 'Unbounded',
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          fontVariations: const [FontVariation('wght', 800)],
                          color: cs.onSurface,
                        ),
                      ),
                      TextSpan(
                        text: ' / ${family.length}',
                        style: TextStyle(
                          fontFamily: 'Onest',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: _medal,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: _side),
              itemCount: family.length,
              separatorBuilder: (_, _) => const SizedBox(width: _gap),
              itemBuilder: (_, i) {
                final a = family[i];
                return AchievementMedal(
                  achievement: a,
                  earned: a.isUnlockedBy(stats),
                  size: _medal,
                  onTap: () => onOpen(a),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _side),
            child: next == null
                ? Text(
                    LocaleService.current.achAllCollected,
                    style: TextStyle(
                      fontFamily: 'Onest',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    ),
                  )
                : AchievementGoal(goal: next, stats: stats),
          ),
        ],
      ),
    );
  }
}
