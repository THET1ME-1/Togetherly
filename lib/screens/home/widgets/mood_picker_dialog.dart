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
            // Handle
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
              LocaleService.current.howAreYouFeeling,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              LocaleService.current.partnerWillSeeMood,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 24),
            // Mood grid - scrollable
            Expanded(
              child: GridView.builder(
                controller: scrollController,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.75,
                ),
                itemCount: MoodOption.all.length,
                itemBuilder: (ctx2, i) {
                  final mood = MoodOption.all[i];
                  final isSelected = currentEmoji == mood.imagePath;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(ctx2);
                      // Delete existing entries for today first
                      for (final e in moodService.myEntriesForDay(today)) {
                        moodService.deleteMoodEntry(e.id);
                      }
                      pairData.setMood(mood.imagePath, mood.label);
                      moodService.addMood(
                        moodId: mood.id,
                        imagePath: mood.imagePath,
                        label: mood.label,
                      );
                      widgetService.updateMood(mood.imagePath, mood.label);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? primary.withOpacity(0.12)
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? primary : Colors.grey.shade200,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (mood.imagePath.isNotEmpty)
                            Image.asset(
                              mood.imagePath,
                              width: 44,
                              height: 44,
                              errorBuilder: (context, error, stackTrace) =>
                                  const SizedBox(width: 44, height: 44),
                            ),
                          const SizedBox(height: 4),
                          Text(
                            mood.label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? primary
                                  : Colors.grey.shade600,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            // Clear mood button
            if (currentEmoji.isNotEmpty) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  // Delete entries for today
                  for (final e in moodService.myEntriesForDay(today)) {
                    await moodService.deleteMoodEntry(e.id);
                  }
                  pairData.clearMood();
                  widgetService.clearMood();
                },
                child: Text(
                  LocaleService.current.clearMood,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade500,
                  ),
                ),
              ),
            ],
          ],
        ),
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
}) {
  final today = DateTime.now();
  final todayNorm = DateTime(today.year, today.month, today.day);
  // Don't allow future dates
  if (date.isAfter(todayNorm)) return;

  final isToday =
      date.year == today.year &&
      date.month == today.month &&
      date.day == today.day;

  // Get existing mood for this date
  final existingEntries = moodService.myEntriesForDay(date);
  final existingPath = existingEntries.isNotEmpty
      ? existingEntries.first.imagePath
      : '';

  // Date label
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
            // Handle
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
              s.moodDateLabel(dateLabel),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isToday ? s.partnerWillSeeMood : s.indicateMoodForDay,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: GridView.builder(
                controller: scrollController,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.75,
                ),
                itemCount: MoodOption.all.length,
                itemBuilder: (ctx2, i) {
                  final mood = MoodOption.all[i];
                  final isSelected = existingPath == mood.imagePath;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(ctx2);
                      if (isToday) {
                        pairData.setMood(mood.imagePath, mood.label);
                        widgetService.updateMood(mood.imagePath, mood.label);
                      }
                      moodService.addMood(
                        moodId: mood.id,
                        imagePath: mood.imagePath,
                        label: mood.label,
                        date: date,
                      );
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? primary.withOpacity(0.12)
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? primary : Colors.grey.shade200,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (mood.imagePath.isNotEmpty)
                            Image.asset(
                              mood.imagePath,
                              width: 44,
                              height: 44,
                              errorBuilder: (context, error, stackTrace) =>
                                  const SizedBox(width: 44, height: 44),
                            ),
                          const SizedBox(height: 4),
                          Text(
                            mood.label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? primary
                                  : Colors.grey.shade600,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            if (existingPath.isNotEmpty) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  // Delete entries for this date
                  for (final e in moodService.myEntriesForDay(date)) {
                    await moodService.deleteMoodEntry(e.id);
                  }
                  if (isToday) {
                    pairData.clearMood();
                    widgetService.clearMood();
                  }
                },
                child: Text(
                  s.removeMood,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
