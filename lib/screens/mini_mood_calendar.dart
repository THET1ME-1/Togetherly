import 'dart:async';

import 'package:flutter/material.dart';
import '../models/mood_entry.dart';
import '../services/mood_service.dart';
import '../theme/app_theme.dart';

/// Горизонтальный мини-календарь с настроениями по дням.
/// Показывает текущую неделю (Пн–Вс). Сегодня — выделен.
/// Эмодзи = настроение, выбранное на этот день.
/// Нажатие на день вызывает [onDayTap].
class MiniMoodCalendar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayNorm = DateTime(today.year, today.month, today.day);
    // Начало текущей недели — понедельник
    final monday = todayNorm.subtract(Duration(days: today.weekday - 1));
    final days = List.generate(7, (i) => monday.add(Duration(days: i)));

    return ListenableBuilder(
      listenable: moodService,
      builder: (context, _) {
        return SizedBox(
          height: 118,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            physics: const BouncingScrollPhysics(),
            itemCount: days.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              return _DayCell(
                date: days[index],
                today: today,
                moodService: moodService,
                theme: theme,
                onTap: onDayTap,
              );
            },
          ),
        );
      },
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
        width: 66,
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(20),
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
