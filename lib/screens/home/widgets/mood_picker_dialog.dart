import 'package:flutter/material.dart';
import '../../../theme/profile_theme.dart';
import '../../../theme/theme_scope.dart';
import '../../../widgets/mood_image.dart';
import 'package:flutter/services.dart';
import '../../../models/ailment.dart';
import '../../../models/mood_band.dart';
import '../../../models/mood_entry.dart';
import '../../../models/user_data.dart';
import '../../../models/mood_pack.dart';
import '../../../models/pair_data.dart';
import '../../../services/locale_service.dart';
import '../../../services/mood_pack_service.dart';
import '../../../services/mood_service.dart';
import '../../../services/widget_service.dart';
import '../../../widgets/mood_pack_selector.dart';
import '../../../widgets/mood_tile_shapes.dart';

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
  UserData? user,
  Set<String> pairOwned = const {},
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
      builder: (ctx, scrollController) => MoodPickerSheet(
        scrollController: scrollController,
        currentEmoji: currentEmoji,
        primary: primary,
        user: user,
        pairOwned: pairOwned,
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
        // ── Вкладка «Самочувствие» (болячки) ──
        showAilmentTab: true,
        currentAilmentId: pairData.myAilment.id,
        onSelectAilment: (a) {
          Navigator.pop(ctx);
          pairData.setAilment(a.id, a.localizedLabel, a.emoji);
        },
        onClearAilment: pairData.myAilment.isNotEmpty
            ? () async {
                Navigator.pop(ctx);
                await pairData.clearAilment();
              }
            : null,
      ),
    ),
  );
}

/// Shows mood picker for a specific date.
/// Для сегодняшней даты использует [MoodService.setMoodForToday]
/// (атомарный апдейт всех трёх источников). Для прошлых — только календарь.
/// [withAilmentTab] — показывать ли переключатель «Настроение / Самочувствие».
/// Из листа дня он не нужен: разделы там уже разведены отдельными пунктами, и
/// второй ряд вкладок внутри выглядел бы дублем выбора.
void showMoodPickerForDate({
  required BuildContext context,
  required DateTime date,
  required PairData pairData,
  UserData? user,
  Set<String> pairOwned = const {},
  required MoodService moodService,
  required WidgetService widgetService,
  required Color primary,
  required Color navActiveIcon,
  bool withAilmentTab = true,
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
      builder: (ctx, scrollController) => MoodPickerSheet(
        scrollController: scrollController,
        currentEmoji: existingPath,
        primary: primary,
        user: user,
        pairOwned: pairOwned,
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
        // Самочувствие — текущий статус, не история: вкладка только для сегодня.
        showAilmentTab: withAilmentTab && isToday,
        currentAilmentId: isToday ? pairData.myAilment.id : '',
        onSelectAilment: isToday
            ? (a) {
                Navigator.pop(ctx);
                pairData.setAilment(a.id, a.localizedLabel, a.emoji);
              }
            : null,
        onClearAilment: (isToday && pairData.myAilment.isNotEmpty)
            ? () async {
                Navigator.pop(ctx);
                await pairData.clearAilment();
              }
            : null,
      ),
    ),
  );
}

/// Лист «Самочувствие» сам по себе — без вкладок и без сетки настроений.
///
/// Самочувствие живёт не в календаре, а в профиле пары и стареет само, поэтому
/// отмечается только на сегодня; лист дня зовёт его лишь для текущей даты.
void showAilmentPicker({
  required BuildContext context,
  required PairData pairData,
  required Color primary,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (ctx, scrollController) => MoodPickerSheet(
        scrollController: scrollController,
        currentEmoji: '',
        primary: primary,
        title: LocaleService.current.ailmentTabLabel,
        subtitle: LocaleService.current.ailmentPickerSubtitle,
        onSelect: (_) {},
        onClear: null,
        ailmentOnly: true,
        currentAilmentId: pairData.myAilment.id,
        onSelectAilment: (a) {
          Navigator.pop(ctx);
          pairData.setAilment(a.id, a.localizedLabel, a.emoji);
        },
        onClearAilment: pairData.myAilment.isNotEmpty
            ? () async {
                Navigator.pop(ctx);
                await pairData.clearAilment();
              }
            : null,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Shared bottom-sheet widget
// ─────────────────────────────────────────────────────────────────────────────

/// Тело листа выбора настроения. Публичный ради golden-тестов раскладки.
class MoodPickerSheet extends StatefulWidget {
  final ScrollController scrollController;
  final String currentEmoji;
  final Color primary;
  final String title;
  final String subtitle;
  final void Function(MoodOption) onSelect;
  final Future<void> Function()? onClear;

  // ── Вкладка «Самочувствие» (опционально) ──
  final bool showAilmentTab;

  /// Лист целиком про самочувствие: ни вкладок, ни сетки настроений.
  final bool ailmentOnly;

  /// Кошелёк и покупки человека: по ним пак настроений закрывается замком.
  /// Без него замков нет — так ведут себя точки вызова без данных о человеке.
  final UserData? user;

  /// Ключи `owned_features` группы: пак общий на пару, платит кто-то один.
  final Set<String> pairOwned;
  final String currentAilmentId;
  final void Function(Ailment)? onSelectAilment;
  final Future<void> Function()? onClearAilment;

  const MoodPickerSheet({
    required this.scrollController,
    required this.currentEmoji,
    required this.primary,
    required this.title,
    required this.subtitle,
    required this.onSelect,
    required this.onClear,
    this.user,
    this.pairOwned = const {},
    this.showAilmentTab = false,
    this.ailmentOnly = false,
    this.currentAilmentId = '',
    this.onSelectAilment,
    this.onClearAilment,
  });

  @override
  State<MoodPickerSheet> createState() => _MoodPickerSheetState();
}

class _MoodPickerSheetState extends State<MoodPickerSheet> {
  int _tab = 0; // 0 — настроение, 1 — самочувствие

  @override
  void initState() {
    super.initState();
    // Загрузить сохранённый выбор пака (идемпотентно); AnimatedBuilder ниже
    // перестроит сетку, когда значение подгрузится/изменится.
    MoodPackService.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final t = context.appTheme;
    final cs = ProfileTheme.schemeFor(t);
    final onAilment = widget.ailmentOnly || (widget.showAilmentTab && _tab == 1);
    return Container(
      decoration: BoxDecoration(
        color: t.cardSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          // Ручка листа по спецификации M3: 32×4.
          Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Заголовок держим на обеих вкладках: раньше при двух вкладках он
          // исчезал и наверху оставалась одна серая строка подсказки.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      fontFamily: ProfileTheme.displayFont,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      height: 1.2,
                      color: t.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  onAilment ? s.ailmentPickerSubtitle : widget.subtitle,
                  style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (widget.showAilmentTab)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: _segmented(s, cs),
            ),
          Expanded(child: onAilment ? _ailmentList(cs) : _moodBody(cs)),
          _clearButton(s, cs, onAilment),
        ],
      ),
    );
  }

  /// Связанная группа кнопок M3 Expressive: выбранная вкладка забирает больше
  /// места и округляется в стадион, соседняя остаётся мягким прямоугольником.
  Widget _segmented(AppStrings s, ColorScheme cs) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          _segBtn(s.moodTabLabel, 0, cs, first: true),
          const SizedBox(width: 4),
          _segBtn(s.ailmentTabLabel, 1, cs, first: false),
        ],
      ),
    );
  }

  Widget _segBtn(String label, int idx, ColorScheme cs, {required bool first}) {
    final active = _tab == idx;
    final outer = Radius.circular(active ? 24 : 20);
    final inner = Radius.circular(active ? 24 : 12);
    return Expanded(
      flex: active ? 145 : 100,
      child: GestureDetector(
        onTap: () => setState(() => _tab = idx),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? widget.primary : cs.surfaceContainerHigh,
            borderRadius: BorderRadius.only(
              topLeft: first ? outer : inner,
              bottomLeft: first ? outer : inner,
              topRight: first ? inner : outer,
              bottomRight: first ? inner : outer,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: active ? cs.onPrimary : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _moodBody(ColorScheme cs) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
          child: MoodPackSelector(
            primary: widget.primary,
            user: widget.user,
            pairOwned: widget.pairOwned,
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(
          child: AnimatedBuilder(
            animation: MoodPackService.instance,
            builder: (context, _) {
              final pack = MoodPackService.instance.selectedPack;
              final sections = groupMoodsByBand(pack.moods);
              return ListView.builder(
                controller: widget.scrollController,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                itemCount: sections.length,
                itemBuilder: (_, i) => _bandSection(sections[i], pack, cs),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Раздел сетки: подпись с линией и свои пять колонок.
  Widget _bandSection(MoodBandSection section, MoodPack pack, ColorScheme cs) {
    final s = LocaleService.current;
    final title = switch (section.band) {
      MoodBand.bright => s.moodBandBright,
      MoodBand.even => s.moodBandEven,
      MoodBand.sad => s.moodBandSad,
      MoodBand.heavy => s.moodBandHeavy,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 14, 2, 10),
          child: Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Divider(height: 1, color: cs.outlineVariant)),
            ],
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
            mainAxisSpacing: 12,
            crossAxisSpacing: 8,
            // Плитка + две строки подписи в 11 пунктов: при 360 dp ячейка
            // выходит 57×93, и подпись помещается целиком.
            childAspectRatio: 0.62,
          ),
          itemCount: section.moods.length,
          itemBuilder: (_, i) {
            final mood = section.moods[i];
            final isSelected = widget.currentEmoji == mood.imagePath;
            return _MoodTile(
              mood: mood,
              isSelected: isSelected,
              primary: widget.primary,
              scheme: cs,
              tileGradient: pack.tileGradient,
              onTap: () {
                HapticFeedback.lightImpact();
                widget.onSelect(mood);
              },
            );
          },
        ),
      ],
    );
  }

  /// Болячки — это подпись с эмодзи, поэтому чипы-строки, а не сетка квадратов
  /// с обрезанными названиями.
  Widget _ailmentList(ColorScheme cs) {
    return SingleChildScrollView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final a in kAilments)
            _AilmentChip(
              ailment: a,
              isSelected: widget.currentAilmentId == a.id,
              scheme: cs,
              onTap: () {
                HapticFeedback.lightImpact();
                widget.onSelectAilment?.call(a);
              },
            ),
        ],
      ),
    );
  }

  Widget _clearButton(AppStrings s, ColorScheme cs, bool onAilment) {
    final onClear = onAilment ? widget.onClearAilment : widget.onClear;
    if (onClear == null) return const SizedBox(height: 16);
    final label = onAilment ? s.clearAilment : s.clearMood;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton(
            onPressed: onClear,
            style: FilledButton.styleFrom(
              backgroundColor: cs.secondaryContainer,
              foregroundColor: cs.onSecondaryContainer,
              shape: const StadiumBorder(),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Text(label),
          ),
        ),
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
  final ColorScheme scheme;

  /// Подложка для паков с прозрачными стикерами (напр. розовый). null —
  /// картинка непрозрачная и заполняет плитку сама (классический пак).
  final List<Color>? tileGradient;
  final VoidCallback onTap;

  const _MoodTile({
    required this.mood,
    required this.isSelected,
    required this.primary,
    required this.scheme,
    required this.onTap,
    this.tileGradient,
  });

  @override
  Widget build(BuildContext context) {
    final sticker = tileGradient != null;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1.0,
            child: LayoutBuilder(
              builder: (context, box) {
                final size = box.maxWidth;
                // Выбор читается формой: мягкий квадрат превращается в
                // волнистую фигуру и чуть подрастает. Цветное свечение прошлой
                // версии выглядело подсветкой, а не отметкой.
                final shape = moodTileShape(selected: isSelected, size: size);
                return AnimatedScale(
                  scale: isSelected ? 1.06 : 1.0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: ClipPath(
                          clipper: ShapeBorderClipper(shape: shape),
                          child: Container(
                            color: sticker
                                ? Color.alphaBlend(
                                    mood.color.withValues(alpha: 0.16),
                                    scheme.surfaceContainerHigh,
                                  )
                                : null,
                            child: mood.imagePath.isEmpty
                                ? Container(color: mood.color)
                                : sticker
                                    ? Padding(
                                        padding: EdgeInsets.all(size * 0.06),
                                        child: MoodImage(
                                          mood.imagePath,
                                          fit: BoxFit.contain,
                                        ),
                                      )
                                    : MoodImage(
                                        mood.imagePath,
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                        height: double.infinity,
                                      ),
                          ),
                        ),
                      ),
                      if (isSelected)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: primary,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.check_rounded,
                              size: 13,
                              color: scheme.onPrimary,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Text(
            mood.localizedLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? primary : scheme.onSurfaceVariant,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Single ailment tile (emoji-based, no asset pipeline)
// ─────────────────────────────────────────────────────────────────────────────

class _AilmentChip extends StatelessWidget {
  final Ailment ailment;
  final bool isSelected;
  final ColorScheme scheme;
  final VoidCallback onTap;

  const _AilmentChip({
    required this.ailment,
    required this.isSelected,
    required this.scheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg =
        isSelected ? scheme.onSecondaryContainer : scheme.onSurface;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? scheme.secondaryContainer : null,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isSelected ? Colors.transparent : scheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(ailment.emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text(
              ailment.localizedLabel,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
