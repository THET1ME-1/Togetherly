import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/mood_entry.dart';
import '../../../models/pair_data.dart';
import '../../../services/locale_service.dart';
import '../../../services/mood_pack_service.dart';
import '../../../services/mood_service.dart';
import '../../../services/widget_service.dart';
import '../../../widgets/mood_pack_selector.dart';

/// Shows mood picker bottom sheet for today's mood.
///
/// Все апдейты идут через [MoodService.setMoodForToday] — единая точка входа,
/// которая атомарно обновляет календарь + group memberMoods + widgetData.
/// Параметры pairData/widgetService оставлены ради обратной совместимости;
/// MoodService уже связан с ними через bindServices в home_screen.initState.
void showMoodPicker({
  required BuildContext context,
  required PairData pairData,
  required MoodService moodService,
  required WidgetService widgetService,
  required Color primary,
  required Color navActiveIcon,
}) {
  final mood = moodService.myMoodToday;
  final currentEmoji = mood?.imagePath ?? '';

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
          moodService.setMoodForToday(
            moodId: mood.id,
            imagePath: mood.imagePath,
            label: mood.localizedLabel,
          );
        },
        onClear: currentEmoji.isNotEmpty
            ? () async {
                Navigator.pop(ctx);
                await moodService.clearMoodForToday();
              }
            : null,
      ),
    ),
  );
}

/// Shows mood picker for a specific date.
/// Для сегодняшней даты использует [MoodService.setMoodForToday]
/// (атомарный апдейт всех трёх источников). Для прошлых — только календарь.
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
          moodService.setMoodForDate(
            date: date,
            moodId: mood.id,
            imagePath: mood.imagePath,
            label: mood.localizedLabel,
          );
        },
        onClear: existingPath.isNotEmpty
            ? () async {
                Navigator.pop(ctx);
                await moodService.clearMoodForDate(date);
              }
            : null,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Shared bottom-sheet widget
// ─────────────────────────────────────────────────────────────────────────────

class _MoodPickerSheet extends StatefulWidget {
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
  State<_MoodPickerSheet> createState() => _MoodPickerSheetState();
}

class _MoodPickerSheetState extends State<_MoodPickerSheet> {
  @override
  void initState() {
    super.initState();
    // Загрузить сохранённый выбор пака (идемпотентно); AnimatedBuilder ниже
    // перестроит сетку, когда значение подгрузится/изменится.
    MoodPackService.instance.load();
  }

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
            widget.title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.subtitle,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 14),
          // Pack selector
          MoodPackSelector(
            primary: widget.primary,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          // Grid (перестраивается при смене пака)
          Expanded(
            child: AnimatedBuilder(
              animation: MoodPackService.instance,
              builder: (context, _) {
                final pack = MoodPackService.instance.selectedPack;
                return GridView.builder(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.only(bottom: 16),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.68,
                  ),
                  itemCount: pack.moods.length,
                  itemBuilder: (_, i) {
                    final mood = pack.moods[i];
                    final isSelected = widget.currentEmoji == mood.imagePath;
                    return _MoodTile(
                      mood: mood,
                      isSelected: isSelected,
                      primary: widget.primary,
                      tileGradient: pack.tileGradient,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        widget.onSelect(mood);
                      },
                    );
                  },
                );
              },
            ),
          ),
          // Clear button
          if (widget.onClear != null) ...[
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextButton(
                  onPressed: widget.onClear,
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

  /// Подложка для паков с прозрачными стикерами (напр. розовый). null —
  /// картинка непрозрачная и заполняет плитку сама (классический пак).
  final List<Color>? tileGradient;
  final VoidCallback onTap;

  static const double _radius = 16;

  const _MoodTile({
    required this.mood,
    required this.isSelected,
    required this.primary,
    required this.onTap,
    this.tileGradient,
  });

  @override
  Widget build(BuildContext context) {
    final gradient = tileGradient;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1.0,
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
                child: Container(
                  // Мягкий фон под прозрачными стикерами; для классики gradient
                  // == null и непрозрачная картинка перекрывает белый фон.
                  decoration: BoxDecoration(
                    color: gradient == null ? null : Colors.white,
                    gradient: gradient != null
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: gradient,
                          )
                        : null,
                  ),
                  child: mood.imagePath.isNotEmpty
                      ? Image.asset(
                          mood.imagePath,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          errorBuilder: (_, _, _) => Container(
                            color: mood.color,
                          ),
                        )
                      : Container(color: mood.color),
                ),
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
