import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/mood_entry.dart';
import '../../../models/pair_data.dart';
import '../../../services/locale_service.dart';
import '../../../services/mood_service.dart';
import '../../../services/widget_service.dart';

/// Shows mood picker bottom sheet for today's mood
void showMoodPicker({
  required BuildContext context,
  required PairData pairData,
  required MoodService moodService,
  required WidgetService widgetService,
  required Color primary,
  required Color navActiveIcon,
}) {
  final today = DateTime.now();
  final todayEntries = moodService.myEntriesForDay(today);
  final currentEmoji = todayEntries.isNotEmpty
      ? todayEntries.first.imagePath
      : pairData.myMood.imagePath;

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      builder: (ctx, scrollController) => _MoodPickerSheet(
        scrollController: scrollController,
        currentEmoji: currentEmoji,
        primary: primary,
        title: LocaleService.current.howAreYouFeeling,
        subtitle: LocaleService.current.partnerWillSeeMood,
        onSelect: (mood) {
          Navigator.pop(ctx);
          for (final e in moodService.myEntriesForDay(today)) {
            moodService.deleteMoodEntry(e.id);
          }
          pairData.setMood(mood.imagePath, mood.localizedLabel);
          moodService.addMood(
            moodId: mood.id,
            imagePath: mood.imagePath,
            label: mood.localizedLabel,
          );
          widgetService.updateMood(
            mood.imagePath,
            mood.localizedLabel,
            skipCalendar: true,
          );
        },
        onClear: currentEmoji.isNotEmpty
            ? () async {
                Navigator.pop(ctx);
                for (final e in moodService.myEntriesForDay(today)) {
                  await moodService.deleteMoodEntry(e.id);
                }
                pairData.clearMood();
                widgetService.clearMood();
              }
            : null,
      ),
    ),
  );
}

/// Shows mood picker for a specific date
void showMoodPickerForDate({
  required BuildContext context,
  required DateTime date,
  required PairData pairData,
  required MoodService moodService,
  required WidgetService widgetService,
  required Color primary,
  required Color navActiveIcon,
}) {
  final today = DateTime.now();
  final todayNorm = DateTime(today.year, today.month, today.day);
  if (date.isAfter(todayNorm)) return;

  final isToday = date.year == today.year &&
      date.month == today.month &&
      date.day == today.day;

  final existingEntries = moodService.myEntriesForDay(date);
  final existingPath =
      existingEntries.isNotEmpty ? existingEntries.first.imagePath : '';

  final s = LocaleService.current;
  final months = s.shortMonths;
  final weekdays = s.shortWeekdays;
  final dateLabel = isToday
      ? s.todayDate
      : '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]}';

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      builder: (ctx, scrollController) => _MoodPickerSheet(
        scrollController: scrollController,
        currentEmoji: existingPath,
        primary: primary,
        title: s.moodDateLabel(dateLabel),
        subtitle: isToday ? s.partnerWillSeeMood : s.indicateMoodForDay,
        onSelect: (mood) {
          Navigator.pop(ctx);
          if (isToday) {
            pairData.setMood(mood.imagePath, mood.localizedLabel);
            widgetService.updateMood(
              mood.imagePath,
              mood.localizedLabel,
              skipCalendar: true,
            );
          }
          moodService.addMood(
            moodId: mood.id,
            imagePath: mood.imagePath,
            label: mood.localizedLabel,
            date: date,
          );
        },
        onClear: existingPath.isNotEmpty
            ? () async {
                Navigator.pop(ctx);
                for (final e in moodService.myEntriesForDay(date)) {
                  await moodService.deleteMoodEntry(e.id);
                }
                if (isToday) {
                  pairData.clearMood();
                  widgetService.clearMood();
                }
              }
            : null,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Shared bottom-sheet widget
// ─────────────────────────────────────────────────────────────────────────────

class _MoodPickerSheet extends StatelessWidget {
  final ScrollController scrollController;
  final String currentEmoji;
  final Color primary;
  final String title;
  final String subtitle;
  final void Function(MoodOption) onSelect;
  final Future<void> Function()? onClear;

  const _MoodPickerSheet({
    required this.scrollController,
    required this.currentEmoji,
    required this.primary,
    required this.title,
    required this.subtitle,
    required this.onSelect,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 20),
          // Grid
          Expanded(
            child: GridView.builder(
              controller: scrollController,
              padding: const EdgeInsets.only(bottom: 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.78,
              ),
              itemCount: MoodOption.all.length,
              itemBuilder: (_, i) {
                final mood = MoodOption.all[i];
                final isSelected = currentEmoji == mood.imagePath;
                return _MoodTile(
                  mood: mood,
                  isSelected: isSelected,
                  primary: primary,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onSelect(mood);
                  },
                );
              },
            ),
          ),
          // Clear button
          if (onClear != null) ...[
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextButton(
                  onPressed: onClear,
                  child: Text(
                    LocaleService.current.clearMood,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ),
              ),
            ),
          ] else
            const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Single emoji tile
// ─────────────────────────────────────────────────────────────────────────────

class _MoodTile extends StatelessWidget {
  final MoodOption mood;
  final bool isSelected;
  final Color primary;
  final VoidCallback onTap;

  static const double _radius = 16;

  const _MoodTile({
    required this.mood,
    required this.isSelected,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_radius),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: mood.color.withValues(alpha: 0.55),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_radius),
                child: mood.imagePath.isNotEmpty
                    ? Image.asset(
                        mood.imagePath,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        errorBuilder: (_, __, _) => Container(
                          color: mood.color,
                        ),
                      )
                    : Container(color: mood.color),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            mood.localizedLabel,
            style: TextStyle(
              fontSize: 10,
              fontWeight:
                  isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? primary : Colors.grey.shade600,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.visible,
          ),
        ],
      ),
    );
  }
}
