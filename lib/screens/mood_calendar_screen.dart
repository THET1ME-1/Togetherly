import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/mood_entry.dart';
import '../models/pair_data.dart';
import '../services/mood_service.dart';

/// Экран «Mood Calendar»
/// Верхняя часть — мой календарь, нижняя — календарь партнёра.
/// Каждый день — квадрат, разделённый на цвета настроений.
class MoodCalendarScreen extends StatefulWidget {
  final PairData pairData;
  final MoodService moodService;

  const MoodCalendarScreen({
    super.key,
    required this.pairData,
    required this.moodService,
  });

  @override
  State<MoodCalendarScreen> createState() => _MoodCalendarScreenState();
}

class _MoodCalendarScreenState extends State<MoodCalendarScreen> {
  static const Color primary = Color(0xFFEE2B6C);

  int _selectedPeriod = 1; // 0=Week, 1=Month, 2=Year
  late DateTime _currentMonth;

  MoodService get _mood => widget.moodService;
  PairData get _pair => widget.pairData;

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
              'Mood Calendar',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade900,
              ),
            ),
            centerTitle: true,
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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: _buildCalendarSection(
                label: 'My Mood',
                entries: _mood.myEntries,
                stats: _mood.myStats(from: _periodStart, to: _periodEnd),
              ),
            ),
          ),

          // ── Partner calendars ──
          ..._pair.partners.map(
            (p) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: _buildCalendarSection(
                  label: '${p.name}\'s Mood',
                  entries: _mood.partnerEntries(p.uid),
                  stats: _mood.partnerStats(
                    p.uid,
                    from: _periodStart,
                    to: _periodEnd,
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
    const labels = ['Week', 'Month', 'Year'];
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
                          ? primary
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
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
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
    return Wrap(
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
            Text(m.emoji, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 2),
            Text(
              m.label,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  // ═══════════════════════════════════════════
  //  CALENDAR SECTION (grid + stats)
  // ═══════════════════════════════════════════

  Widget _buildCalendarSection({
    required String label,
    required List<MoodEntry> entries,
    required Map<String, int> stats,
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
        _buildGrid(byDay),

        const SizedBox(height: 16),

        // Stats bar
        if (stats.isNotEmpty) _buildStatsBar(stats),
      ],
    );
  }

  // ═══════════════════════════════════════════
  //  GRID
  // ═══════════════════════════════════════════

  Widget _buildGrid(Map<String, List<MoodEntry>> byDay) {
    switch (_selectedPeriod) {
      case 0:
        return _buildWeekGrid(byDay);
      case 1:
        return _buildMonthGrid(byDay);
      case 2:
        return _buildYearGrid(byDay);
      default:
        return _buildMonthGrid(byDay);
    }
  }

  Widget _buildWeekGrid(Map<String, List<MoodEntry>> byDay) {
    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day - now.weekday + 1);
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

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
                color: isToday ? primary : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () => _showMoodPickerForDay(day),
              onLongPress: moods.isNotEmpty
                  ? () => _showDayDetail(day, moods)
                  : null,
              child: _moodSquare(moods, size: 40, isToday: isToday),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildMonthGrid(Map<String, List<MoodEntry>> byDay) {
    final first = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final daysInMonth = DateTime(
      _currentMonth.year,
      _currentMonth.month + 1,
      0,
    ).day;
    final startWeekday = first.weekday; // 1=Mon
    final now = DateTime.now();

    const dayNames = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

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
                  onTap: () => _showMoodPickerForDay(day),
                  onLongPress: moods.isNotEmpty
                      ? () => _showDayDetail(day, moods)
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
        final monthStart = DateTime(year, month + 1, 1);
        final daysInMonth = DateTime(year, month + 2, 0).day;
        final months = [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ];

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
          border: isToday ? Border.all(color: primary, width: 2) : null,
        ),
      );
    }

    if (moods.length == 1) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: moods.first.color,
          borderRadius: BorderRadius.circular(size > 20 ? 4 : 2),
          border: isToday ? Border.all(color: primary, width: 2) : null,
        ),
        child: size > 30
            ? Center(
                child: Text(
                  moods.first.emoji,
                  style: TextStyle(fontSize: size * 0.4),
                ),
              )
            : null,
      );
    }

    // Multiple moods — split square
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size > 20 ? 4 : 2),
        border: isToday ? Border.all(color: primary, width: 2) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        size: Size(size, size),
        painter: _MoodSplitPainter(
          colors: moods.map((m) => m.color).toList(),
          radius: size > 20 ? 4 : 2,
        ),
      ),
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
                Text(
                  '${mood?.emoji ?? '?'} $pct%',
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
  //  MOOD PICKER FOR DAY
  // ═══════════════════════════════════════════

  void _showMoodPickerForDay(DateTime day) {
    final dayStr =
        '${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}.${day.year}';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
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
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'How are you feeling?',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade900,
              ),
            ),
            const SizedBox(height: 20),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 5,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.75,
              children: MoodOption.all.map((m) {
                return GestureDetector(
                  onTap: () {
                    _mood.addMood(
                      moodId: m.id,
                      emoji: m.emoji,
                      label: m.label,
                      date: day,
                    );
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${m.emoji} ${m.label} recorded!'),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: m.color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: m.color.withOpacity(0.3)),
                        ),
                        child: Center(
                          child: Text(
                            m.emoji,
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        m.label,
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
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  DAY DETAIL
  // ═══════════════════════════════════════════

  void _showDayDetail(DateTime day, List<MoodEntry> moods) {
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
                'No mood recorded',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
              )
            else
              ...moods.map(
                (m) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: m.color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            m.emoji,
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
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

/// Painter для разделения квадрата на несколько цветов.
/// Клипируется к RRect, чтобы цвета не выходили за скруглённые углы.
class _MoodSplitPainter extends CustomPainter {
  final List<Color> colors;
  final double radius;

  _MoodSplitPainter({required this.colors, this.radius = 8});

  @override
  void paint(Canvas canvas, Size size) {
    if (colors.isEmpty) return;

    // Clip to rounded rect so nothing escapes the corners
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Radius.circular(radius),
      ),
    );

    final count = colors.length;
    if (count == 1) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = colors.first,
      );
    } else if (count <= 3) {
      // Split horizontally for 2-3
      final w = size.width / count;
      for (var i = 0; i < count; i++) {
        canvas.drawRect(
          Rect.fromLTWH(w * i, 0, w, size.height),
          Paint()..color = colors[i],
        );
      }
    } else {
      // Grid layout for 4+
      final cols = count <= 4 ? 2 : (count <= 9 ? 3 : 4);
      final rows = (count / cols).ceil();
      final cellW = size.width / cols;
      final cellH = size.height / rows;
      for (var i = 0; i < count; i++) {
        final col = i % cols;
        final row = i ~/ cols;
        canvas.drawRect(
          Rect.fromLTWH(cellW * col, cellH * row, cellW, cellH),
          Paint()..color = colors[i],
        );
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MoodSplitPainter oldDelegate) {
    return oldDelegate.colors != colors;
  }
}
