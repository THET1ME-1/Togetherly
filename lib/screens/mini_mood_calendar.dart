import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/mood_entry.dart';
import '../services/mood_service.dart';
import '../theme/app_theme.dart';

/// Горизонтальный мини-календарь с настроениями по дням.
/// Листается бесконечно вперёд и назад. Сегодня — выделен.
/// При прокрутке от сегодня появляется кнопка «Сегодня».
class MiniMoodCalendar extends StatefulWidget {
  final MoodService moodService;
  final AppTheme theme;
  final void Function(DateTime date) onDayTap;

  const MiniMoodCalendar({
    super.key,
    required this.moodService,
    required this.theme,
    required this.onDayTap,
  });

  static const _dayNames = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  @override
  State<MiniMoodCalendar> createState() => _MiniMoodCalendarState();
}

class _MiniMoodCalendarState extends State<MiniMoodCalendar> {
  // Виртуальный центр списка — сегодня
  static const int _kCenter = 500000;
  static const double _kCellWidth = 74.0;
  static const double _kSeparator = 10.0;
  static const double _kItemStride = _kCellWidth + _kSeparator;

  late final ScrollController _scrollController;
  late final DateTime _today;
  late final DateTime _todayNorm;

  bool _showBackToToday = false;
  double _todayScrollOffset = _kCenter * _kItemStride;
  int _lastDaysScrolled = 0;
  int _lastDayIndex = 0;

  @override
  void initState() {
    super.initState();
    _today = DateTime.now();
    _todayNorm = DateTime(_today.year, _today.month, _today.day);
    _scrollController = ScrollController(
      initialScrollOffset: _kCenter * _kItemStride,
    );
    _scrollController.addListener(_onScroll);
    // После первого фрейма сдвигаем скролл так, чтобы сегодня был последним справа
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final viewport = _scrollController.position.viewportDimension;
      _todayScrollOffset = (_kCenter * _kItemStride) - viewport + _kItemStride;
      _scrollController.jumpTo(_todayScrollOffset);
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    final diff = (offset - _todayScrollOffset).abs() / _kItemStride;
    final shouldShow = diff > 0.8;
    if (shouldShow != _showBackToToday) {
      setState(() => _showBackToToday = shouldShow);
    }

    // Вибрация при пролистывании за экран каждого дня
    final daysScrolled = diff.floor();
    if (daysScrolled != _lastDaysScrolled) {
      _lastDaysScrolled = daysScrolled;
      HapticFeedback.selectionClick();
    }
  }

  void _scrollToToday() {
    _scrollController.animateTo(
      _todayScrollOffset,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Переводим виртуальный индекс → дата
  DateTime _dateForIndex(int index) {
    return _todayNorm.add(Duration(days: index - _kCenter));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 154,
          child: ListenableBuilder(
            listenable: widget.moodService,
            builder: (context, _) {
              return ListView.builder(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                clipBehavior: Clip.none,
                physics: const BouncingScrollPhysics(),
                itemCount: _kCenter * 2,
                itemExtent: _kItemStride,
                itemBuilder: (context, index) {
                  final date = _dateForIndex(index);
                  
                  return AnimatedBuilder(
                    animation: _scrollController,
                    builder: (context, child) {
                      double dy = 0.0;
                      if (_scrollController.hasClients) {
                        final position = _scrollController.position;
                        final viewportWidth = position.viewportDimension;
                        final scrollOffset = position.pixels;
                        
                        final viewportCenter = scrollOffset + (viewportWidth / 2);
                        final itemCenter = (index * _kItemStride) + (_kCellWidth / 2);
                        final distance = (itemCenter - viewportCenter).abs();
                        
                        // Парарабола, чтобы боковые карточки опускались: dy = a * x^2
                        dy = (distance * distance) * 0.00075;
                        if (dy > 45.0) dy = 45.0; // ограничиваем сдвиг
                      }
                      
                      return Transform.translate(
                        offset: Offset(0, dy),
                        child: child,
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(right: _kSeparator),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: RepaintBoundary(
                          child: _DayCell(
                            date: date,
                            today: _today,
                            moodService: widget.moodService,
                            theme: widget.theme,
                            onTap: widget.onDayTap,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),

        // ── Кнопка «Today» — под списком, по центру ──
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: _showBackToToday
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: GestureDetector(
                    onTap: _scrollToToday,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: widget.theme.primary,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: widget.theme.primary.withOpacity(0.30),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.today_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Today',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _DayCell extends StatefulWidget {
  final DateTime date;
  final DateTime today;
  final MoodService moodService;
  final AppTheme theme;
  final void Function(DateTime) onTap;

  const _DayCell({
    required this.date,
    required this.today,
    required this.moodService,
    required this.theme,
    required this.onTap,
  });

  @override
  State<_DayCell> createState() => _DayCellState();
}

class _DayCellState extends State<_DayCell> {
  int _currentIndex = 0;
  Timer? _timer;

  bool get isToday =>
      widget.date.year == widget.today.year &&
      widget.date.month == widget.today.month &&
      widget.date.day == widget.today.day;

  bool get isFuture => widget.date.isAfter(
    DateTime(widget.today.year, widget.today.month, widget.today.day),
  );

  @override
  void initState() {
    super.initState();
    _maybeStartTimer();
  }

  @override
  void didUpdateWidget(_DayCell old) {
    super.didUpdateWidget(old);
    _maybeStartTimer();
  }

  void _maybeStartTimer() {
    final entries = widget.moodService.myEntriesForDay(widget.date);
    if (entries.length > 1 && _timer == null) {
      _timer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (mounted) {
          setState(() {
            final entries = widget.moodService.myEntriesForDay(widget.date);
            if (entries.length > 1) {
              _currentIndex = (_currentIndex + 1) % entries.length;
            }
          });
        }
      });
    } else if (entries.length <= 1) {
      _timer?.cancel();
      _timer = null;
      _currentIndex = 0;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.moodService.myEntriesForDay(widget.date);
    final safeIndex = entries.isEmpty ? 0 : _currentIndex % entries.length;
    final MoodEntry? current = entries.isNotEmpty ? entries[safeIndex] : null;
    final dayName = MiniMoodCalendar._dayNames[widget.date.weekday - 1];

    final Color cardBg = isToday
        ? widget.theme.primary.withOpacity(0.13)
        : Colors.white.withOpacity(0.75);
    final Color textColor = isToday
        ? widget.theme.primary
        : const Color(0xFF6B7280);
    final Color numColor = isToday
        ? widget.theme.primary
        : const Color(0xFF1F2937);

    return GestureDetector(
      onTap: isFuture ? null : () => widget.onTap(widget.date),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 74,
        height: 118,
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: isToday
                ? widget.theme.primary.withOpacity(0.35)
                : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: isToday
              ? [
                  BoxShadow(
                    color: widget.theme.primary.withOpacity(0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Opacity(
          opacity: isFuture ? 0.35 : 1.0,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                dayName,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.date.day.toString(),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: numColor,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 30,
                height: 30,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  child: current != null && current.imagePath.isNotEmpty
                      ? Image.asset(
                          current.imagePath,
                          key: ValueKey(current.id),
                          width: 30,
                          height: 30,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
