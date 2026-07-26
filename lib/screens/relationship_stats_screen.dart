import 'package:flutter/material.dart';

import '../models/mood_entry.dart';
import '../services/locale_service.dart';
import '../services/mood_repository.dart';
import '../services/pb_data_service.dart';
import '../services/plus_service.dart';
import '../theme/app_theme.dart';
import '../theme/profile_theme.dart';
import '../utils/couple_days.dart';
import '../utils/relationship_tips.dart';
import '../widgets/common/m3_loading.dart';
import 'plus_screen.dart';

/// Расширенная статистика пары и советы на сегодня — раздел Togetherly+.
///
/// Цифры берём из тех же счётчиков, что ведёт сервер (`groups.memories_count`,
/// `drawings_count`, `streak_days`, `xp`) и из истории настроений. Ничего не
/// считаем заново на клиенте: расхождение с достижениями и виджетами дороже
/// любой красивой метрики.
///
/// Советы даёт готовый движок [RelationshipTips] — он до сих пор был написан,
/// но нигде не показывался.
class RelationshipStatsScreen extends StatefulWidget {
  const RelationshipStatsScreen({
    super.key,
    required this.theme,
    required this.groupId,
    required this.myUid,
    required this.partnerUid,
    this.startDate,
    this.anniversaryDate,
  });

  final AppTheme theme;
  final String groupId;
  final String myUid;
  final String partnerUid;

  /// Начало отношений — берётся тем же способом, что «дни вместе» на главном.
  final DateTime? startDate;
  final DateTime? anniversaryDate;

  @override
  State<RelationshipStatsScreen> createState() =>
      _RelationshipStatsScreenState();
}

class _RelationshipStatsScreenState extends State<RelationshipStatsScreen> {
  bool _loading = true;

  int _memories = 0;
  int _drawings = 0;
  int _streak = 0;
  int _xp = 0;

  /// Среднее настроение за 30 дней, 1…5. null — не отмечались.
  double? _myMood30;
  double? _partnerMood30;

  /// Отметок настроения за 30 дней у обоих.
  int _moodMarks = 0;

  List<RelationshipTip> _tips = const [];

  AppTheme get _t => widget.theme;
  AppStrings get _s => LocaleService.current;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final since = DateTime.now().subtract(const Duration(days: 30));
    try {
      final group = await PbDataService().loadGroupById(widget.groupId);
      if (group != null) {
        _memories = (group.data['memories_count'] as num?)?.toInt() ?? 0;
        _drawings = (group.data['drawings_count'] as num?)?.toInt() ?? 0;
        _streak = (group.data['streak_days'] as num?)?.toInt() ?? 0;
        _xp = (group.data['xp'] as num?)?.toInt() ?? 0;
      }

      final mine = await MoodRepository().load(widget.groupId, widget.myUid);
      final theirs = widget.partnerUid.isEmpty
          ? <dynamic>[]
          : await MoodRepository().load(widget.groupId, widget.partnerUid);

      _myMood30 = _averageScore(mine, since);
      _partnerMood30 = _averageScore(theirs, since);
      _moodMarks = _countSince(mine, since) + _countSince(theirs, since);

      _tips = RelationshipTips.forToday(TipContext(
        partnerMoodScore: _latestScore(theirs),
        myMoodScore: _latestScore(mine),
        daysTogether: coupleDaysTogether(
          groupStart: widget.startDate,
          timerStart: null,
        ),
        daysToAnniversary: _daysToAnniversary(),
      ));
    } catch (_) {
      // Сеть отвалилась — покажем то, что успели, вместо пустого экрана.
    }
    if (mounted) setState(() => _loading = false);
  }

  int _countSince(List<dynamic> entries, DateTime since) => entries
      .where((e) => (e.timestamp as DateTime).isAfter(since))
      .length;

  double? _averageScore(List<dynamic> entries, DateTime since) {
    final scores = entries
        .where((e) => (e.timestamp as DateTime).isAfter(since))
        .map(_scoreOf)
        .toList();
    if (scores.isEmpty) return null;
    return scores.reduce((a, b) => a + b) / scores.length;
  }

  /// Оценка записи 1…5. Настроение из пака, которого нет в каталоге, даёт
  /// нейтральную тройку — так же, как считают достижения.
  int _scoreOf(dynamic entry) {
    final id = entry.moodId as String;
    for (final m in MoodOption.all) {
      if (m.id == id) return m.score;
    }
    for (final m in MoodOption.pinkPack) {
      if (m.id == id) return m.score;
    }
    return 3;
  }

  int? _latestScore(List<dynamic> entries) {
    if (entries.isEmpty) return null;
    final sorted = [...entries]..sort((a, b) =>
        (b.timestamp as DateTime).compareTo(a.timestamp as DateTime));
    return _scoreOf(sorted.first);
  }

  int? _daysToAnniversary() {
    final date = widget.anniversaryDate ?? widget.startDate;
    if (date == null) return null;
    final now = DateTime.now();
    var next = DateTime(now.year, date.month, date.day);
    if (next.isBefore(DateTime(now.year, now.month, now.day))) {
      next = DateTime(now.year + 1, date.month, date.day);
    }
    return next.difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.themeFor(_t).colorScheme;
    final days = coupleDaysTogether(
      groupStart: widget.startDate,
      timerStart: null,
    );

    return Scaffold(
      backgroundColor: _t.bgGradient.last,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _s.statsTitle,
          style: TextStyle(
            fontFamily: ProfileTheme.displayFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _t.textPrimary,
          ),
        ),
      ),
      body: _loading
          ? M3PageLoading(color: _t.primaryLight)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (days != null && days > 0) _headline(cs, days),
                const SizedBox(height: 16),
                _numbers(cs),
                const SizedBox(height: 16),
                _mood(cs),
                if (_tips.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _tipsBlock(cs),
                ],
              ],
            ),
    );
  }

  Widget _headline(ColorScheme cs, int days) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$days',
              style: TextStyle(
                fontFamily: ProfileTheme.displayFont,
                fontSize: 44,
                fontWeight: FontWeight.w800,
                height: 1,
                color: cs.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _s.statsDaysTogether,
              style: TextStyle(
                fontFamily: ProfileTheme.bodyFont,
                fontSize: 14,
                color: cs.onPrimaryContainer.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      );

  Widget _numbers(ColorScheme cs) => GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.6,
        children: [
          _tile(cs, Icons.photo_library_rounded, '$_memories', _s.statsMemories),
          _tile(cs, Icons.brush_rounded, '$_drawings', _s.statsDrawings),
          _tile(cs, Icons.local_fire_department_rounded, '$_streak',
              _s.statsStreak),
          _tile(cs, Icons.auto_awesome_rounded, '$_xp', _s.statsXp),
        ],
      );

  Widget _tile(ColorScheme cs, IconData icon, String value, String label) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, size: 20, color: cs.primary),
            Text(
              value,
              style: TextStyle(
                fontFamily: ProfileTheme.displayFont,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontFamily: ProfileTheme.bodyFont,
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );

  Widget _mood(ColorScheme cs) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _s.statsMoodMonth,
              style: TextStyle(
                fontFamily: ProfileTheme.displayFont,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            _moodRow(cs, _s.statsMoodMine, _myMood30),
            const SizedBox(height: 8),
            _moodRow(cs, _s.statsMoodPartner, _partnerMood30),
            const SizedBox(height: 12),
            Text(
              _s.statsMoodMarks(_moodMarks),
              style: TextStyle(
                fontFamily: ProfileTheme.bodyFont,
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );

  Widget _moodRow(ColorScheme cs, String label, double? value) {
    // Пустая шкала честнее нуля: «не отмечались» и «настроение на нуле» —
    // разные вещи, а нарисованный ноль читается как второе.
    final fraction = value == null ? 0.0 : ((value - 1) / 4).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: ProfileTheme.bodyFont,
              fontSize: 13,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 10,
              backgroundColor: cs.secondaryContainer,
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 34,
          child: Text(
            value == null ? '—' : value.toStringAsFixed(1),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontFamily: ProfileTheme.displayFont,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  Widget _tipsBlock(ColorScheme cs) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: cs.tertiaryContainer,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _s.statsTipsTitle,
              style: TextStyle(
                fontFamily: ProfileTheme.displayFont,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: cs.onTertiaryContainer,
              ),
            ),
            for (final tip in _tips) ...[
              const SizedBox(height: 14),
              Text(
                tip.title,
                style: TextStyle(
                  fontFamily: ProfileTheme.bodyFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: cs.onTertiaryContainer,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                tip.body,
                style: TextStyle(
                  fontFamily: ProfileTheme.bodyFont,
                  fontSize: 13,
                  height: 1.4,
                  color: cs.onTertiaryContainer.withValues(alpha: 0.85),
                ),
              ),
            ],
          ],
        ),
      );
}

/// Открывает статистику, если куплен Togetherly+, иначе ведёт на его страницу.
Future<void> openRelationshipStats(
  BuildContext context, {
  required AppTheme theme,
  required String groupId,
  required String myUid,
  required String partnerUid,
  DateTime? startDate,
  DateTime? anniversaryDate,
}) async {
  if (!PlusService.instance.active) {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            PlusScreen(scheme: ProfileTheme.themeFor(theme).colorScheme),
        settings: const RouteSettings(name: '/plus'),
      ),
    );
    return;
  }
  if (!context.mounted) return;
  await Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => RelationshipStatsScreen(
        theme: theme,
        groupId: groupId,
        myUid: myUid,
        partnerUid: partnerUid,
        startDate: startDate,
        anniversaryDate: anniversaryDate,
      ),
      settings: const RouteSettings(name: '/relationship_stats'),
    ),
  );
}
