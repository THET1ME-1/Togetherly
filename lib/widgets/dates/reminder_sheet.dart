import 'package:flutter/material.dart';

import '../../l10n/dates_text.dart';
import '../../models/date_reminder.dart';
import '../../screens/date_time_picker_screen.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/fonts.dart';
import '../../theme/profile_theme.dart';
import '../app_sheet.dart';
import 'date_controls.dart';
import 'repeat_sheet.dart' show PresetRow;

/// Лист «Напоминание»: пресеты, как в Google Календаре, для даты на весь день
/// («За день в 9:00») или со временем («За 30 минут»). Уже добавленные стоят с
/// галочкой и второй раз не добавляются. Возвращает минуты или null.
Future<int?> showReminderSheet(
  BuildContext context, {
  required AppTheme theme,
  required bool allDay,
  required List<int> existing,
  String? timeText,
  DateTime? nextStart,
}) {
  final cs = ProfileTheme.schemeFor(theme);
  return showAppSheet<int>(
    context,
    background: cs.surfaceContainerLow,
    builder: (_) => Theme(
      data: ProfileTheme.data(cs),
      child: _ReminderSheet(
        theme: theme,
        scheme: cs,
        allDay: allDay,
        existing: existing,
        timeText: timeText,
        nextStart: nextStart,
      ),
    ),
  );
}

class _ReminderSheet extends StatelessWidget {
  const _ReminderSheet({
    required this.theme,
    required this.scheme,
    required this.allDay,
    required this.existing,
    required this.timeText,
    required this.nextStart,
  });

  final AppTheme theme;
  final ColorScheme scheme;
  final bool allDay;
  final List<int> existing;
  final String? timeText;
  final DateTime? nextStart;

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: dt('dt.remTitle'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                allDay ? dt('dt.remAllDay') : dt('dt.remAtTime', {'time': timeText ?? ''}),
                style: AppFonts.onest(size: 13, color: scheme.onSurfaceVariant),
              ),
            ),
            for (final m in reminderPresets(allDay: allDay))
              PresetRow(
                key: ValueKey('reminder-$m'),
                scheme: scheme,
                text: (reminderText(m, allDay: allDay), ''),
                checked: existing.contains(m),
                enabled: !existing.contains(m),
                onTap: () => Navigator.pop(context, m),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              child: Divider(height: 1, color: scheme.outlineVariant),
            ),
            PresetRow(
              key: const ValueKey('reminder-custom'),
              scheme: scheme,
              icon: Icons.tune_rounded,
              text: (dt('dt.remCustom'), ''),
              checked: false,
              onTap: () async {
                final m = await showCustomReminderSheet(
                  context,
                  theme: theme,
                  allDay: allDay,
                  nextStart: nextStart,
                );
                if (m != null && context.mounted) Navigator.pop(context, m);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Лист «Своё напоминание»: «За N [минут | часов | дней | недель]» у даты со
/// временем, «За N [дней | недель] в 9:00» у даты на весь день. Внизу —
/// когда придёт ближайшее.
Future<int?> showCustomReminderSheet(
  BuildContext context, {
  required AppTheme theme,
  required bool allDay,
  DateTime? nextStart,
}) {
  final cs = ProfileTheme.schemeFor(theme);
  return showAppSheet<int>(
    context,
    background: cs.surfaceContainerLow,
    builder: (_) => Theme(
      data: ProfileTheme.data(cs),
      child: CustomReminderSheet(theme: theme, scheme: cs, allDay: allDay, nextStart: nextStart),
    ),
  );
}

class CustomReminderSheet extends StatefulWidget {
  const CustomReminderSheet({
    super.key,
    required this.theme,
    required this.scheme,
    required this.allDay,
    this.nextStart,
  });

  final AppTheme theme;
  final ColorScheme scheme;
  final bool allDay;

  /// Ближайшее начало даты — для строки «придёт 4 декабря в 17:00».
  final DateTime? nextStart;

  @override
  State<CustomReminderSheet> createState() => _CustomReminderSheetState();
}

class _CustomReminderSheetState extends State<CustomReminderSheet> {
  int _amount = 1;
  ReminderUnit _unit = ReminderUnit.days;
  int _hour = 9;
  int _minute = 0;

  ColorScheme get _cs => widget.scheme;

  @override
  void initState() {
    super.initState();
    if (!widget.allDay) {
      _amount = 2;
      _unit = ReminderUnit.hours;
    }
  }

  /// Дни перед датой на весь день: 0 — «в этот день», недели — по семь.
  int get _daysBefore => _unit == ReminderUnit.weeks ? _amount * 7 : _amount;

  int get _minutes => widget.allDay
      ? allDayMinutes(_daysBefore, _hour, _minute)
      : timedMinutes(_amount, _unit);

  /// Когда придёт ближайшее: «4 декабря в 17:00».
  String? get _when {
    final start = widget.nextStart;
    if (start == null) return null;
    final DateTime at;
    if (widget.allDay) {
      final p = allDayParts(_minutes);
      at = DateTime(start.year, start.month, start.day - p.daysBefore, p.hour, p.minute);
    } else {
      at = start.subtract(Duration(minutes: _minutes));
    }
    return dt('dt.remDateTime', {
      'date': LocaleService.current.dayLogDate(at),
      'time': clockText(at.hour, at.minute),
    });
  }

  Future<void> _pickTime() async {
    final now = DateTime.now();
    final picked = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute<DateTime>(
        builder: (_) => DateTimePickerScreen(
          title: dt('dt.time'),
          theme: widget.theme,
          initial: DateTime(now.year, now.month, now.day, _hour, _minute),
          firstYear: now.year,
          lastYear: now.year + 1,
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

  @override
  Widget build(BuildContext context) {
    final cs = _cs;
    final allDay = widget.allDay;
    final units = allDay
        ? [
            (ReminderUnit.days, dtCount('dt.unitDay', _amount)),
            (ReminderUnit.weeks, dtCount('dt.unitWeek', _amount)),
          ]
        : [
            (ReminderUnit.minutes, dtCount('dt.uMinutes', _amount)),
            (ReminderUnit.hours, dtCount('dt.uHours', _amount)),
            (ReminderUnit.days, dtCount('dt.unitDay', _amount)),
            (ReminderUnit.weeks, dtCount('dt.unitWeek', _amount)),
          ];
    final when = _when;
    final ink = AppThemes.onColor(cs.primaryContainer);
    return SheetScaffold(
      title: dt('dt.remCustomTitle'),
      bottom: DateSheetButtons(
        cancel: dt('dt.cancel'),
        confirm: dt('dt.remAdd'),
        confirmKey: const ValueKey('custom-reminder-add'),
        onConfirm: () => Navigator.pop(context, _minutes),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DateSectionLabel(dt('dt.remBefore'), scheme: cs),
            Row(
              children: [
                DateStepper(
                  scheme: cs,
                  value: _amount,
                  min: allDay ? 0 : 1,
                  max: _unit == ReminderUnit.minutes ? 600 : 60,
                  onChanged: (v) => setState(() => _amount = v),
                ),
                if (allDay) ...[
                  const SizedBox(width: 10),
                  Text(dt('dt.remAt'), style: AppFonts.onest(size: 16, weight: 600, color: cs.onSurface)),
                  const SizedBox(width: 8),
                  DatePill(
                    key: const ValueKey('reminder-time'),
                    scheme: cs,
                    active: true,
                    text: clockText(_hour, _minute),
                    onTap: _pickTime,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            DateSegmented<ReminderUnit>(
              scheme: cs,
              value: _unit,
              items: units,
              onChanged: (u) => setState(() {
                _unit = u;
                if (_unit != ReminderUnit.minutes && _amount > 60) _amount = 60;
              }),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(24)),
              child: Row(
                children: [
                  Icon(Icons.notifications_rounded, size: 22, color: cs.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          reminderText(_minutes, allDay: allDay),
                          key: const ValueKey('custom-reminder-summary'),
                          style: AppFonts.onest(size: 16, weight: 700, color: ink),
                        ),
                        if (when != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            dt('dt.remWillCome', {'when': when}),
                            style: AppFonts.onest(size: 13, color: ink.withValues(alpha: 0.72)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
