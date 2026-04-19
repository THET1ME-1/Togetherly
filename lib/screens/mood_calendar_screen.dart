import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/mood_entry.dart';
import '../models/pair_data.dart';
import '../services/locale_service.dart';
import '../services/mood_service.dart';
import '../services/widget_service.dart';
import '../theme/app_theme.dart';

/// Экран «Mood Calendar»
/// Верхняя часть — мой календарь, нижняя — календарь партнёра.
/// Каждый день — квадрат, разделённый на цвета настроений.
class MoodCalendarScreen extends StatefulWidget {
  final PairData pairData;
  final MoodService moodService;
  final WidgetService widgetService;

  final AppTheme theme;

  const MoodCalendarScreen({
    super.key,
    required this.pairData,
    required this.moodService,
    required this.widgetService,
    required this.theme,
  });

  @override
  State<MoodCalendarScreen> createState() => _MoodCalendarScreenState();
}

class _MoodCalendarScreenState extends State<MoodCalendarScreen> {
  int _selectedPeriod = 1; // 0=Week, 1=Month, 2=Year
  late DateTime _currentMonth;
  double _calendarScale = 1.0;
  double _baseScale = 1.0;
  bool _legendExpanded = false;

  MoodService get _mood => widget.moodService;
  PairData get _pair => widget.pairData;
  WidgetService get _ws => widget.widgetService;

  @override
  void initState() {
    super.initState();
    _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
    _mood.addListener(_onChanged);

    // Subscribe to partner moods
    for (final p in _pair.partners) {
      _mood.listenToPartner(p.uid);
    }
  }

  @override
  void dispose() {
    _mood.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  // ── Period helpers ──

  DateTime get _periodStart {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case 0: // Week
        final weekDay = now.weekday; // 1=Mon
        return DateTime(now.year, now.month, now.day - weekDay + 1);
      case 1: // Month
        return DateTime(_currentMonth.year, _currentMonth.month);
      case 2: // Year
        return DateTime(now.year);
      default:
        return DateTime(now.year, now.month);
    }
  }

  DateTime get _periodEnd {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case 0:
        return _periodStart.add(const Duration(days: 6));
      case 1:
        return DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
      case 2:
        return DateTime(now.year, 12, 31);
      default:
        return DateTime(now.year, now.month + 1, 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── AppBar ──
          SliverAppBar(
            pinned: true,
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              LocaleService.current.moodCalendarTitle,
              style: GoogleFonts.rubik(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade900,
              ),
            ),
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.zoom_out_rounded, size: 22),
                onPressed: _calendarScale > 0.7
                    ? () => setState(
                        () => _calendarScale = (_calendarScale - 0.15).clamp(
                          0.7,
                          1.5,
                        ),
                      )
                    : null,
                tooltip: LocaleService.current.zoomOut,
              ),
              IconButton(
                icon: const Icon(Icons.zoom_in_rounded, size: 22),
                onPressed: _calendarScale < 1.5
                    ? () => setState(
                        () => _calendarScale = (_calendarScale + 0.15).clamp(
                          0.7,
                          1.5,
                        ),
                      )
                    : null,
                tooltip: LocaleService.current.zoomIn,
              ),
            ],
          ),

          // ── Period toggle ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: _buildPeriodToggle(),
            ),
          ),

          // ── Month navigation (for month view) ──
          if (_selectedPeriod == 1)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: _buildMonthNav(),
              ),
            ),

          // ── Legend ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: _buildLegend(),
            ),
          ),

          // ── My calendar ──
          SliverToBoxAdapter(
            child: GestureDetector(
              onScaleStart: (_) {
                _baseScale = _calendarScale;
              },
              onScaleUpdate: (details) {
                setState(() {
                  _calendarScale = (_baseScale * details.scale).clamp(0.7, 1.5);
                });
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Transform.scale(
                  scale: _calendarScale,
                  alignment: Alignment.topCenter,
                  child: _buildCalendarSection(
                    label: LocaleService.current.myMood,
                    entries: _mood.myEntries,
                    stats: _mood.myStats(from: _periodStart, to: _periodEnd),
                  ),
                ),
              ),
            ),
          ),

          // ── Partner calendars ──
          ..._pair.partners.map(
            (p) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Transform.scale(
                  scale: _calendarScale,
                  alignment: Alignment.topCenter,
                  child: _buildCalendarSection(
                    label: LocaleService.current.partnerMood(p.name),
                    entries: _mood.partnerEntries(p.uid),
                    stats: _mood.partnerStats(
                      p.uid,
                      from: _periodStart,
                      to: _periodEnd,
                    ),
                    isPartner: true,
                  ),
                ),
              ),
            ),
          ),

          // ── Bottom spacing ──
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  PERIOD TOGGLE
  // ═══════════════════════════════════════════

  Widget _buildPeriodToggle() {
    final labels = [
      LocaleService.current.week,
      LocaleService.current.month,
      LocaleService.current.year,
    ];
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: List.generate(
          3,
          (i) => Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedPeriod = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: _selectedPeriod == i
                      ? Colors.white
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _selectedPeriod == i
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 8,
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: _selectedPeriod == i
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: _selectedPeriod == i
                          ? widget.theme.primary
                          : Colors.grey.shade500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  MONTH NAVIGATION
  // ═══════════════════════════════════════════

  Widget _buildMonthNav() {
    final months = LocaleService.current.fullMonths;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: () {
            setState(() {
              _currentMonth = DateTime(
                _currentMonth.year,
                _currentMonth.month - 1,
              );
            });
          },
        ),
        Text(
          '${months[_currentMonth.month - 1]} ${_currentMonth.year}',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade800,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: () {
            setState(() {
              _currentMonth = DateTime(
                _currentMonth.year,
                _currentMonth.month + 1,
              );
            });
          },
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════
  //  LEGEND
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
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: _legendExpanded ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: Colors.grey.shade500,
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
                      Image.asset(
                        m.imagePath,
                        width: 22,
                        height: 22,
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox(width: 22, height: 22),
                      ),
                    const SizedBox(width: 4),
                    Text(
                      m.localizedLabel,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
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
  //  CALENDAR SECTION (grid + stats)
  // ═══════════════════════════════════════════

  Widget _buildCalendarSection({
    required String label,
    required List<MoodEntry> entries,
    required Map<String, int> stats,
    bool isPartner = false,
  }) {
    // Group entries by day
    final byDay = <String, List<MoodEntry>>{};
    for (final e in entries) {
      byDay.putIfAbsent(e.dayKey, () => []).add(e);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Colors.grey.shade800,
          ),
        ),
        const SizedBox(height: 12),

        // Calendar grid
        _buildGrid(byDay, isPartner: isPartner),

        const SizedBox(height: 16),

        // Stats bar
        if (stats.isNotEmpty) _buildStatsBar(stats),

        const SizedBox(height: 16),

        // Analytics (trend & average)
        if (entries.isNotEmpty) _buildAnalytics(entries),
      ],
    );
  }

  // ═══════════════════════════════════════════
  //  GRID
  // ═══════════════════════════════════════════

  Widget _buildGrid(
    Map<String, List<MoodEntry>> byDay, {
    bool isPartner = false,
  }) {
    switch (_selectedPeriod) {
      case 0:
        return _buildWeekGrid(byDay, isPartner: isPartner);
      case 1:
        return _buildMonthGrid(byDay, isPartner: isPartner);
      case 2:
        return _buildYearGrid(byDay);
      default:
        return _buildMonthGrid(byDay, isPartner: isPartner);
    }
  }

  Widget _buildWeekGrid(
    Map<String, List<MoodEntry>> byDay, {
    bool isPartner = false,
  }) {
    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day - now.weekday + 1);
    final dayNames = LocaleService.current.shortWeekdays;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: List.generate(7, (i) {
        final day = weekStart.add(Duration(days: i));
        final key = _dayKey(day);
        final moods = byDay[key] ?? [];
        final isToday = _dayKey(now) == key;

        return Column(
          children: [
            Text(
              dayNames[i],
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                color: isToday ? widget.theme.primary : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 4),
            GestureDetector(
              onTap:
                  isPartner ||
                      day.isAfter(DateTime(now.year, now.month, now.day))
                  ? null
                  : () => _showMoodPickerForDay(day),
              onLongPress: moods.isNotEmpty
                  ? () => _showDayDetail(day, moods, isPartner: isPartner)
                  : null,
              child: _moodSquare(moods, size: 40, isToday: isToday),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildMonthGrid(
    Map<String, List<MoodEntry>> byDay, {
    bool isPartner = false,
  }) {
    final first = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final daysInMonth = DateTime(
      _currentMonth.year,
      _currentMonth.month + 1,
      0,
    ).day;
    final startWeekday = first.weekday; // 1=Mon
    final now = DateTime.now();

    final dayNames = LocaleService.current.shortWeekdaysSingleChar;

    return Column(
      children: [
        // Day names header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: dayNames
              .map(
                (d) => SizedBox(
                  width: 36,
                  child: Center(
                    child: Text(
                      d,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 6),
        // Grid
        ...List.generate(((startWeekday - 1 + daysInMonth) / 7).ceil(), (week) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(7, (dayOfWeek) {
                final dayNum = week * 7 + dayOfWeek - (startWeekday - 2);
                if (dayNum < 1 || dayNum > daysInMonth) {
                  return const SizedBox(width: 36, height: 36);
                }
                final day = DateTime(
                  _currentMonth.year,
                  _currentMonth.month,
                  dayNum,
                );
                final key = _dayKey(day);
                final moods = byDay[key] ?? [];
                final isToday = _dayKey(now) == key;

                return GestureDetector(
                  onTap:
                      isPartner ||
                          day.isAfter(DateTime(now.year, now.month, now.day))
                      ? null
                      : () => _showMoodPickerForDay(day),
                  onLongPress: moods.isNotEmpty
                      ? () => _showDayDetail(day, moods, isPartner: isPartner)
                      : null,
                  child: _moodSquare(moods, size: 36, isToday: isToday),
                );
              }),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildYearGrid(Map<String, List<MoodEntry>> byDay) {
    final year = DateTime.now().year;
    final now = DateTime.now();

    return Column(
      children: List.generate(12, (month) {
        final daysInMonth = DateTime(year, month + 2, 0).day;
        final months = LocaleService.current.shortMonths;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                months[month],
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade500,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 2,
                runSpacing: 2,
                children: List.generate(daysInMonth, (d) {
                  final day = DateTime(year, month + 1, d + 1);
                  final key = _dayKey(day);
                  final moods = byDay[key] ?? [];
                  final isToday = _dayKey(now) == key;
                  return _moodSquare(moods, size: 14, isToday: isToday);
                }),
              ),
            ],
          ),
        );
      }),
    );
  }

  // ═══════════════════════════════════════════
  //  MOOD SQUARE
  // ═══════════════════════════════════════════

  Widget _moodSquare(
    List<MoodEntry> moods, {
    required double size,
    bool isToday = false,
  }) {
    if (moods.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(size > 20 ? 4 : 2),
          border: isToday
              ? Border.all(color: widget.theme.primary, width: 2)
              : null,
        ),
      );
    }

    return _CyclingMoodSquare(
      moods: moods,
      size: size,
      isToday: isToday,
      primary: widget.theme.primary,
    );
  }

  // ═══════════════════════════════════════════
  //  STATS BAR
  // ═══════════════════════════════════════════

  Widget _buildStatsBar(Map<String, int> stats) {
    final total = stats.values.fold(0, (a, b) => a + b);
    if (total == 0) return const SizedBox.shrink();

    // Sort by count descending
    final sorted = stats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Bar
        Container(
          height: 24,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: sorted.map((e) {
              final mood = MoodOption.byId(e.key);
              final fraction = e.value / total;
              return Expanded(
                flex: (fraction * 1000).round(),
                child: Container(color: mood?.color ?? Colors.grey),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 10),
        // Labels
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: sorted.map((e) {
            final mood = MoodOption.byId(e.key);
            final pct = ((e.value / total) * 100).round();
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: mood?.color ?? Colors.grey,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 4),
                if (mood != null)
                  if (mood.imagePath.isNotEmpty)
                    Image.asset(
                      mood.imagePath,
                      width: 20,
                      height: 20,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox(width: 20, height: 20),
                    ),
                const SizedBox(width: 4),
                Text(
                  '$pct%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════
  //  ANALYTICS (TREND & AVERAGE)
  // ═══════════════════════════════════════════

  Widget _buildAnalytics(List<MoodEntry> entries) {
    if (entries.isEmpty) return const SizedBox.shrink();

    // 1. Group by day and calculate average score per day
    final byDay = <DateTime, List<MoodEntry>>{};
    for (final e in entries) {
      final d = DateTime(e.timestamp.year, e.timestamp.month, e.timestamp.day);
      byDay.putIfAbsent(d, () => []).add(e);
    }

    final sortedDays = byDay.keys.toList()..sort();

    // Overall average
    double totalScore = 0;
    for (final e in entries) {
      totalScore += e.score;
    }
    final avgScore = (totalScore / entries.length).toStringAsFixed(1);

    // Chart data
    final spots = <FlSpot>[];
    for (int i = 0; i < sortedDays.length; i++) {
      final day = sortedDays[i];
      final dayEntries = byDay[day]!;
      final dayAvg =
          dayEntries.map((e) => e.score).reduce((a, b) => a + b) /
          dayEntries.length;
      spots.add(FlSpot(i.toDouble(), dayAvg));
    }

    // Determine the text equivalent for the average score
    String avgText = '';
    final numAvg = totalScore / entries.length;
    if (numAvg >= 4.5)
      avgText = LocaleService.current.great;
    else if (numAvg >= 3.5)
      avgText = LocaleService.current.good;
    else if (numAvg >= 2.5)
      avgText = LocaleService.current.okay;
    else if (numAvg >= 1.5)
      avgText = LocaleService.current.bad;
    else
      avgText = LocaleService.current.awful;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                LocaleService.current.averageMood,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: widget.theme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$avgScore ($avgText)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: widget.theme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 120,
            child: sortedDays.length > 1
                ? LineChart(
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeInOutExpo,
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 1,
                        getDrawingHorizontalLine: (value) {
                          return FlLine(
                            color: Colors.grey.shade200,
                            strokeWidth: 1,
                            dashArray: [5, 5],
                          );
                        },
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
                            reservedSize: 24,
                            interval: 1,
                            getTitlesWidget: (value, meta) {
                              if (value == 1 || value == 3 || value == 5) {
                                return Text(
                                  value.toInt().toString(),
                                  style: TextStyle(
                                    color: Colors.grey.shade400,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
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
                            interval: 1,
                            getTitlesWidget: (value, meta) {
                              if (value.toInt() >= 0 &&
                                  value.toInt() < sortedDays.length) {
                                final date = sortedDays[value.toInt()];
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    '${date.day}/${date.month}',
                                    style: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
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
                          color: widget.theme.primary,
                          barWidth: 3,
                          isStrokeCapRound: true,
                          dotData: FlDotData(
                            show: true,
                            getDotPainter: (spot, percent, barData, index) =>
                                FlDotCirclePainter(
                                  radius: 4,
                                  color: Colors.white,
                                  strokeWidth: 2,
                                  strokeColor: widget.theme.primary,
                                ),
                          ),
                          belowBarData: BarAreaData(
                            show: true,
                            color: widget.theme.primary.withOpacity(0.1),
                          ),
                        ),
                      ],
                    ),
                  )
                : Center(
                    child: Text(
                      LocaleService.current.notEnoughData,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  MOOD PICKER FOR DAY
  // ═══════════════════════════════════════════

  void _showMoodPickerForDay(DateTime day) {
    final dayStr =
        '${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}.${day.year}';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (ctx, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                dayStr,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                LocaleService.current.howAreYouFeeling,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade900,
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: GridView.count(
                  controller: scrollController,
                  crossAxisCount: 5,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.75,
                  children: MoodOption.all.map((m) {
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        _mood.addMood(
                          moodId: m.id,
                          imagePath: m.imagePath,
                          label: m.localizedLabel,
                          date: day,
                        );
                        // Синхронизуем live-настроение если выбран сегодняшний день
                        final now = DateTime.now();
                        if (day.year == now.year &&
                            day.month == now.month &&
                            day.day == now.day) {
                          _pair.setMood(m.imagePath, m.localizedLabel);
                          // skipCalendar: moodService уже добавил запись
                          _ws.updateMood(
                            m.imagePath,
                            m.localizedLabel,
                            skipCalendar: true,
                          );
                        }
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              LocaleService.current.moodRecorded(
                                m.localizedLabel,
                              ),
                            ),
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: m.color.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: m.color.withOpacity(0.3),
                              ),
                            ),
                            child: m.imagePath.isNotEmpty
                                ? Center(
                                    child: Image.asset(
                                      m.imagePath,
                                      width: 42,
                                      height: 42,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              const SizedBox(
                                                width: 42,
                                                height: 42,
                                              ),
                                    ),
                                  )
                                : const SizedBox(width: 42, height: 42),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            m.localizedLabel,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  DAY DETAIL
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
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              dayStr,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 16),
            if (moods.isEmpty)
              Text(
                LocaleService.current.noMoodRecorded,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
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
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: m.color.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: m.imagePath.isNotEmpty
                                      ? Center(
                                          child: Image.asset(
                                            m.imagePath,
                                            width: 34,
                                            height: 34,
                                            errorBuilder:
                                                (context, error, stackTrace) =>
                                                    const SizedBox(
                                                      width: 34,
                                                      height: 34,
                                                    ),
                                          ),
                                        )
                                      : const SizedBox(width: 34, height: 34),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    m.label,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade800,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${m.timestamp.hour.toString().padLeft(2, '0')}:${m.timestamp.minute.toString().padLeft(2, '0')}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade500,
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
                                      color: Colors.grey.shade400,
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
    );
  }

  // ── Helpers ──

  String _dayKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }
}

/// Ячейка настроения с плавной циклической сменой эмодзи раз в секунду.
class _CyclingMoodSquare extends StatefulWidget {
  final List<MoodEntry> moods;
  final double size;
  final bool isToday;
  final Color primary;

  const _CyclingMoodSquare({
    required this.moods,
    required this.size,
    required this.isToday,
    required this.primary,
  });

  @override
  State<_CyclingMoodSquare> createState() => _CyclingMoodSquareState();
}

class _CyclingMoodSquareState extends State<_CyclingMoodSquare> {
  int _currentIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCycling();
  }

  @override
  void didUpdateWidget(_CyclingMoodSquare old) {
    super.didUpdateWidget(old);
    if (old.moods.length != widget.moods.length) {
      _timer?.cancel();
      _timer = null;
      _currentIndex = 0;
      _startCycling();
    }
  }

  void _startCycling() {
    if (widget.moods.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (mounted) {
          setState(() {
            _currentIndex = (_currentIndex + 1) % widget.moods.length;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mood = widget.moods[_currentIndex % widget.moods.length];
    final size = widget.size;
    final radius = size > 20 ? 4.0 : 2.0;

    return SizedBox(
      width: size,
      height: size,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        child: Container(
          key: ValueKey(mood.id),
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: mood.color,
            borderRadius: BorderRadius.circular(radius),
            border: widget.isToday
                ? Border.all(color: widget.primary, width: 2)
                : null,
          ),
          child: size > 20 && mood.imagePath.isNotEmpty
              ? Center(
                  child: Image.asset(
                    mood.imagePath,
                    width: size * 0.7,
                    height: size * 0.7,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox(),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
