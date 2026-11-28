import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/mood_entry.dart' show MoodEntry, MoodGenders;
import '../../../widgets/mood/day_mood_lanes.dart';
import '../../../models/cycle_entry.dart';
import '../../../models/pair_data.dart';
import '../../../models/user_data.dart';
import '../../../services/cycle_gate.dart';
import '../../../services/cycle_service.dart';
import 'cycle_consent_sheet.dart';
import '../../../services/locale_service.dart';
import '../../../services/mood_service.dart';
import '../../../services/plus_service.dart';
import '../../../services/widget_service.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/profile_theme.dart';
import '../../../widgets/app_sheet.dart';
import '../../../l10n/dates_text.dart';
import '../../../models/pair_date.dart';
import '../../../models/symbol_catalog.dart';
import '../../../services/pair_dates_service.dart';
import '../../../theme/fonts.dart';
import '../../dates/date_form_screen.dart';
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
    PairDatesService.instance.addListener(_onChanged);
  }

  @override
  void dispose() {
    _cycle.removeListener(_onChanged);
    widget.moodService.removeListener(_onChanged);
    widget.pairData.removeListener(_onChanged);
    PairDatesService.instance.removeListener(_onChanged);
    super.dispose();
  }

  bool get _isFuture {
    final now = DateTime.now();
    return widget.day.isAfter(DateTime(now.year, now.month, now.day));
  }

  /// Наши даты в этот день (TOG-61): свои и готовые.
  List<DateOccurrence> get _dates {
    if (!widget.pairData.isPaired) return const [];
    final all = PairDatesService.instance.allFor(widget.pairData, myUid: widget.userData?.uid ?? '');
    return [for (final d in all) ...d.occurrencesBetween(widget.day, widget.day)];
  }

  /// Открыть дату или новую дату на этот день — отдельным экраном поверх
  /// календаря, лист закрывается.
  void _openDate([DateOccurrence? o]) {
    if (o != null && o.date.isAuto) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(dt('dt.autoHint'))));
      return;
    }
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(MaterialPageRoute<bool>(
      builder: (_) => DateFormScreen(
        theme: widget.theme,
        groupId: widget.pairData.pairId,
        existing: o?.date,
        initialDay: widget.day,
        occurrenceDay: o?.day,
      ),
      settings: const RouteSettings(name: '/date_form'),
    ));
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
    return '${latest.labelFor(MoodGenders.mine)} · $hh:$mm';
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
      user: widget.userData,
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

  Future<void> _openCycle() async {
    final plus = PlusService.instance;
    // Флаг покупки читается с сервера, и до ответа гейт говорит «не куплено» о
    // том, кто заплатил. Ждём ответа, прежде чем предлагать покупку: иначе
    // купившая попадает на витрину вместо своих отметок и видит там «Плюс ваш»
    // (жалобы 01.09.2026). Предел небольшой — ответ обычно приходит мгновенно
    // из локальной копии, а сеть ждать человеку незачем.
    if (!plus.known) {
      try {
        await plus.ensureLoaded().timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('day_log_sheet: флаг Плюса не пришёл — $e');
      }
      if (!mounted) return;
    }
    switch (cycleTapAction(gate: plus.gate, known: plus.known)) {
      // Платформа без Togetherly+ (iOS): строки цикла тут и не должно быть,
      // вести некуда.
      case CycleTap.nothing:
        return;
      // Ответа так и нет: молчим. Увести на витрину купившую хуже, чем не
      // среагировать на касание — второе она повторит, первое собьёт с толку.
      case CycleTap.wait:
        return;
      // Без покупки отмечать нечего — ведём туда, где Плюс покупают.
      case CycleTap.offer:
        final nav = Navigator.of(context);
        nav.pop();
        nav.push(
          MaterialPageRoute<void>(builder: (_) => PlusScreen(scheme: _cs)),
        );
        return;
      case CycleTap.open:
        showCycleDaySheet(context: context, day: widget.day, scheme: _cs);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showCycle = CycleService.availableFor(widget.userData);
    final lanes = _lanes();
    final future = _isFuture;
    final paired = widget.pairData.isPaired;
    final dates = _dates;
    final event = paired
        ? _EventCard(
            scheme: _cs,
            dates: dates,
            line: (o) => [
              if (o.date.repeats && !o.date.isAuto) repeatLine(o.date.rrule, o.date.day!),
              occurrenceLine(
                o,
                myUid: widget.userData?.uid ?? '',
                partnerName: widget.pairData.partnerDisplayName,
                partnerGender: widget.widgetService.firstPartnerData?.gender ?? '',
                withDate: false,
              ),
            ].where((t) => t.isNotEmpty).join(' · '),
            onAdd: () => _openDate(),
            onOpen: _openDate,
          )
        : null;
    // Прокрутка нужна дорожкам: день с десятком смен настроения выше экрана.
    return SheetScaffold(
      child: SingleChildScrollView(
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
                    future
                        ? '${_s.dayLogWeekday(widget.day)} · ${untilText(daysBetween(DateTime.now(), widget.day))}'
                        : '${_s.dayLogWeekday(widget.day)} · ${_s.dayLogWhat}',
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
            if (lanes != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: lanes,
              ),
            // Будущий день открывают ради даты — она первой.
            if (future && event != null) event,
            _LogCard(
              icon: Icons.sentiment_satisfied_rounded,
              title: _s.moodTabLabel,
              value: future ? dt('dt.moodLater') : _moodValue,
              background: _cs.primaryContainer,
              foreground: _cs.onPrimaryContainer,
              enabled: !future,
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
                enabled: !future,
                onTap: _openCycle,
              ),
            if (!future && event != null) event,
          ],
        ),
      ),
    );
  }

  /// История дня двумя дорожками: вы и партнёр. Нет отметок ни у кого —
  /// блока нет, лист выглядит как раньше.
  Widget? _lanes() {
    final pair = widget.pairData;
    final mine = widget.moodService.myEntriesForDay(widget.day);
    final theirs = pair.partnerUid.isEmpty
        ? const <MoodEntry>[]
        : widget.moodService.partnerEntriesForDay(pair.partnerUid, widget.day);
    if (mine.isEmpty && theirs.isEmpty) return null;
    return DayMoodLanes(
      mine: mine,
      theirs: theirs,
      myName: widget.userData?.displayName ?? '',
      partnerName: pair.partnerDisplayName,
      myUid: widget.userData?.uid ?? '',
      partnerUid: pair.partnerUid,
      myAvatarUrl: widget.userData?.avatarUrl,
      partnerAvatarUrl: pair.partnerAvatarUrl,
      myGender: MoodGenders.mine,
      partnerGender: widget.widgetService.firstPartnerData?.gender ?? '',
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
    // Отметки цикла — данные о здоровье, особая категория и по закону
    // Молдовы № 133/2011, и по GDPR. Общего «принимаю политику» при
    // регистрации для них мало: спрашиваем отдельно и ровно один раз, перед
    // первой отметкой.
    if (!_cycle.consentGranted) {
      final agreed = await showCycleConsentSheet(context, scheme: _cs);
      if (agreed != true) return;
      await _cycle.grantConsent();
      if (!mounted) return;
    }
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

// ─────────────────────────────────────────────────────────────────────────────
//  «Событие»: наши даты этого дня (TOG-61)
// ─────────────────────────────────────────────────────────────────────────────

/// Пункт листа дня с датами: пусто — «Отметить памятную дату» и «+»; есть
/// даты — их строки внутри карточки, касание открывает дату.
class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.scheme,
    required this.dates,
    required this.line,
    required this.onAdd,
    required this.onOpen,
  });

  final ColorScheme scheme;
  final List<DateOccurrence> dates;
  final String Function(DateOccurrence) line;
  final VoidCallback onAdd;
  final ValueChanged<DateOccurrence> onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = scheme;
    final fg = cs.onTertiaryContainer;
    final header = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: fg.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: Icon(Icons.event_rounded, size: 26, color: fg),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(dt('dt.event'), style: AppFonts.onest(size: 18, weight: 700, letterSpacing: -0.2, color: fg)),
                const SizedBox(height: 3),
                Text(
                  dates.isEmpty ? dt('dt.eventEmpty') : dtCount('dt.eventCount', dates.length),
                  style: AppFonts.onest(size: 13.5, color: fg.withValues(alpha: 0.78)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: dt('dt.add'),
            child: Material(
              color: fg,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const ValueKey('day-log-add-date'),
                onTap: onAdd,
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(Icons.add_rounded, size: 22, color: cs.tertiaryContainer),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        key: const ValueKey('day-log-event'),
        color: cs.tertiaryContainer,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Column(
          children: [
            // Пустой пункт целиком — «добавить», как остальные строки листа.
            dates.isEmpty ? InkWell(onTap: onAdd, child: header) : header,
            for (final o in dates)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Material(
                  color: cs.surface.withValues(alpha: 0.55),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: ValueKey('day-log-date-${o.date.id}'),
                    onTap: () => onOpen(o),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(color: fg, borderRadius: BorderRadius.circular(14)),
                            child: Center(child: SymbolIcon(o.date.symbol, size: 22, color: cs.tertiaryContainer)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  dateTitle(o.date, o.day),
                                  style: AppFonts.onest(size: 16, weight: 700, color: cs.onSurface),
                                ),
                                if (line(o).isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(line(o), style: AppFonts.onest(size: 13, color: cs.onSurfaceVariant)),
                                ],
                              ],
                            ),
                          ),
                          Icon(
                            o.date.isAuto ? Icons.info_outline_rounded : Icons.edit_rounded,
                            size: 20,
                            color: cs.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
