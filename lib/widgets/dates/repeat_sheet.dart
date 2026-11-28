import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/dates_text.dart';
import '../../models/date_recurrence.dart';
import '../../screens/date_time_picker_screen.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/fonts.dart';
import '../../theme/profile_theme.dart';
import '../app_sheet.dart';
import 'date_controls.dart';

/// Лист «Повтор»: пресеты, как в Google Календаре, от дня начала. Своё
/// правило, не совпавшее с пресетом, стоит отмеченной строкой с полным
/// описанием. Возвращает новое правило (пусто — без повтора) или null, если
/// лист закрыли.
Future<String?> showRepeatSheet(
  BuildContext context, {
  required AppTheme theme,
  required DateTime start,
  required String current,
}) {
  final cs = ProfileTheme.schemeFor(theme);
  return showAppSheet<String>(
    context,
    background: cs.surfaceContainerLow,
    builder: (_) => Theme(
      data: ProfileTheme.data(cs),
      child: _RepeatSheet(theme: theme, scheme: cs, start: start, current: current),
    ),
  );
}

class _RepeatSheet extends StatelessWidget {
  const _RepeatSheet({required this.theme, required this.scheme, required this.start, required this.current});

  final AppTheme theme;
  final ColorScheme scheme;
  final DateTime start;
  final String current;

  @override
  Widget build(BuildContext context) {
    final kind = presetOf(current, start);
    return SheetScaffold(
      title: dt('dt.repeat'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final p in repeatPresets(start))
              PresetRow(
                key: ValueKey('repeat-${p.kind.name}'),
                scheme: scheme,
                text: repeatText(p.rrule, start),
                checked: p.kind == kind,
                onTap: () => Navigator.pop(context, p.rrule),
              ),
            if (kind == RepeatPresetKind.custom)
              PresetRow(
                key: const ValueKey('repeat-current-custom'),
                scheme: scheme,
                text: repeatText(current, start),
                checked: true,
                onTap: () => Navigator.pop(context, current),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              child: Divider(height: 1, color: scheme.outlineVariant),
            ),
            PresetRow(
              key: const ValueKey('repeat-custom'),
              scheme: scheme,
              icon: Icons.tune_rounded,
              text: (dt('dt.rCustom'), ''),
              checked: false,
              onTap: () async {
                final rule = await showCustomRepeatSheet(context, theme: theme, start: start, current: current);
                if (rule != null && context.mounted) Navigator.pop(context, rule);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Строка листа пресетов: галочка, главное и уточнение серым рядом.
class PresetRow extends StatelessWidget {
  const PresetRow({
    super.key,
    required this.scheme,
    required this.text,
    required this.checked,
    required this.onTap,
    this.icon,
    this.enabled = true,
  });

  final ColorScheme scheme;
  final (String, String) text;
  final bool checked;
  final VoidCallback onTap;
  final IconData? icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cs = scheme;
    final (main, detail) = text;
    return Semantics(
      selected: checked,
      button: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Material(
          color: checked && enabled ? cs.primaryContainer : Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled
                ? () {
                    HapticFeedback.selectionClick();
                    onTap();
                  }
                : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: icon != null
                          ? Icon(icon, size: 22, color: cs.onSurfaceVariant)
                          : (checked ? Icon(Icons.check_rounded, size: 22, color: cs.primary) : null),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(
                            text: main,
                            style: AppFonts.onest(size: 16, weight: checked ? 700 : 600, color: cs.onSurface),
                          ),
                          if (detail.isNotEmpty)
                            TextSpan(
                              text: '  $detail',
                              style: AppFonts.onest(size: 13, weight: 500, color: cs.onSurfaceVariant),
                            ),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Лист «Свой повтор»: «Раз в N [дней | недель | месяцев | лет]», дни недели,
/// день месяца, окончание. Сверху живое описание правила.
Future<String?> showCustomRepeatSheet(
  BuildContext context, {
  required AppTheme theme,
  required DateTime start,
  required String current,
}) {
  final cs = ProfileTheme.schemeFor(theme);
  return showAppSheet<String>(
    context,
    background: cs.surfaceContainerLow,
    builder: (_) => Theme(
      data: ProfileTheme.data(cs),
      child: CustomRepeatSheet(theme: theme, scheme: cs, start: start, current: current),
    ),
  );
}

enum _MonthMode { day, nth, last }

enum _EndMode { never, until, count }

class CustomRepeatSheet extends StatefulWidget {
  const CustomRepeatSheet({
    super.key,
    required this.theme,
    required this.scheme,
    required this.start,
    required this.current,
  });

  final AppTheme theme;
  final ColorScheme scheme;
  final DateTime start;
  final String current;

  @override
  State<CustomRepeatSheet> createState() => _CustomRepeatSheetState();
}

class _CustomRepeatSheetState extends State<CustomRepeatSheet> {
  late RepeatFreq _freq;
  late int _interval;
  late Set<int> _weekdays;
  late _MonthMode _month;
  late _EndMode _end;
  late DateTime _until;
  late int _count;

  ColorScheme get _cs => widget.scheme;
  DateTime get _start => widget.start;

  /// Номер недели дня начала в месяце (1–5) и последняя ли это неделя.
  int get _nth => (_start.day - 1) ~/ 7 + 1;
  bool get _isLast => _start.day + 7 > daysInMonth(_start.year, _start.month);

  @override
  void initState() {
    super.initState();
    final rule = Recurrence.parse(widget.current, _start);
    _freq = rule?.freq ?? RepeatFreq.weekly;
    _interval = rule?.interval ?? 1;
    _weekdays = {...?rule?.weekdays};
    if (_weekdays.isEmpty) _weekdays = {_start.weekday};
    _month = rule?.monthNth == null
        ? _MonthMode.day
        : (rule!.monthNth! < 0 ? _MonthMode.last : _MonthMode.nth);
    if (_month == _MonthMode.nth && _nth > 4) _month = _MonthMode.day;
    if (_month == _MonthMode.last && !_isLast) _month = _MonthMode.day;
    _end = rule?.until != null
        ? _EndMode.until
        : (rule?.count != null ? _EndMode.count : _EndMode.never);
    _until = rule?.until ?? DateTime(_start.year, _start.month + 3, _start.day);
    _count = rule?.count ?? 10;
  }

  Recurrence get _rule {
    final monthly = _freq == RepeatFreq.monthly;
    final byWeekday = monthly && _month != _MonthMode.day;
    return Recurrence(
      freq: _freq,
      interval: _interval,
      weekdays: _freq == RepeatFreq.weekly ? _weekdays : const {},
      monthDay: monthly && !byWeekday ? _start.day : null,
      monthNth: byWeekday ? (_month == _MonthMode.last ? -1 : _nth) : null,
      monthWeekday: byWeekday ? _start.weekday : null,
      until: _end == _EndMode.until ? _until : null,
      count: _end == _EndMode.count ? _count : null,
    );
  }

  Future<void> _pickUntil() async {
    final picked = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute<DateTime>(
        builder: (_) => DateTimePickerScreen(
          title: dt('dt.end'),
          theme: widget.theme,
          initial: _until,
          firstYear: _start.year,
          lastYear: _start.year + 30,
          withTime: false,
        ),
        settings: const RouteSettings(name: '/date_picker'),
      ),
    );
    if (picked == null || !mounted) return;
    final day = DateTime(picked.year, picked.month, picked.day);
    setState(() {
      _until = day.isBefore(_start) ? _start : day;
      _end = _EndMode.until;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = _cs;
    final rule = _rule;
    return SheetScaffold(
      title: dt('dt.customTitle'),
      bottom: DateSheetButtons(
        cancel: dt('dt.cancel'),
        confirm: dt('dt.done'),
        confirmKey: const ValueKey('custom-repeat-done'),
        onConfirm: () => Navigator.pop(context, rule.toRrule()),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              repeatLine(rule.toRrule(), _start),
              key: const ValueKey('custom-repeat-summary'),
              style: AppFonts.onest(size: 13, color: cs.onSurfaceVariant),
            ),
            DateSectionLabel(dt('dt.every'), scheme: cs),
            Row(
              children: [
                DateStepper(
                  scheme: cs,
                  value: _interval,
                  min: 1,
                  max: 99,
                  onChanged: (v) => setState(() => _interval = v),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DateSegmented<RepeatFreq>(
                    scheme: cs,
                    value: _freq,
                    items: [
                      (RepeatFreq.daily, dtCount('dt.unitDay', _interval)),
                      (RepeatFreq.weekly, dtCount('dt.unitWeek', _interval)),
                      (RepeatFreq.monthly, dtCount('dt.unitMonth', _interval)),
                      (RepeatFreq.yearly, dtCount('dt.unitYear', _interval)),
                    ],
                    onChanged: (f) => setState(() => _freq = f),
                  ),
                ),
              ],
            ),
            if (_freq == RepeatFreq.weekly) ...[
              DateSectionLabel(dt('dt.byDays'), scheme: cs),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var d = 1; d <= 7; d++)
                    DayCircle(
                      key: ValueKey('weekday-$d'),
                      scheme: cs,
                      label: LocaleService.current.shortWeekdays[d - 1],
                      selected: _weekdays.contains(d),
                      onTap: () => setState(() {
                        // Хотя бы один день остаётся: без дней повтор пуст.
                        if (_weekdays.contains(d) && _weekdays.length == 1) return;
                        _weekdays.contains(d) ? _weekdays.remove(d) : _weekdays.add(d);
                      }),
                    ),
                ],
              ),
            ],
            if (_freq == RepeatFreq.monthly) ...[
              DateSectionLabel(dt('dt.byMonth'), scheme: cs),
              DateChoices<_MonthMode>(
                scheme: cs,
                value: _month,
                items: [
                  (_MonthMode.day, dt('dt.monthDay', {'n': _start.day})),
                  if (_nth <= 4) (_MonthMode.nth, dt('dt.nthWd.${_start.weekday}', {'o': dt('dt.ord.$_nth')})),
                  if (_isLast) (_MonthMode.last, dt('dt.lastWd.${_start.weekday}')),
                ],
                onChanged: (m) => setState(() => _month = m),
              ),
            ],
            DateSectionLabel(dt('dt.end'), scheme: cs),
            DateChoices<_EndMode>(
              scheme: cs,
              value: _end,
              items: [
                (_EndMode.never, dt('dt.never')),
                (_EndMode.until, dt('dt.endOn')),
                (_EndMode.count, dt('dt.endAfter')),
              ],
              trailing: {
                _EndMode.until: DatePill(
                  key: const ValueKey('repeat-until'),
                  scheme: cs,
                  active: _end == _EndMode.until,
                  text: LocaleService.current.dayLogDate(_until),
                  onTap: _pickUntil,
                ),
                _EndMode.count: DateStepper(
                  scheme: cs,
                  value: _count,
                  min: 1,
                  max: 999,
                  compact: true,
                  onChanged: (v) => setState(() {
                    _count = v;
                    _end = _EndMode.count;
                  }),
                ),
              },
              onChanged: (m) => setState(() => _end = m),
            ),
          ],
        ),
      ),
    );
  }
}
