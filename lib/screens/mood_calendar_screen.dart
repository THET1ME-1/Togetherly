import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../theme/fonts.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/cycle_entry.dart';
import '../models/mood_entry.dart';
import '../models/pair_data.dart';
import '../models/user_data.dart';
import '../services/cycle_service.dart';
import '../services/locale_service.dart';
import '../services/mood_service.dart';
import '../services/widget_service.dart';
import '../theme/app_theme.dart';
import '../theme/profile_theme.dart';
import '../theme/cycle_colors.dart';
import '../utils/cycle_math.dart';
import '../widgets/cycle/cycle_tips_strip.dart';
import '../widgets/cycle_analytics.dart';
import '../widgets/mood/mood_ring_stats.dart';
import '../widgets/mood_image.dart';
import 'home/widgets/day_log_sheet.dart';

/// Режим календаря настроений.
enum _CalMode { week, month, year }

/// Экран «Календарь настроений».
///
/// Сетка календаря повторяет ScoreMaster (M3 Expressive): ячейка-день —
/// тональный контейнер со скруглением и числом дня; день с настроением залит
/// мягким цветом эмоции и показывает саму эмодзи; сегодня обведён. Чипы
/// Неделя/Месяц/Год заливаются `primary`, период листается стрелками в любом
/// режиме. Ниже сетки — распределение и график среднего настроения.
class MoodCalendarScreen extends StatefulWidget {
  final PairData pairData;
  final MoodService moodService;
  final WidgetService widgetService;

  final AppTheme theme;

  /// Нужен листу дня: пункт «Цикл» показывается только женскому полу.
  final UserData? userData;

  const MoodCalendarScreen({
    super.key,
    required this.pairData,
    required this.moodService,
    required this.widgetService,
    required this.theme,
    this.userData,
  });

  @override
  State<MoodCalendarScreen> createState() => _MoodCalendarScreenState();
}

class _MoodCalendarScreenState extends State<MoodCalendarScreen> {
  _CalMode _calMode = _CalMode.month;
  late DateTime _calAnchor;
  double _calendarScale = 1.0;
  double _baseScale = 1.0;
  bool _legendExpanded = false;
  bool _myCycleExpanded = false;
  bool _partnerCycleExpanded = false;

  MoodService get _mood => widget.moodService;
  PairData get _pair => widget.pairData;
  WidgetService get _ws => widget.widgetService;
  CycleService get _cycle => CycleService.instance;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _calAnchor = DateTime(now.year, now.month, now.day);
    _mood.addListener(_onChanged);
    _mood.loadSettings();
    // Отметки цикла рисуются прямо в сетке настроений, поэтому экран следит и
    // за ними: поставленная в листе менструация красит ячейку сразу.
    _cycle.addListener(_onChanged);

    for (final p in _pair.partners) {
      _mood.listenToPartner(p.uid);
    }
  }

  @override
  void dispose() {
    _mood.removeListener(_onChanged);
    _cycle.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _showMoodSettings() {
    final s = LocaleService.current;
    final primary = widget.theme.primary;
    showModalBottomSheet(
      context: context,
      backgroundColor: widget.theme.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: widget.theme.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                s.moodSettings,
                style: AppFonts.onest(size: 18, weight: 800, color: widget.theme.textPrimary),
              ),
              const SizedBox(height: 16),
              StatefulBuilder(
                builder: (ctx, setSheetState) => Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.moodMultiplePerDay,
                            style: AppFonts.onest(size: 14, weight: 600, color: widget.theme.textPrimary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            s.moodMultiplePerDaySubtitle,
                            style: AppFonts.onest(size: 12, color: widget.theme.textMuted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Switch.adaptive(
                      value: _mood.allowMultipleMoodsPerDay,
                      activeColor: primary,
                      onChanged: (v) {
                        _mood.setAllowMultipleMoodsPerDay(v);
                        setSheetState(() {});
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Период (для статистики) ──

  DateTime get _periodStart {
    switch (_calMode) {
      case _CalMode.week:
        final monday =
            _calAnchor.subtract(Duration(days: _calAnchor.weekday - 1));
        return DateTime(monday.year, monday.month, monday.day);
      case _CalMode.month:
        return DateTime(_calAnchor.year, _calAnchor.month);
      case _CalMode.year:
        return DateTime(_calAnchor.year);
    }
  }

  DateTime get _periodEnd {
    switch (_calMode) {
      case _CalMode.week:
        return _periodStart.add(const Duration(days: 6));
      case _CalMode.month:
        return DateTime(_calAnchor.year, _calAnchor.month + 1, 0);
      case _CalMode.year:
        return DateTime(_calAnchor.year, 12, 31);
    }
  }

  void _shiftAnchor(int dir) {
    HapticFeedback.selectionClick();
    setState(() {
      switch (_calMode) {
        case _CalMode.week:
          _calAnchor = _calAnchor.add(Duration(days: 7 * dir));
        case _CalMode.month:
          _calAnchor = DateTime(_calAnchor.year, _calAnchor.month + dir, 1);
        case _CalMode.year:
          _calAnchor = DateTime(_calAnchor.year + dir, _calAnchor.month, 1);
      }
    });
  }

  String _calTitle() {
    final months = LocaleService.current.fullMonths; // 1-based, [0] пустой
    final short = LocaleService.current.shortMonths; // 0-based
    switch (_calMode) {
      case _CalMode.week:
        final monday =
            _calAnchor.subtract(Duration(days: _calAnchor.weekday - 1));
        final sunday = monday.add(const Duration(days: 6));
        if (monday.month == sunday.month) {
          return '${monday.day}–${sunday.day} ${months[monday.month]}';
        }
        return '${monday.day} ${short[monday.month - 1]} – '
            '${sunday.day} ${short[sunday.month - 1]}';
      case _CalMode.month:
        return '${months[_calAnchor.month]} ${_calAnchor.year}';
      case _CalMode.year:
        return '${_calAnchor.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ProfileTheme.schemeFor(widget.theme);
    return Scaffold(
      backgroundColor: widget.theme.surfaceMuted,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: widget.theme.cardSurface,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              LocaleService.current.moodCalendarTitle,
              style: AppFonts.onest(size: 20, weight: 800, color: widget.theme.textPrimary),
            ),
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.zoom_out_rounded, size: 22),
                onPressed: _calendarScale > 0.7
                    ? () => setState(() => _calendarScale =
                        (_calendarScale - 0.15).clamp(0.7, 1.5))
                    : null,
                tooltip: LocaleService.current.zoomOut,
              ),
              IconButton(
                icon: const Icon(Icons.zoom_in_rounded, size: 22),
                onPressed: _calendarScale < 1.5
                    ? () => setState(() => _calendarScale =
                        (_calendarScale + 0.15).clamp(0.7, 1.5))
                    : null,
                tooltip: LocaleService.current.zoomIn,
              ),
              IconButton(
                icon: const Icon(Icons.tune_rounded, size: 22),
                onPressed: _showMoodSettings,
                tooltip: LocaleService.current.moodSettings,
              ),
            ],
          ),

          // ── Переключатель режима + навигация периода ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: _calControls(scheme),
            ),
          ),

          // ── Легенда ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: _buildLegend(),
            ),
          ),

          // ── Мой календарь ──
          SliverToBoxAdapter(
            child: GestureDetector(
              onScaleStart: (_) => _baseScale = _calendarScale,
              onScaleUpdate: (d) => setState(() =>
                  _calendarScale = (_baseScale * d.scale).clamp(0.7, 1.5)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Transform.scale(
                  scale: _calendarScale,
                  alignment: Alignment.topCenter,
                  child: _buildCalendarSection(
                    scheme: scheme,
                    label: LocaleService.current.myMood,
                    entries: _mood.myEntries,
                    stats: _mood.myStats(from: _periodStart, to: _periodEnd),
                  ),
                ),
              ),
            ),
          ),

          // ── Календари партнёров ──
          ..._pair.partners.map(
            (p) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Transform.scale(
                  scale: _calendarScale,
                  alignment: Alignment.topCenter,
                  child: _buildCalendarSection(
                    scheme: scheme,
                    label: LocaleService.current.partnerMood(p.name),
                    entries: _mood.partnerEntries(p.uid),
                    stats: _mood.partnerStats(p.uid,
                        from: _periodStart, to: _periodEnd),
                    isPartner: true,
                    ownerName: p.name,
                  ),
                ),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  КОНТРОЛЫ КАЛЕНДАРЯ (чипы + навигация)
  // ═══════════════════════════════════════════

  Widget _calControls(ColorScheme scheme) {
    final labels = [
      (_CalMode.week, LocaleService.current.week),
      (_CalMode.month, LocaleService.current.month),
      (_CalMode.year, LocaleService.current.year),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          Row(
            children: [
              for (final m in labels) ...[
                _calModeChip(m.$2, m.$1 == _calMode, () {
                  HapticFeedback.selectionClick();
                  setState(() => _calMode = m.$1);
                }, scheme),
                if (m.$1 != _CalMode.year) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => _shiftAnchor(-1),
                icon: Icon(Icons.chevron_left_rounded, color: scheme.onSurface),
              ),
              Expanded(
                child: Text(
                  _calTitle(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Unbounded',
                    fontWeight: FontWeight.w700,
        fontVariations: const [FontVariation('wght', 700)],
                    letterSpacing: -0.3,
                    fontSize: 16,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => _shiftAnchor(1),
                icon:
                    Icon(Icons.chevron_right_rounded, color: scheme.onSurface),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _calModeChip(
      String label, bool sel, VoidCallback onTap, ColorScheme scheme) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sel ? scheme.primary : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Onest',
              fontSize: 13,
              fontWeight: FontWeight.w700,
        fontVariations: const [FontVariation('wght', 700)],
              color: sel ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  ЛЕГЕНДА
  // ═══════════════════════════════════════════

  Widget _buildLegend() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _legendExpanded = !_legendExpanded),
          child: Row(
            children: [
              Text(
                LocaleService.current.moods,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: widget.theme.textSecondary,
                ),
              ),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: _legendExpanded ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: widget.theme.textMuted,
                ),
              ),
            ],
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: MoodOption.all.map((m) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: m.color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 4),
                    if (m.imagePath.isNotEmpty)
                      MoodImage(m.imagePath, width: 22, height: 22),
                    const SizedBox(width: 4),
                    Text(
                      m.localizedLabel,
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.theme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
          crossFadeState: _legendExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 250),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════
  //  СЕКЦИЯ КАЛЕНДАРЯ (карточка-сетка + статистика)
  // ═══════════════════════════════════════════

  Widget _buildCalendarSection({
    required ColorScheme scheme,
    required String label,
    required List<MoodEntry> entries,
    required Map<String, int> stats,
    bool isPartner = false,
    String ownerName = '',
  }) {
    final byDay = <String, List<MoodEntry>>{};
    for (final e in entries) {
      byDay.putIfAbsent(e.dayKey, () => []).add(e);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Карточка-сетка в духе ScoreMaster
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Unbounded',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
        fontVariations: const [FontVariation('wght', 700)],
                  letterSpacing: -0.2,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.04),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey(
                      '${_calMode.name}-${_calAnchor.toIso8601String()}-$isPartner'),
                  child: _buildGrid(byDay, scheme, isPartner: isPartner),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (stats.isNotEmpty)
          MoodRingStats(counts: stats, scheme: Theme.of(context).colorScheme),
        const SizedBox(height: 16),
        if (entries.isNotEmpty) _buildAnalytics(scheme, entries),
        if (!isPartner && CycleService.unlockedFor(widget.userData))
          _buildCycleBlock(scheme),
        // Цикл партнёрши: только когда она делится отметками и их хватило на
        // прогноз. Ни своего пола, ни своей подписки тут не спрашиваем — цикл
        // читают, а не ведут, и заплатила за него та, чей это календарь.
        if (isPartner && CycleService.partnerCycleVisible(_cycle.partner))
          _buildCycleBlock(scheme, partner: true, ownerName: ownerName),
      ],
    );
  }

  // ═══════════════════════════════════════════
  //  ЦИКЛ: прогноз, средние и графики
  // ═══════════════════════════════════════════

  /// Сворачиваемый блок под календарём: то, что раньше жило отдельным экраном
  /// в настройках. Отметки ставятся в самом календаре, поэтому здесь только
  /// цифры — прогноз, средние длины и графики.
  /// [partner] — блок считается по отметкам партнёрши, которые она разрешила
  /// показывать. Арифметика та же: источник отметок ей безразличен.
  Widget _buildCycleBlock(
    ColorScheme scheme, {
    bool partner = false,
    String ownerName = '',
  }) {
    final s = LocaleService.current;
    // Цвет метки и состояние «развёрнут» у каждого календаря свои: блоков на
    // экране два, и общий флаг раскрывал их парой.
    final accent = _periodColorOf(scheme, partner: partner);
    final expanded = partner ? _partnerCycleExpanded : _myCycleExpanded;
    final periodDays = (partner ? _cycle.partner : _cycle.mine)
        .where((e) => e.kind == CycleKind.period)
        .map((e) => e.day)
        .toList();
    final forecast = CycleMath.predict(periodDays);
    final dayOfCycle = CycleMath.dayOfCycle(periodDays);
    final cycleLen = CycleMath.averageCycleLength(periodDays);
    final periodLen = CycleMath.averagePeriodLength(periodDays);

    String headline;
    String? note;
    if (forecast == null) {
      headline = s.cycleNoDataTitle;
      note = s.cycleNoDataHint;
    } else if (forecast.overdueDays > 0) {
      headline = s.cycleOverdue(forecast.overdueDays);
      note = s.cycleOverdueHint;
    } else {
      final now = DateTime.now();
      final left = forecast.nextPeriod
          .difference(DateTime(now.year, now.month, now.day))
          .inDays;
      headline = left <= 0 ? s.cycleExpectedToday : s.cycleDaysLeft(left);
      note = dayOfCycle == null ? null : s.cycleDayOfCycle(dayOfCycle);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                if (partner) {
                  _partnerCycleExpanded = !_partnerCycleExpanded;
                } else {
                  _myCycleExpanded = !_myCycleExpanded;
                }
              });
            },
            child: Row(
              children: [
                Icon(Icons.water_drop_rounded, size: 18, color: accent),
                const SizedBox(width: 8),
                Text(
                  partner && ownerName.isNotEmpty
                      ? s.cycleOf(ownerName)
                      : s.cycleTitle,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: widget.theme.textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    dayOfCycle == null ? '' : s.cycleDayOfCycle(dayOfCycle),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: widget.theme.textMuted,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: widget.theme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          headline,
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                        if (note != null) ...[
                          const SizedBox(height: 5),
                          Text(
                            note,
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onPrimaryContainer
                                  .withValues(alpha: 0.75),
                            ),
                          ),
                        ],
                        if (forecast != null && forecast.irregular) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(Icons.info_rounded,
                                  size: 15, color: scheme.onPrimaryContainer),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  s.cycleIrregularWarning,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onPrimaryContainer
                                        .withValues(alpha: 0.9),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (cycleLen != null || periodLen != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (cycleLen != null)
                          Expanded(
                            child: _statTile(scheme, s.cycleDaysValue(cycleLen),
                                s.cycleAverageLength),
                          ),
                        if (cycleLen != null && periodLen != null)
                          const SizedBox(width: 10),
                        if (periodLen != null)
                          Expanded(
                            child: _statTile(scheme,
                                s.cycleDaysValue(periodLen), s.cycleAveragePeriod),
                          ),
                      ],
                    ),
                  ],
                  if (forecast != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _statTile(
                            scheme,
                            _shortDate(forecast.nextPeriod),
                            s.cycleNextPeriod,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _statTile(
                            scheme,
                            '${_shortDate(forecast.fertileFrom)} — '
                            '${_shortDate(forecast.fertileTo)}',
                            s.cycleFertileWindow,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  // Советы стоят сразу после прогноза, до статистики: в дни
                  // месячных нужны они, а средняя длина цикла подождёт.
                  CycleTipsStrip(scheme: scheme, accent: accent),
                  const SizedBox(height: 12),
                  CycleAnalytics(
                    scheme: scheme,
                    periodDays: periodDays,
                    periodColor: accent,
                  ),
                  const SizedBox(height: 12),
                  _cycleLegend(scheme, accent),
                ],
              ),
            ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  /// Что значат метки на клетках. Переехала сюда с отдельного экрана цикла —
  /// он удалён, а календарь остался один, и объяснять цвета всё равно надо.
  ///
  /// В списке только то, что календарь РИСУЕТ: закрашенный день с точкой,
  /// обводка ожидаемых и точка близости. Овуляции и фертильных дней тут нет —
  /// они живут в карточках прогноза выше, и рисовать их в легенде значило бы
  /// обещать метки, которых на клетках не существует.
  Widget _cycleLegend(ColorScheme scheme, Color accent) {
    final s = LocaleService.current;
    return Wrap(
      spacing: 14,
      runSpacing: 8,
      children: [
        _legendItem(scheme, s.cycleLegendPeriod, fill: accent),
        _legendItem(scheme, s.cycleLegendPredicted, outline: accent),
        _legendItem(scheme, s.cycleLegendIntimacy, fill: scheme.primary),
      ],
    );
  }

  Widget _legendItem(
    ColorScheme scheme,
    String label, {
    Color? fill,
    Color? outline,
  }) =>
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fill,
              border: outline == null
                  ? null
                  : Border.all(color: outline.withValues(alpha: 0.75), width: 1.5),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 12.5, color: widget.theme.textSecondary),
          ),
        ],
      );

  String _shortDate(DateTime d) =>
      '${d.day} ${LocaleService.current.cycleMonthsGenitive[d.month - 1]}';

  // ═══════════════════════════════════════════
  //  СЕТКА
  // ═══════════════════════════════════════════

  Widget _buildGrid(
    Map<String, List<MoodEntry>> byDay,
    ColorScheme scheme, {
    bool isPartner = false,
  }) {
    switch (_calMode) {
      case _CalMode.week:
        return _weekGrid(byDay, scheme, isPartner: isPartner);
      case _CalMode.month:
        return _monthGrid(byDay, scheme, isPartner: isPartner);
      case _CalMode.year:
        return _yearGrid(byDay, scheme);
    }
  }

  Widget _weekHeader(ColorScheme scheme) {
    final names = LocaleService.current.shortWeekdays; // Пн..Вс
    return Row(
      children: [
        for (final d in names)
          Expanded(
            child: Center(
              child: Text(
                d,
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
        fontVariations: const [FontVariation('wght', 700)],
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Ячейка дня: тональный контейнер с числом; день с настроением залит мягким
  /// цветом эмоции и показывает эмодзи; сегодня обведён.
  Widget _moodDayCell(
    DateTime day,
    Map<String, List<MoodEntry>> byDay,
    ColorScheme scheme, {
    required bool isPartner,
    double numberSize = 12,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final key = _dayKey(day);
    final moods = byDay[key] ?? const [];
    final hasMood = moods.isNotEmpty;
    final isToday = _dayKey(now) == key;
    final isFuture = day.isAfter(today);

    final latest = hasMood
        ? moods.reduce((a, b) => a.timestamp.isAfter(b.timestamp) ? a : b)
        : null;

    // Отметки цикла: свои в своей сетке, партнёрские — в партнёрской, и только
    // те, что она разрешила показывать (лишнее отсекает сервер).
    final cycleEntries = isPartner ? _cycle.partner : _cycle.mine;
    final hasPeriod = cycleEntries
        .any((e) => e.kind == CycleKind.period && e.day == day);
    final hasSex = cycleEntries
        .any((e) => e.kind == CycleKind.intimacy && e.day == day);
    // Ожидаемые дни считаем от той же сетки, что рисуем: расчёт не спрашивает,
    // чьи отметки ему дали. Раньше прогноз был только своим, и в паре из двух
    // девушек каждая видела у второй голый календарь без ожидаемых дней.
    final expectsPeriod = !hasPeriod &&
        CycleService.phaseOf(cycleEntries, day) == CyclePhase.predictedPeriod;

    var bg = hasMood
        ? Color.alphaBlend(
            latest!.color.withValues(alpha: 0.22), scheme.surfaceContainerHighest)
        : scheme.surfaceContainerHighest;
    final periodColor = _periodColorOf(scheme, partner: isPartner);
    if (hasPeriod) {
      bg = Color.alphaBlend(periodColor.withValues(alpha: 0.16), bg);
    }

    return GestureDetector(
      onTap: () {
        if (isPartner) {
          if (hasMood) _showDayDetail(day, moods, isPartner: true);
          return;
        }
        if (isFuture) return;
        _showDayLog(day);
      },
      onLongPress: hasMood
          ? () => _showDayDetail(day, moods, isPartner: isPartner)
          : null,
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: isFuture && !hasMood ? bg.withValues(alpha: 0.5) : bg,
            borderRadius: BorderRadius.circular(14),
            border: isToday
                ? Border.all(color: scheme.primary, width: 2)
                // Ожидаемые месячные — пунктирный по смыслу контур: прогноз,
                // а не факт, поэтому он тоньше и полупрозрачный.
                : (expectsPeriod
                    ? Border.all(
                        color: periodColor.withValues(alpha: 0.55), width: 1.5)
                    : null),
          ),
          padding: const EdgeInsets.all(3),
          child: Stack(
            alignment: Alignment.center,
            children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${day.day}',
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: numberSize,
                  fontWeight: hasMood || isToday
                      ? FontWeight.w800
                      : FontWeight.w500,
                  color: isToday && !hasMood
                      ? scheme.primary
                      : (isFuture
                          ? scheme.onSurfaceVariant.withValues(alpha: 0.5)
                          : scheme.onSurface),
                ),
              ),
              if (hasMood && latest!.imagePath.isNotEmpty)
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 1,
                      // Круглая маска: классические эмодзи — квадратные плитки с
                      // цветным фоном; в круге они выглядят так же округло, как
                      // прозрачные стикеры розового пака (cover заполняет круг).
                      child: ClipOval(
                        child: MoodImage(latest.imagePath, fit: BoxFit.cover),
                      ),
                    ),
                  ),
                ),
            ],
          ),
              // Точки цикла у края клетки: настроение занимает середину, поэтому
              // отметки живут отдельным слоем и не сжимают его. Свои прижаты
              // книзу, партнёрские кверху — владельца видно и на чёрно-белом
              // снимке экрана, и при цветовой слепоте, когда один цвет не
              // спасает.
              if (hasPeriod || hasSex)
                Align(
                  alignment:
                      isPartner ? Alignment.topCenter : Alignment.bottomCenter,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasPeriod) _cycleDot(periodColor),
                      if (hasPeriod && hasSex) const SizedBox(width: 3),
                      if (hasSex) _cycleDot(scheme.primary),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Цвет отметок цикла. Календарей на экране два, поэтому метка обязана
  /// называть владельца сама: свои дни красные, партнёрские сливовые.
  Color _periodColorOf(ColorScheme scheme, {required bool partner}) =>
      CycleColors.period(scheme.brightness, partner: partner);

  Widget _cycleDot(Color color) => Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );

  Widget _weekGrid(
    Map<String, List<MoodEntry>> byDay,
    ColorScheme scheme, {
    bool isPartner = false,
  }) {
    final monday =
        _calAnchor.subtract(Duration(days: _calAnchor.weekday - 1));
    final days = [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))];
    return Column(
      children: [
        _weekHeader(scheme),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final d in days)
              Expanded(
                child: _moodDayCell(d, byDay, scheme,
                    isPartner: isPartner, numberSize: 13),
              ),
          ],
        ),
      ],
    );
  }

  Widget _monthGrid(
    Map<String, List<MoodEntry>> byDay,
    ColorScheme scheme, {
    bool isPartner = false,
  }) {
    final first = DateTime(_calAnchor.year, _calAnchor.month, 1);
    final daysInMonth =
        DateTime(_calAnchor.year, _calAnchor.month + 1, 0).day;
    final leadBlanks = first.weekday - 1; // понедельник = 0

    final cells = <Widget>[];
    for (var i = 0; i < leadBlanks; i++) {
      cells.add(const Expanded(child: SizedBox.shrink()));
    }
    for (var d = 1; d <= daysInMonth; d++) {
      final day = DateTime(_calAnchor.year, _calAnchor.month, d);
      cells.add(Expanded(
        child: _moodDayCell(day, byDay, scheme, isPartner: isPartner),
      ));
    }
    while (cells.length % 7 != 0) {
      cells.add(const Expanded(child: SizedBox.shrink()));
    }
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 7) {
      rows.add(Row(children: cells.sublist(i, i + 7)));
    }
    return Column(
      children: [
        _weekHeader(scheme),
        const SizedBox(height: 6),
        ...rows,
      ],
    );
  }

  Widget _yearGrid(Map<String, List<MoodEntry>> byDay, ColorScheme scheme) {
    // Число дней с настроением по месяцам года.
    final counts = List<int>.filled(12, 0);
    byDay.forEach((k, list) {
      final d = DateTime.tryParse(k);
      if (d != null && d.year == _calAnchor.year && list.isNotEmpty) {
        counts[d.month - 1]++;
      }
    });
    final maxCount = counts.fold<int>(1, (a, b) => math.max(a, b));
    final short = LocaleService.current.shortMonths;

    Widget monthCell(int m) {
      final count = counts[m];
      final has = count > 0;
      final t = maxCount <= 1 ? 1.0 : (count / maxCount).clamp(0.0, 1.0);
      final color = has
          ? Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.12 + 0.22 * t),
              scheme.surfaceContainerHighest)
          : scheme.surfaceContainerHighest;
      return GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() {
            _calMode = _CalMode.month;
            _calAnchor = DateTime(_calAnchor.year, m + 1, 1);
          });
        },
        child: Container(
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Text(
                short[m],
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
        fontVariations: const [FontVariation('wght', 700)],
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$count',
                style: TextStyle(
                  fontFamily: 'Unbounded',
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
        fontVariations: const [FontVariation('wght', 800)],
                  color: has
                      ? scheme.primary
                      : scheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final rows = <Widget>[];
    for (var r = 0; r < 4; r++) {
      rows.add(Row(
        children: [
          for (var c = 0; c < 3; c++) Expanded(child: monthCell(r * 3 + c)),
        ],
      ));
    }
    return Column(children: rows);
  }

  // ═══════════════════════════════════════════
  //  АНАЛИТИКА (тренд и среднее)
  // ═══════════════════════════════════════════

  Widget _buildAnalytics(ColorScheme scheme, List<MoodEntry> entries) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final ru = LocaleService.instance.isRussian;

    final byDay = <DateTime, List<MoodEntry>>{};
    for (final e in entries) {
      final d = DateTime(e.timestamp.year, e.timestamp.month, e.timestamp.day);
      byDay.putIfAbsent(d, () => []).add(e);
    }

    final sortedDays = byDay.keys.toList()..sort();

    double totalScore = 0;
    for (final e in entries) {
      totalScore += e.score;
    }
    final avgScore = (totalScore / entries.length).toStringAsFixed(1);

    // Самое частое настроение — для плитки статистики.
    final moodCounts = <String, int>{};
    for (final e in entries) {
      moodCounts[e.moodId] = (moodCounts[e.moodId] ?? 0) + 1;
    }
    String? topMoodId;
    var topN = 0;
    moodCounts.forEach((k, v) {
      if (v > topN) {
        topN = v;
        topMoodId = k;
      }
    });
    final topMood = topMoodId != null ? MoodOption.byId(topMoodId!) : null;

    final spots = <FlSpot>[];
    for (int i = 0; i < sortedDays.length; i++) {
      final day = sortedDays[i];
      final dayEntries = byDay[day]!;
      final dayAvg =
          dayEntries.map((e) => e.score).reduce((a, b) => a + b) /
              dayEntries.length;
      spots.add(FlSpot(i.toDouble(), dayAvg));
    }

    final labelInterval = (sortedDays.length / 6).ceil().toDouble();

    String avgText;
    final numAvg = totalScore / entries.length;
    if (numAvg >= 4.5) {
      avgText = LocaleService.current.great;
    } else if (numAvg >= 3.5) {
      avgText = LocaleService.current.good;
    } else if (numAvg >= 2.5) {
      avgText = LocaleService.current.okay;
    } else if (numAvg >= 1.5) {
      avgText = LocaleService.current.bad;
    } else {
      avgText = LocaleService.current.awful;
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  LocaleService.current.averageMood,
                  style: TextStyle(
                    fontFamily: 'Unbounded',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
        fontVariations: const [FontVariation('wght', 700)],
                    letterSpacing: -0.2,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$avgScore · $avgText',
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
        fontVariations: const [FontVariation('wght', 800)],
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // ── Плитки статистики (Material You) ──
          Row(
            children: [
              Expanded(
                  child: _statTile(
                      scheme, '${entries.length}', ru ? 'Записей' : 'Entries')),
              const SizedBox(width: 8),
              Expanded(
                  child: _statTile(scheme, '${byDay.length}',
                      ru ? 'Дней отмечено' : 'Days tracked')),
              const SizedBox(width: 8),
              Expanded(
                  child: _moodStatTile(
                      scheme, topMood, ru ? 'Чаще всего' : 'Most often')),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 128,
            child: sortedDays.length > 1
                ? LineChart(
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeInOutExpo,
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 1,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: scheme.outlineVariant,
                          strokeWidth: 1,
                          dashArray: [5, 6],
                        ),
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 22,
                            interval: 1,
                            getTitlesWidget: (value, meta) {
                              if (value == 1 || value == 3 || value == 5) {
                                return Text(
                                  value.toInt().toString(),
                                  style: TextStyle(
                                    fontFamily: 'Onest',
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
        fontVariations: const [FontVariation('wght', 600)],
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 22,
                            interval: labelInterval,
                            getTitlesWidget: (value, meta) {
                              final idx = value.round();
                              if (idx >= 0 &&
                                  idx < sortedDays.length &&
                                  (value - idx).abs() < 0.01 &&
                                  idx % labelInterval.toInt() == 0) {
                                final date = sortedDays[idx];
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    '${date.day}/${date.month}',
                                    style: TextStyle(
                                      fontFamily: 'Onest',
                                      color: scheme.onSurfaceVariant,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
        fontVariations: const [FontVariation('wght', 600)],
                                    ),
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      minX: 0,
                      maxX: (sortedDays.length - 1).toDouble(),
                      minY: 1,
                      maxY: 5,
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          color: scheme.primary,
                          barWidth: 3.5,
                          isStrokeCapRound: true,
                          dotData: FlDotData(
                            show: true,
                            getDotPainter: (spot, percent, barData, index) =>
                                FlDotCirclePainter(
                              radius: 4,
                              color: scheme.surface,
                              strokeWidth: 2.5,
                              strokeColor: scheme.primary,
                            ),
                          ),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                scheme.primary.withValues(alpha: 0.22),
                                scheme.primary.withValues(alpha: 0.02),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : Center(
                    child: Text(
                      LocaleService.current.notEnoughData,
                      style: TextStyle(
                        fontFamily: 'Onest',
        fontVariations: const [FontVariation('wght', 400)],
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// Компактная M3-плитка статистики: крупное число + подпись.
  Widget _statTile(ColorScheme scheme, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Unbounded',
              fontSize: 18,
              fontWeight: FontWeight.w800,
        fontVariations: const [FontVariation('wght', 800)],
              letterSpacing: -0.4,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            style: TextStyle(
              fontFamily: 'Onest',
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
        fontVariations: const [FontVariation('wght', 600)],
              height: 1.1,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Плитка «частое настроение»: круглая эмодзи вместо числа.
  Widget _moodStatTile(ColorScheme scheme, MoodOption? mood, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 26,
            width: 26,
            child: mood != null && mood.imagePath.isNotEmpty
                ? ClipOval(
                    child: MoodImage(mood.imagePath, fit: BoxFit.cover),
                  )
                : Icon(Icons.mood_rounded, size: 22, color: scheme.primary),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 2,
            style: TextStyle(
              fontFamily: 'Onest',
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
        fontVariations: const [FontVariation('wght', 600)],
              height: 1.1,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  ПИКЕР НАСТРОЕНИЯ ДНЯ
  // ═══════════════════════════════════════════

  /// Лист дня: настроение, самочувствие и цикл в одном месте.
  void _showDayLog(DateTime day) {
    showDayLogSheet(
      context: context,
      day: DateTime(day.year, day.month, day.day),
      pairData: _pair,
      moodService: _mood,
      widgetService: _ws,
      theme: widget.theme,
      userData: widget.userData,
    );
  }

  // ═══════════════════════════════════════════
  //  ДЕТАЛИ ДНЯ
  // ═══════════════════════════════════════════

  void _showDayDetail(
    DateTime day,
    List<MoodEntry> moods, {
    bool isPartner = false,
  }) {
    final dayStr =
        '${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}.${day.year}';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: widget.theme.cardSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: widget.theme.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                dayStr,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: widget.theme.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              if (moods.isEmpty)
                Text(
                  LocaleService.current.noMoodRecorded,
                  style: TextStyle(fontSize: 14, color: widget.theme.textMuted),
                )
              else
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: moods
                          .map(
                            (m) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: m.imagePath.isNotEmpty
                                        ? MoodImage(
                                            m.imagePath,
                                            width: 48,
                                            height: 48,
                                            fit: BoxFit.cover,
                                          )
                                        : Container(
                                            width: 48,
                                            height: 48,
                                            color: m.color,
                                          ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      m.localizedLabel,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: widget.theme.textPrimary,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${m.timestamp.hour.toString().padLeft(2, '0')}:${m.timestamp.minute.toString().padLeft(2, '0')}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: widget.theme.textMuted,
                                    ),
                                  ),
                                  if (!isPartner) ...[
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () {
                                        _mood.deleteMoodEntry(m.id);
                                        Navigator.pop(context);
                                      },
                                      child: Icon(
                                        Icons.delete_outline_rounded,
                                        size: 18,
                                        color: widget.theme.textMuted,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Хелперы ──

  String _dayKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }
}
