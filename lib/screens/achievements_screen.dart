import 'package:flutter/material.dart';

import '../models/pair_achievement.dart';
import '../services/achievement_service.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import '../theme/profile_theme.dart';
import '../widgets/achievement_medal.dart';
import '../widgets/common/m3_wave_progress.dart';

/// Что показываем в списке.
enum _Filter { all, unlocked, inProgress }

/// Экран «Достижения пары».
///
/// Список во всю ширину, а не сетка плиток: достижений тридцать восемь, и в
/// две колонки названия обрезались бы на полуслове, а прогресс приходилось бы
/// угадывать по длине полоски. Строкой помещается и название целиком, и
/// «78 из 100» словами.
///
/// Оформление — тональные контейнеры M3 вместо теней и градиентов: глубина
/// показывается цветом поверхности, полученное заливается `primaryContainer`.
/// Медаль — правильный многоугольник, число граней растёт с уровнем.
class AchievementsScreen extends StatefulWidget {
  final AppTheme theme;

  const AchievementsScreen({super.key, required this.theme});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  _Filter _filter = _Filter.all;

  AppStrings get _s => LocaleService.current;

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.schemeFor(widget.theme);
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
            _s.achievementsTitle,
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
            final sections = _sections(stats);

            return ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                MediaQuery.of(context).padding.bottom + 28,
              ),
              children: [
                _summary(cs, unlocked),
                const SizedBox(height: 14),
                _filters(cs),
                for (final entry in sections) ...[
                  const SizedBox(height: 18),
                  _sectionTitle(cs, entry.key),
                  const SizedBox(height: 8),
                  for (final a in entry.value)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _row(cs, a, stats),
                    ),
                ],
                if (sections.isEmpty) _empty(cs),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Достижения по разделам, уже с учётом фильтра. Пустые разделы не
  /// показываем — иначе при фильтре «получено» экран забит заголовками.
  List<MapEntry<String, List<PairAchievement>>> _sections(
      AchievementStats stats) {
    bool visible(PairAchievement a) => switch (_filter) {
          _Filter.all => true,
          _Filter.unlocked => a.isUnlockedBy(stats),
          _Filter.inProgress => !a.isUnlockedBy(stats),
        };

    final byMetric = <AchievementMetric, List<PairAchievement>>{};
    for (final a in PairAchievement.all.where(visible)) {
      byMetric.putIfAbsent(a.metric, () => []).add(a);
    }
    return [
      for (final m in AchievementMetric.values)
        if ((byMetric[m] ?? const []).isNotEmpty)
          MapEntry(_metricTitle(m), byMetric[m]!),
    ];
  }

  String _metricTitle(AchievementMetric m) => switch (m) {
        AchievementMetric.daysTogether => _s.achMetricDays,
        AchievementMetric.memories => _s.achMetricMemories,
        AchievementMetric.messages => _s.achMetricMessages,
        AchievementMetric.drawings => _s.achMetricDrawings,
        AchievementMetric.streakDays => _s.achMetricStreak,
      };

  Widget _summary(ColorScheme cs, int unlocked) {
    final total = PairAchievement.all.length;
    final ratio = total == 0 ? 0.0 : unlocked / total;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
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
              letterSpacing: -1,
              color: cs.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _s.achievementsUnlockedOf(unlocked, total),
            style: TextStyle(
              fontFamily: 'Onest',
              fontSize: 13,
              color: cs.onPrimaryContainer.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor:
                  cs.onPrimaryContainer.withValues(alpha: 0.18),
              valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters(ColorScheme cs) {
    Widget chip(String label, _Filter value) {
      final on = _filter == value;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(
          label: Text(label),
          selected: on,
          showCheckmark: false,
          onSelected: (_) => setState(() => _filter = value),
          labelStyle: TextStyle(
            fontFamily: 'Onest',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: on ? cs.onSecondaryContainer : cs.onSurfaceVariant,
          ),
          backgroundColor: Colors.transparent,
          selectedColor: cs.secondaryContainer,
          side: BorderSide(color: on ? Colors.transparent : cs.outlineVariant),
        ),
      );
    }

    return Row(
      children: [
        chip(_s.achFilterAll, _Filter.all),
        chip(_s.achFilterUnlocked, _Filter.unlocked),
        chip(_s.achFilterInProgress, _Filter.inProgress),
      ],
    );
  }

  Widget _sectionTitle(ColorScheme cs, String title) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            fontFamily: 'Onest',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: cs.onSurfaceVariant,
          ),
        ),
      );

  Widget _row(ColorScheme cs, PairAchievement a, AchievementStats stats) {
    final unlocked = a.isUnlockedBy(stats);
    final value = a.currentValue(stats);
    final progress = (value / a.threshold).clamp(0.0, 1.0);
    // Волна хороша, когда цель близко: на восьми процентах она читается как
    // помеха, а не как движение. Дальним целям оставляем ровную полосу.
    final nearGoal = progress >= 0.25;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: unlocked ? cs.surfaceContainerHighest : cs.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AchievementMedal(
            tier: a.tier,
            unlocked: unlocked,
            label: unlocked ? a.emoji : '${a.threshold}',
            size: 48,
            fill: unlocked ? a.tierColor : cs.surfaceContainerHighest,
            onFill: unlocked ? Colors.white : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  a.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  unlocked
                      ? a.description
                      : _s.achProgressOf(value, a.threshold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                if (!unlocked) ...[
                  const SizedBox(height: 7),
                  if (nearGoal)
                    M3WaveProgress(value: progress, color: cs.primary)
                  else
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: cs.outlineVariant,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(cs.primary),
                      ),
                    ),
                ],
              ],
            ),
          ),
          if (unlocked) ...[
            const SizedBox(width: 8),
            Icon(Icons.check_rounded, size: 20, color: cs.primary),
          ],
        ],
      ),
    );
  }

  Widget _empty(ColorScheme cs) => Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Center(
          child: Text(
            _s.achNothingHere,
            style: TextStyle(
              fontFamily: 'Onest',
              fontSize: 14,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      );
}
