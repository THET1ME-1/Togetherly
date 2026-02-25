import 'package:flutter/material.dart';
import '../models/mood_entry.dart';
import '../services/mood_service.dart';
import '../theme/app_theme.dart';

/// Горизонтальный мини-календарь с настроениями по дням.
/// Показывает последние [daysToShow] дней. Сегодня — выделен.
/// Эмодзи = настроение, выбранное на этот день.
/// Нажатие на день вызывает [onDayTap].
class MiniMoodCalendar extends StatelessWidget {
  final MoodService moodService;
  final AppTheme theme;
  final void Function(DateTime date) onDayTap;
  final int daysToShow;

  const MiniMoodCalendar({
    super.key,
    required this.moodService,
    required this.theme,
    required this.onDayTap,
    this.daysToShow = 7,
  });

  static const _dayNames = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final days = List.generate(
      daysToShow,
      (i) => DateTime(
        today.year,
        today.month,
        today.day,
      ).subtract(Duration(days: daysToShow - 1 - i)),
    );

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

class _DayCell extends StatelessWidget {
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

  bool get isToday =>
      date.year == today.year &&
      date.month == today.month &&
      date.day == today.day;

  @override
  Widget build(BuildContext context) {
    final entries = moodService.myEntriesForDay(date);
    final MoodEntry? topEntry = entries.isNotEmpty ? entries.first : null;
    final dayName = MiniMoodCalendar._dayNames[date.weekday - 1];

    final Color cardBg = isToday
        ? theme.primary.withOpacity(0.13)
        : Colors.white.withOpacity(0.75);
    final Color textColor = isToday ? theme.primary : const Color(0xFF6B7280);
    final Color numColor = isToday ? theme.primary : const Color(0xFF1F2937);

    return GestureDetector(
      onTap: () => onTap(date),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 66,
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isToday
                ? theme.primary.withOpacity(0.35)
                : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: isToday
              ? [
                  BoxShadow(
                    color: theme.primary.withOpacity(0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
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
              date.day.toString(),
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
              child: topEntry != null && topEntry.imagePath.isNotEmpty
                  ? Image.asset(
                      topEntry.imagePath,
                      width: 30,
                      height: 30,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
