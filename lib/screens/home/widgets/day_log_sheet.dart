import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/cycle_entry.dart';
import '../../../models/pair_data.dart';
import '../../../models/user_data.dart';
import '../../../services/cycle_service.dart';
import '../../../services/locale_service.dart';
import '../../../services/mood_service.dart';
import '../../../services/plus_access.dart';
import '../../../services/plus_service.dart';
import '../../../services/widget_service.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/profile_theme.dart';
import '../../../widgets/app_sheet.dart';
import '../../plus_screen.dart';
import 'mood_picker_dialog.dart';

/// Лист дня календаря: настроение, самочувствие и цикл в одном месте.
///
/// Раньше цикл жил отдельным экраном за двумя настройками, и отметить месячные
/// рядом с настроением было нельзя. Теперь тап по дню открывает один лист, а
/// цикл — второй лист поверх него. Отдельный экран цикла остался под прогноз и
/// статистику, отмечать там больше нечего.
Future<void> showDayLogSheet({
  required BuildContext context,
  required DateTime day,
  required PairData pairData,
  required MoodService moodService,
  required WidgetService widgetService,
  required AppTheme theme,
  UserData? userData,
}) {
  final scheme = ProfileTheme.schemeFor(theme);
  return showAppSheet<void>(
    context,
    background: scheme.surfaceContainerLow,
    builder: (ctx) => Theme(
      data: ProfileTheme.data(scheme),
      child: _DayLogSheet(
        day: day,
        pairData: pairData,
        moodService: moodService,
        widgetService: widgetService,
        theme: theme,
        scheme: scheme,
        userData: userData,
      ),
    ),
  );
}

/// Лист «Цикл» сам по себе: менструация и секс на конкретный день.
///
/// Единственное место, где ставится отметка цикла, — сюда ведут и лист дня в
/// календаре настроений, и календарь на экране цикла.
Future<void> showCycleDaySheet({
  required BuildContext context,
  required DateTime day,
  required ColorScheme scheme,
}) {
  return showAppSheet<void>(
    context,
    background: scheme.surfaceContainerLow,
    builder: (ctx) => Theme(
      data: ProfileTheme.data(scheme),
      child: _CycleDaySheet(
        day: DateTime(day.year, day.month, day.day),
        scheme: scheme,
      ),
    ),
  );
}

class _DayLogSheet extends StatefulWidget {
  const _DayLogSheet({
    required this.day,
    required this.pairData,
    required this.moodService,
    required this.widgetService,
    required this.theme,
    required this.scheme,
    required this.userData,
  });

  final DateTime day;
  final PairData pairData;
  final MoodService moodService;
  final WidgetService widgetService;
  final AppTheme theme;
  final ColorScheme scheme;
  final UserData? userData;

  @override
  State<_DayLogSheet> createState() => _DayLogSheetState();
}

class _DayLogSheetState extends State<_DayLogSheet> {
  final CycleService _cycle = CycleService.instance;

  @override
  void initState() {
    super.initState();
    _cycle.addListener(_onChanged);
    widget.moodService.addListener(_onChanged);
    widget.pairData.addListener(_onChanged);
  }

  @override
  void dispose() {
    _cycle.removeListener(_onChanged);
    widget.moodService.removeListener(_onChanged);
    widget.pairData.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  AppStrings get _s => LocaleService.current;
  ColorScheme get _cs => widget.scheme;

  bool get _isToday {
    final now = DateTime.now();
    return now.year == widget.day.year &&
        now.month == widget.day.month &&
        now.day == widget.day.day;
  }

  // ── подписи состояний ────────────────────────────────────────────────────

  String get _moodValue {
    final entries = widget.moodService.myEntriesForDay(widget.day);
    if (entries.isEmpty) return _s.dayLogNotMarked;
    final latest = entries.reduce(
        (a, b) => a.timestamp.isAfter(b.timestamp) ? a : b);
    final hh = latest.timestamp.hour.toString().padLeft(2, '0');
    final mm = latest.timestamp.minute.toString().padLeft(2, '0');
    return '${latest.localizedLabel} · $hh:$mm';
  }

  String get _ailmentValue {
    if (!_isToday) return _s.dayLogTodayOnly;
    final a = widget.pairData.myAilment;
    return a.isNotEmpty ? a.label : _s.dayLogNotMarked;
  }

  String get _cycleValue {
    final periodDay = _cycle.periodDayIndex(widget.day);
    final sex = _cycle.myEntryOn(widget.day, CycleKind.intimacy) != null;
    if (periodDay != null && sex) {
      return '${_s.cyclePeriodDayLabel(periodDay)} · ${_s.cycleSexMarked}';
    }
    if (periodDay != null) return _s.cyclePeriodDayLabel(periodDay);
    if (sex) return _s.cycleSexMarked;
    return _s.dayLogNotMarked;
  }

  // ── действия ─────────────────────────────────────────────────────────────

  void _openMood() {
    // Контекст навигатора переживает закрытие листа; собственный контекст после
    // pop уже мёртв, и следующий лист на нём открыть нельзя.
    final host = Navigator.of(context).context;
    Navigator.pop(context);
    showMoodPickerForDate(
      context: host,
      date: widget.day,
      pairData: widget.pairData,
      moodService: widget.moodService,
      widgetService: widget.widgetService,
      primary: widget.theme.primary,
      navActiveIcon: widget.theme.navActiveIcon,
      withAilmentTab: false,
    );
  }

  void _openAilment() {
    final host = Navigator.of(context).context;
    Navigator.pop(context);
    showAilmentPicker(
      context: host,
      pairData: widget.pairData,
      primary: widget.theme.primary,
    );
  }

  void _openCycle() {
    switch (PlusService.instance.gate) {
      // Платформа без Togetherly+ (iOS): строки цикла тут и не должно быть,
      // вести некуда.
      case PlusGate.hidden:
        return;
      // Без покупки отмечать нечего — ведём туда, где Плюс покупают.
      case PlusGate.locked:
        final nav = Navigator.of(context);
        nav.pop();
        nav.push(
          MaterialPageRoute<void>(builder: (_) => PlusScreen(scheme: _cs)),
        );
        return;
      case PlusGate.open:
        showCycleDaySheet(context: context, day: widget.day, scheme: _cs);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showCycle = CycleService.availableFor(widget.userData);
    return SheetScaffold(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _s.dayLogDate(widget.day),
                  style: TextStyle(
                    fontFamily: 'Unbounded',
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    fontVariations: const [FontVariation('wght', 700)],
                    letterSpacing: -0.4,
                    color: _cs.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_s.dayLogWeekday(widget.day)} · ${_s.dayLogWhat}',
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 13.5,
                    color: _cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _LogCard(
            icon: Icons.sentiment_satisfied_rounded,
            title: _s.moodTabLabel,
            value: _moodValue,
            background: _cs.primaryContainer,
            foreground: _cs.onPrimaryContainer,
            onTap: _openMood,
          ),
          _LogCard(
            icon: Icons.monitor_heart_rounded,
            title: _s.ailmentTabLabel,
            value: _ailmentValue,
            background: _cs.secondaryContainer,
            foreground: _cs.onSecondaryContainer,
            enabled: _isToday,
            onTap: _openAilment,
          ),
          if (showCycle)
            _LogCard(
              icon: Icons.autorenew_rounded,
              title: _s.cycleTitle,
              value: _cycleValue,
              background: _cs.errorContainer,
              foreground: _cs.onErrorContainer,
              onTap: _openCycle,
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Лист «Цикл»: менструация и секс
// ─────────────────────────────────────────────────────────────────────────────

class _CycleDaySheet extends StatefulWidget {
  const _CycleDaySheet({required this.day, required this.scheme});

  final DateTime day;
  final ColorScheme scheme;

  @override
  State<_CycleDaySheet> createState() => _CycleDaySheetState();
}

class _CycleDaySheetState extends State<_CycleDaySheet> {
  final CycleService _cycle = CycleService.instance;

  @override
  void initState() {
    super.initState();
    _cycle.addListener(_onChanged);
  }

  @override
  void dispose() {
    _cycle.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  AppStrings get _s => LocaleService.current;
  ColorScheme get _cs => widget.scheme;

  Future<void> _toggle(CycleKind kind) async {
    HapticFeedback.selectionClick();
    await _cycle.toggle(widget.day, kind);
  }

  @override
  Widget build(BuildContext context) {
    final period = _cycle.myEntryOn(widget.day, CycleKind.period) != null;
    final sex = _cycle.myEntryOn(widget.day, CycleKind.intimacy) != null;
    // Красный месячных — тот же, что на экране цикла: иносказания тут мешают.
    const periodColor = Color(0xFFD32F2F);

    return SheetScaffold(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 24, 0),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.pop(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.chevron_left_rounded,
                        size: 20, color: _cs.onSurfaceVariant),
                    const SizedBox(width: 2),
                    Text(
                      _s.dayLogDate(widget.day),
                      style: TextStyle(
                        fontFamily: 'Onest',
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: _cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 6, 24, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _s.cycleTitle,
                  style: TextStyle(
                    fontFamily: 'Unbounded',
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    fontVariations: const [FontVariation('wght', 700)],
                    letterSpacing: -0.4,
                    color: _cs.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _s.cycleSheetHint,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 13.5,
                    color: _cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _LogCard(
            icon: Icons.water_drop_rounded,
            title: _s.cycleMarkPeriod,
            value: _s.cycleMarkPeriodHint,
            background: _fill(period, _cs.errorContainer),
            foreground: period ? _cs.onErrorContainer : _cs.onSurfaceVariant,
            checked: period,
            checkColor: periodColor,
            onTap: () => _toggle(CycleKind.period),
          ),
          _LogCard(
            icon: Icons.favorite_rounded,
            title: _s.cycleMarkIntimacy,
            value: _s.cycleMarkIntimacyHint,
            background: _fill(sex, _cs.primaryContainer),
            foreground: sex ? _cs.onPrimaryContainer : _cs.onSurfaceVariant,
            checked: sex,
            checkColor: _cs.primary,
            onTap: () => _toggle(CycleKind.intimacy),
          ),
        ],
      ),
    );
  }

  /// Снятая отметка остаётся серой — цвет говорит о состоянии, а не о разделе.
  Color _fill(bool on, Color active) =>
      on ? active : _cs.surfaceContainerHighest;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Карточка пункта
// ─────────────────────────────────────────────────────────────────────────────

class _LogCard extends StatelessWidget {
  const _LogCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.background,
    required this.foreground,
    required this.onTap,
    this.enabled = true,
    this.checked,
    this.checkColor,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;
  final bool enabled;

  /// null — справа стрелка «дальше»; иначе кружок с состоянием отметки.
  final bool? checked;
  final Color? checkColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: foreground.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 26, color: foreground),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    fontVariations: const [FontVariation('wght', 700)],
                    letterSpacing: -0.2,
                    color: foreground,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 13.5,
                    color: foreground.withValues(alpha: 0.78),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (checked == null)
            Icon(Icons.chevron_right_rounded,
                size: 22, color: foreground.withValues(alpha: 0.7))
          else
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: checked!
                    ? (checkColor ?? scheme.primary)
                    : scheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_rounded,
                size: 18,
                color: checked!
                    ? Colors.white
                    : scheme.onSurfaceVariant.withValues(alpha: 0.55),
              ),
            ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        // Заливка отдаётся Material, а не Container: иначе фон карточки
        // перекрывает рябь нажатия и пункт кажется мёртвым.
        child: Material(
          color: background,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: content,
          ),
        ),
      ),
    );
  }
}
