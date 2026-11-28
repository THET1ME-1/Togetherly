import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/dates_text.dart';
import '../../models/date_recurrence.dart';
import '../../models/date_reminder.dart';
import '../../models/pair_date.dart';
import '../../models/symbol_catalog.dart';
import '../../services/device_time_zone.dart';
import '../../services/locale_service.dart';
import '../../services/pair_date_repository.dart';
import '../../services/phone_calendar_sync.dart';
import '../../theme/app_theme.dart';
import '../../theme/fonts.dart';
import '../../theme/profile_theme.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/common/keyboard_aware.dart';
import '../../widgets/dates/phone_calendar_sheet.dart';
import '../../widgets/dates/reminder_sheet.dart';
import '../../widgets/dates/repeat_sheet.dart';
import '../../widgets/memory/form_top_bar.dart';
import '../date_time_picker_screen.dart';
import '../symbol_picker_screen.dart';

/// Частые значки дат на виду, остальные — экраном поиска (4334 символа).
const List<String> kDateQuickSymbols = [
  'favorite',
  'cake',
  'celebration',
  'restaurant',
  'flight',
  'theater_comedy',
  'redeem',
];

/// Новая памятная дата или правка — отдельным экраном, как капсула времени
/// (просьба владельца 28.11.2026: «пусть новая дата будет отдельным экраном,
/// а не попапом»). Макет: https://claude.ai/artifact/A4pbED46avBz9QhigtEX6F.
class DateFormScreen extends StatefulWidget {
  const DateFormScreen({
    super.key,
    required this.theme,
    required this.groupId,
    this.existing,
    this.initialDay,
    this.occurrenceDay,
  });

  final AppTheme theme;
  final String groupId;
  final PairDate? existing;

  /// День, с которого открыли новую дату (клетка календаря).
  final DateTime? initialDay;

  /// Какой повтор открыли: от него считается «только этот день» при удалении.
  final DateTime? occurrenceDay;

  @override
  State<DateFormScreen> createState() => _DateFormScreenState();
}

class _DateFormScreenState extends State<DateFormScreen> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  final _titleFocus = FocusNode();

  late String _symbol;
  late bool _allDay;
  late DateTime _day;
  late int _hour;
  late int _minute;
  late String _rrule;
  late List<int> _reminders;
  bool _titleError = false;
  bool _saving = false;

  // С чем открыли: не тронутые день и время сохраняются как были, вместе с
  // поясом автора, иначе правка названия партнёром в другом поясе сдвинула
  // бы время.
  late final DateTime _initDay;
  late final bool _initAllDay;
  late final int _initHour;
  late final int _initMinute;

  AppTheme get _t => widget.theme;
  ColorScheme get _cs => ProfileTheme.schemeFor(_t);
  PairDate? get _existing => widget.existing;

  @override
  void initState() {
    super.initState();
    final e = _existing;
    final now = DateTime.now();
    _title.text = e?.title ?? '';
    _note.text = e?.note ?? '';
    _symbol = e?.symbol ?? kDateQuickSymbols.first;
    _allDay = e?.allDay ?? true;
    final start = e?.startAt;
    final base = start ?? e?.day ?? widget.initialDay ?? now;
    _day = DateTime(base.year, base.month, base.day);
    _hour = start?.hour ?? 19;
    _minute = start?.minute ?? 0;
    _rrule = e?.rrule ?? '';
    _reminders = e?.reminders.toList() ?? defaultReminders(allDay: true);
    _initDay = _day;
    _initAllDay = _allDay;
    _initHour = _hour;
    _initMinute = _minute;
    // Лист календаря телефона включил или выключил копию — подпись под
    // переключателем меняется сразу.
    PhoneCalendarSync.instance
      ..addListener(_onPhoneSync)
      ..load();
  }

  void _onPhoneSync() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    PhoneCalendarSync.instance.removeListener(_onPhoneSync);
    _title.dispose();
    _note.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  void _hideKeyboard() => FocusManager.instance.primaryFocus?.unfocus();

  String get _timeText => clockText(_hour, _minute);

  /// Ближайшее начало даты по часам телефона — для «придёт 4 декабря в 17:00».
  DateTime get _nextStart {
    final now = DateTime.now();
    final draft = _draft(day: _day, time: _allDay ? null : _timeKey, tz: '');
    final next = draft.nextFrom(now);
    if (next == null) return _allDay ? _day : DateTime(_day.year, _day.month, _day.day, _hour, _minute);
    return next.at ?? next.day;
  }

  String get _timeKey => '${_hour.toString().padLeft(2, '0')}:${_minute.toString().padLeft(2, '0')}';

  PairDate _draft({required DateTime? day, required String? time, required String tz}) => PairDate(
        id: _existing?.id ?? '',
        title: _title.text.trim(),
        symbol: _symbol,
        note: _note.text.trim(),
        day: day,
        time: time,
        tz: tz,
        rrule: _rrule,
        exdates: _existing?.exdates ?? const {},
        reminders: _reminders,
      );

  // ── день, время, повтор ─────────────────────────────────────────────────

  Future<void> _pickDay() async {
    _hideKeyboard();
    final picked = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute<DateTime>(
        builder: (_) => DateTimePickerScreen(
          title: dt('dt.what'),
          theme: _t,
          initial: _day,
          firstYear: 1950,
          lastYear: DateTime.now().year + 30,
          withTime: false,
        ),
        settings: const RouteSettings(name: '/date_picker'),
      ),
    );
    if (picked == null || !mounted) return;
    final day = DateTime(picked.year, picked.month, picked.day);
    setState(() {
      _rrule = _moveRule(_rrule, from: _day, to: day);
      _day = day;
    });
  }

  /// Сменили день: пресет повтора переезжает вместе с ним («каждое
  /// воскресенье» → «каждую среду»), как в Google Календаре. Своё правило
  /// остаётся как было.
  String _moveRule(String rrule, {required DateTime from, required DateTime to}) {
    final kind = presetOf(rrule, from);
    if (kind == RepeatPresetKind.custom || kind == RepeatPresetKind.none) return rrule;
    for (final p in repeatPresets(to)) {
      if (p.kind == kind) return p.rrule;
    }
    // «Последний четверг» на дне не из последней недели — ближайший по смыслу.
    return repeatPresets(to).firstWhere((p) => p.kind == RepeatPresetKind.monthlyDay).rrule;
  }

  Future<void> _pickTime() async {
    _hideKeyboard();
    final picked = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute<DateTime>(
        builder: (_) => DateTimePickerScreen(
          title: dt('dt.time'),
          theme: _t,
          initial: DateTime(_day.year, _day.month, _day.day, _hour, _minute),
          firstYear: _day.year,
          lastYear: _day.year,
          startOnTime: true,
        ),
        settings: const RouteSettings(name: '/date_picker'),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _hour = picked.hour;
      _minute = picked.minute;
    });
  }

  void _toggleAllDay(bool value) {
    HapticFeedback.selectionClick();
    setState(() {
      _reminders = convertReminders(_reminders, toAllDay: value);
      _allDay = value;
    });
  }

  Future<void> _pickRepeat() async {
    _hideKeyboard();
    final rule = await showRepeatSheet(context, theme: _t, start: _day, current: _rrule);
    if (rule == null || !mounted) return;
    setState(() => _rrule = rule);
  }

  // ── напоминания ─────────────────────────────────────────────────────────

  Future<void> _addReminder() async {
    _hideKeyboard();
    if (_reminders.length >= kMaxReminders) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(dt('dt.remLimit'))));
      return;
    }
    final m = await showReminderSheet(
      context,
      theme: _t,
      allDay: _allDay,
      existing: _reminders,
      timeText: _timeText,
      nextStart: _nextStart,
    );
    if (m == null || !mounted) return;
    setState(() => _reminders = normalizeReminders([..._reminders, m]));
  }

  void _removeReminder(int m) {
    HapticFeedback.selectionClick();
    setState(() => _reminders = [..._reminders]..remove(m));
  }

  // ── значок ──────────────────────────────────────────────────────────────

  Future<void> _findSymbol() async {
    _hideKeyboard();
    final picked = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => SymbolPickerScreen(theme: _t, selected: _symbol),
        settings: const RouteSettings(name: '/symbol_picker'),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _symbol = picked);
  }

  // ── сохранение и удаление ───────────────────────────────────────────────

  Future<void> _save() async {
    if (_saving) return;
    if (_title.text.trim().isEmpty) {
      setState(() => _titleError = true);
      _titleFocus.requestFocus();
      return;
    }
    setState(() => _saving = true);
    final untouched = _existing != null &&
        _day == _initDay &&
        _allDay == _initAllDay &&
        (_allDay || (_hour == _initHour && _minute == _initMinute));
    final e = _existing;
    final PairDate draft;
    if (untouched && e != null) {
      draft = _draft(day: e.day, time: e.time, tz: e.tz);
    } else {
      draft = _draft(day: _day, time: _allDay ? null : _timeKey, tz: await deviceTimeZone() ?? '');
    }
    final repo = PairDateRepository.instance;
    if (e == null) {
      await repo.create(widget.groupId, draft);
    } else {
      await repo.save(
        widget.groupId,
        e.copyWith(
          title: draft.title,
          symbol: draft.symbol,
          note: draft.note,
          day: draft.day,
          time: () => draft.time,
          tz: draft.tz,
          rrule: draft.rrule,
          reminders: draft.reminders,
        ),
      );
    }
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    _hideKeyboard();
    final e = _existing;
    if (e == null) return;
    final occ = widget.occurrenceDay;
    final choice = await showAppSheet<String>(
      context,
      background: _cs.surfaceContainerLow,
      builder: (ctx) => Theme(
        data: ProfileTheme.data(_cs),
        child: SheetScaffold(
          title: dt('dt.deleteAsk'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (e.repeats && occ != null) ...[
                  _deleteButton(ctx, 'one', dt('dt.deleteOne'), tonal: true),
                  const SizedBox(height: 8),
                  _deleteButton(ctx, 'following', dt('dt.deleteFollowing'), tonal: true),
                  const SizedBox(height: 8),
                  _deleteButton(ctx, 'all', dt('dt.deleteAll')),
                ] else
                  _deleteButton(ctx, 'all', dt('dt.delete')),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  child: Text(dt('dt.cancel')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final repo = PairDateRepository.instance;
    switch (choice) {
      case 'one':
        await repo.save(widget.groupId, e.skipping(occ!));
      case 'following':
        final cut = e.endingBefore(occ!);
        cut == null ? await repo.remove(e.id) : await repo.save(widget.groupId, cut);
      default:
        await repo.remove(e.id);
    }
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Widget _deleteButton(BuildContext ctx, String value, String label, {bool tonal = false}) {
    final style = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      backgroundColor: tonal ? _cs.errorContainer : _cs.error,
      foregroundColor: tonal ? _cs.onErrorContainer : _cs.onError,
    );
    return FilledButton(
      key: ValueKey('date-delete-$value'),
      onPressed: () => Navigator.pop(ctx, value),
      style: style,
      child: Text(label),
    );
  }

  // ── экран ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = _cs;
    final media = MediaQuery.of(context);
    final typing = keyboardOpen(context);
    return Theme(
      data: ProfileTheme.data(cs),
      child: Scaffold(
        backgroundColor: cs.surface,
        body: Stack(
          children: [
            Column(
              children: [
                SizedBox(height: media.padding.top + 8),
                FormTopBar(
                  scheme: cs,
                  dot: _t.fillColor,
                  label: _existing == null ? dt('dt.new') : dt('dt.editTitle'),
                  onClose: () => Navigator.pop(context),
                  trailing: typing
                      ? FilledButton.tonal(
                          key: const ValueKey('date-form-done'),
                          onPressed: _hideKeyboard,
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                          child: Text(dt('dt.done')),
                        )
                      : (_existing == null
                          ? null
                          : IconButton.filledTonal(
                              key: const ValueKey('date-form-delete'),
                              tooltip: dt('dt.delete'),
                              onPressed: _delete,
                              style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                              icon: const Icon(Icons.delete_outline_rounded),
                            )),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(12, 6, 12, 108 + media.padding.bottom),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _titleCard(cs),
                        const SizedBox(height: 12),
                        _whenCard(cs),
                        const SizedBox(height: 12),
                        _remindersCard(cs),
                        const SizedBox(height: 12),
                        _noteCard(cs),
                        const SizedBox(height: 12),
                        _phoneCard(cs),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 12, 10, 0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.group_rounded, size: 18, color: cs.onSurfaceVariant),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  dt('dt.shared'),
                                  style: AppFonts.onest(size: 13, height: 1.35, color: cs.onSurfaceVariant),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (!typing)
              Positioned(
                left: 12,
                right: 12,
                bottom: media.padding.bottom + 12,
                child: FilledButton(
                  key: const ValueKey('date-form-save'),
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    textStyle: AppFonts.onest(size: 16, weight: 700),
                  ),
                  child: Text(dt('dt.save')),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _titleCard(ColorScheme cs) {
    final fg = cs.onTertiaryContainer;
    final shown = kDateQuickSymbols.contains(_symbol)
        ? kDateQuickSymbols
        : [_symbol, ...kDateQuickSymbols.take(kDateQuickSymbols.length - 1)];
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(28)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(dt('dt.what'), style: AppFonts.onest(size: 13, weight: 700, color: fg)),
          TextField(
            key: const ValueKey('date-form-title'),
            controller: _title,
            focusNode: _titleFocus,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 80,
            onChanged: (_) {
              if (_titleError) setState(() => _titleError = false);
            },
            onTapOutside: (_) => _hideKeyboard(),
            style: AppFonts.unbounded(size: 22, weight: 700, letterSpacing: -0.4, color: cs.onSurface),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              counterText: '',
              hintText: dt('dt.titleHint'),
              hintMaxLines: 2,
              hintStyle: AppFonts.onest(size: 18, weight: 600, color: fg.withValues(alpha: 0.55)),
              errorText: _titleError ? dt('dt.titleEmpty') : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 6),
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, box) {
              const count = 8;
              final size = ((box.maxWidth - (count - 1) * 4) / count).clamp(30.0, 40.0);
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final name in shown)
                    _symbolCircle(
                      cs,
                      size: size,
                      selected: name == _symbol,
                      child: SymbolIcon(name, size: size * 0.52, color: name == _symbol ? cs.tertiaryContainer : fg),
                      onTap: () => setState(() => _symbol = name),
                      key: ValueKey('date-symbol-$name'),
                    ),
                  _symbolCircle(
                    cs,
                    size: size,
                    selected: false,
                    outlined: true,
                    tooltip: dt('dt.findIcon'),
                    child: Icon(Icons.search_rounded, size: size * 0.52, color: fg),
                    onTap: _findSymbol,
                    key: const ValueKey('date-symbol-search'),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _symbolCircle(
    ColorScheme cs, {
    required double size,
    required bool selected,
    required Widget child,
    required VoidCallback onTap,
    bool outlined = false,
    String? tooltip,
    Key? key,
  }) {
    final fg = cs.onTertiaryContainer;
    final circle = Material(
      key: key,
      color: selected ? fg : (outlined ? Colors.transparent : fg.withValues(alpha: 0.12)),
      shape: CircleBorder(side: outlined ? BorderSide(color: fg, width: 1.5) : BorderSide.none),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: SizedBox(width: size, height: size, child: Center(child: child)),
      ),
    );
    return Semantics(
      selected: selected,
      button: true,
      child: tooltip == null ? circle : Tooltip(message: tooltip, child: circle),
    );
  }

  Widget _card(ColorScheme cs, List<Widget> children) => Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(28)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  Widget _row(
    ColorScheme cs, {
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    Key? key,
  }) {
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 12, 8),
        child: Row(
          children: [
            Icon(icon, size: 22, color: cs.onSurfaceVariant),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: AppFonts.onest(size: 16, weight: 600, color: cs.onSurface)),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: AppFonts.onest(size: 13, color: cs.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
    return onTap == null ? KeyedSubtree(key: key, child: content) : InkWell(key: key, onTap: onTap, child: content);
  }

  Widget _whenCard(ColorScheme cs) {
    final s = LocaleService.current;
    final (main, detail) = repeatText(_rrule, _day);
    return _card(cs, [
      _row(
        cs,
        key: const ValueKey('date-form-all-day'),
        icon: Icons.schedule_rounded,
        title: dt('dt.allDay'),
        onTap: () => _toggleAllDay(!_allDay),
        trailing: Switch(value: _allDay, onChanged: _toggleAllDay),
      ),
      _row(
        cs,
        key: const ValueKey('date-form-day'),
        icon: Icons.calendar_month_rounded,
        title: '${s.shortWeekdays[_day.weekday - 1]}, ${s.dayLogDate(_day)} ${_day.year}',
        onTap: _pickDay,
        trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
      ),
      if (!_allDay)
        _row(
          cs,
          key: const ValueKey('date-form-time'),
          icon: Icons.access_time_rounded,
          title: _timeText,
          onTap: _pickTime,
          trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        child: Divider(height: 1, color: cs.outlineVariant),
      ),
      _row(
        cs,
        key: const ValueKey('date-form-repeat'),
        icon: Icons.repeat_rounded,
        title: main,
        subtitle: detail,
        onTap: _pickRepeat,
        trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
      ),
    ]);
  }

  Widget _remindersCard(ColorScheme cs) {
    return _card(cs, [
      for (final m in _reminders)
        _row(
          cs,
          key: ValueKey('date-form-reminder-$m'),
          icon: Icons.notifications_rounded,
          title: reminderText(m, allDay: _allDay),
          trailing: IconButton(
            tooltip: dt('dt.removeReminder'),
            visualDensity: VisualDensity.compact,
            onPressed: () => _removeReminder(m),
            icon: Icon(Icons.close_rounded, size: 20, color: cs.onSurfaceVariant),
          ),
        ),
      if (_reminders.length < kMaxReminders)
        InkWell(
          key: const ValueKey('date-form-add-reminder'),
          onTap: _addReminder,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 12, 8),
              child: Row(
                children: [
                  Icon(Icons.add_rounded, size: 22, color: cs.primary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(dt('dt.addReminder'), style: AppFonts.onest(size: 16, weight: 700, color: cs.onSurface)),
                  ),
                ],
              ),
            ),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(54, 0, 18, 8),
        child: Text(
          _reminders.isEmpty ? dt('dt.noReminders') : dt('dt.remindBoth'),
          style: AppFonts.onest(size: 13, color: cs.onSurfaceVariant),
        ),
      ),
    ]);
  }

  Widget _noteCard(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
      decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(28)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Icon(Icons.notes_rounded, size: 22, color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              key: const ValueKey('date-form-note'),
              controller: _note,
              minLines: 1,
              maxLines: 5,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
              onTapOutside: (_) => _hideKeyboard(),
              style: AppFonts.onest(size: 16, color: cs.onSurface),
              decoration: InputDecoration(
                border: InputBorder.none,
                counterText: '',
                hintText: dt('dt.noteHint'),
                hintStyle: AppFonts.onest(size: 16, color: cs.onSurfaceVariant.withValues(alpha: 0.8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _phoneCard(ColorScheme cs) {
    final sync = PhoneCalendarSync.instance;
    void open() => showPhoneCalendarSheet(context, theme: _t);
    return Container(
      decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: _row(
          cs,
          key: const ValueKey('date-form-phone'),
          icon: Icons.event_available_rounded,
          title: dt('dt.phone'),
          subtitle: sync.enabled ? sync.calendarLabel : dt('dt.phoneOff'),
          onTap: open,
          trailing: Switch(value: sync.enabled, onChanged: (_) => open()),
        ),
      ),
    );
  }
}

