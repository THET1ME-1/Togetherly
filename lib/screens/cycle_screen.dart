import 'package:flutter/material.dart';

import '../models/cycle_entry.dart';
import '../services/cycle_service.dart';
import '../services/locale_service.dart';
import '../theme/profile_theme.dart';
import '../utils/cycle_math.dart';
import '../widgets/app_sheet.dart';
import '../widgets/cycle_analytics.dart';
import '../widgets/settings_scaffold.dart';

/// Календарь цикла: отметки месячных и близости плюс прогноз.
///
/// Прогноз — календарный метод: средняя длина по своим последним циклам,
/// овуляция за 14 дней до ожидаемых месячных, фертильное окно вокруг неё.
/// При нерегулярном цикле метод врёт, поэтому такой прогноз честно помечается —
/// рисовать уверенную дату там, где её нет, хуже, чем признать разброс.
class CycleScreen extends StatefulWidget {
  const CycleScreen({
    super.key,
    required this.scheme,
    required this.groupId,
    this.partnerName = '',
  });

  final ColorScheme scheme;
  final String groupId;
  final String partnerName;

  @override
  State<CycleScreen> createState() => _CycleScreenState();
}

class _CycleScreenState extends State<CycleScreen> {
  final CycleService _cycle = CycleService.instance;

  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
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

  ColorScheme get _cs => widget.scheme;
  AppStrings get _s => LocaleService.current;

  // ── Цвета фаз ──────────────────────────────────────────────────────────
  //
  // Месячные — красным (это кровь, иносказания тут только мешают), фертильные
  // дни — акцентом темы, ожидаемые месячные — тем же красным, но пунктирной
  // обводкой: это прогноз, а не факт.
  Color get _periodColor => const Color(0xFFD32F2F);
  Color get _fertileColor => _cs.primary;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ProfileTheme.data(_cs),
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: _cs.surface,
          appBar: AppBar(
            backgroundColor: _cs.surface,
            surfaceTintColor: Colors.transparent,
            centerTitle: true,
            title: Text(
              _s.cycleTitle,
              style: TextStyle(
                fontFamily: 'Unbounded',
                fontSize: 22,
                fontWeight: FontWeight.w600,
                fontVariations: const [FontVariation('wght', 600)],
                color: _cs.onSurface,
              ),
            ),
          ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              4,
              16,
              MediaQuery.of(context).padding.bottom + 32,
            ),
            children: [
              _statusCard(),
              const SizedBox(height: 16),
              _calendarCard(),
              const SizedBox(height: 16),
              _forecastSection(),
              const SizedBox(height: 16),
              CycleAnalytics(
                scheme: _cs,
                periodDays: _cycle.mine
                    .where((e) => e.kind == CycleKind.period)
                    .map((e) => e.day)
                    .toList(),
                periodColor: _periodColor,
              ),
              const SizedBox(height: 16),
              _legend(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Статус ─────────────────────────────────────────────────────────────

  Widget _statusCard() {
    final forecast = _cycle.forecast;
    final day = _cycle.dayOfCycle;

    String headline;
    String? note;

    if (forecast == null) {
      headline = _s.cycleNoDataTitle;
      note = _s.cycleNoDataHint;
    } else if (forecast.overdueDays > 0) {
      headline = _s.cycleOverdue(forecast.overdueDays);
      note = _s.cycleOverdueHint;
    } else {
      final left = forecast.nextPeriod.difference(_today()).inDays;
      headline = left <= 0 ? _s.cycleExpectedToday : _s.cycleDaysLeft(left);
      note = day == null ? null : _s.cycleDayOfCycle(day);
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cs.primaryContainer,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            headline,
            style: TextStyle(
              fontFamily: 'Unbounded',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              fontVariations: const [FontVariation('wght', 700)],
              letterSpacing: -0.4,
              color: _cs.onPrimaryContainer,
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: 6),
            Text(
              note,
              style: TextStyle(
                fontFamily: 'Onest',
                fontSize: 13,
                color: _cs.onPrimaryContainer.withValues(alpha: 0.75),
              ),
            ),
          ],
          if (forecast != null && forecast.irregular) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.info_rounded,
                    size: 16, color: _cs.onPrimaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _s.cycleIrregularWarning,
                    style: TextStyle(
                      fontFamily: 'Onest',
                      fontSize: 12,
                      color: _cs.onPrimaryContainer.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Календарь ──────────────────────────────────────────────────────────

  Widget _calendarCard() {
    final first = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    // Понедельник — первый столбец.
    final leading = (first.weekday - 1) % 7;
    final cells = <DateTime?>[
      ...List.filled(leading, null),
      for (var d = 1; d <= daysInMonth; d++)
        DateTime(_month.year, _month.month, d),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month - 1),
                ),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  _monthLabel(_month),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Unbounded',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    fontVariations: const [FontVariation('wght', 700)],
                    color: _cs.onSurface,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month + 1),
                ),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (final d in _s.cycleWeekdayShorts)
                Expanded(
                  child: Text(
                    d,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Onest',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _cs.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
            ),
            itemCount: cells.length,
            itemBuilder: (_, i) {
              final day = cells[i];
              return day == null ? const SizedBox.shrink() : _dayCell(day);
            },
          ),
        ],
      ),
    );
  }

  Widget _dayCell(DateTime day) {
    final phase = _cycle.phaseOn(day);
    final isToday = day == _today();
    final isFuture = day.isAfter(_today());
    final hasIntimacy = _cycle.myEntryOn(day, CycleKind.intimacy) != null;
    final partnerMark = _cycle.partner.any((e) =>
        e.day == day && e.kind == CycleKind.period);

    Color? fill;
    Color? ring;
    switch (phase) {
      case CyclePhase.period:
        fill = _periodColor.withValues(alpha: 0.9);
      case CyclePhase.predictedPeriod:
        ring = _periodColor.withValues(alpha: 0.6);
      case CyclePhase.ovulation:
        fill = _fertileColor.withValues(alpha: 0.85);
      case CyclePhase.fertile:
        fill = _fertileColor.withValues(alpha: 0.22);
      case CyclePhase.none:
        break;
    }
    // Отметка партнёрши: своих данных может не быть вовсе, а её показать надо.
    if (fill == null && partnerMark) {
      fill = _periodColor.withValues(alpha: 0.35);
    }

    final onFill = phase == CyclePhase.period || phase == CyclePhase.ovulation;

    return GestureDetector(
      onTap: isFuture ? null : () => _openDaySheet(day),
      child: Container(
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: fill ?? Colors.transparent,
          shape: BoxShape.circle,
          border: ring != null
              ? Border.all(color: ring, width: 2)
              : (isToday
                  ? Border.all(color: _cs.onSurface, width: 1.5)
                  : null),
        ),
        alignment: Alignment.center,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              '${day.day}',
              style: TextStyle(
                fontFamily: 'Onest',
                fontSize: 13,
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                color: onFill
                    ? Colors.white
                    : (isFuture
                        ? _cs.onSurfaceVariant.withValues(alpha: 0.5)
                        : _cs.onSurface),
              ),
            ),
            if (hasIntimacy)
              Positioned(
                bottom: 0,
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: onFill ? Colors.white : _cs.tertiary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Лист дня ───────────────────────────────────────────────────────────

  void _openDaySheet(DateTime day) {
    showAppSheet<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final hasPeriod = _cycle.myEntryOn(day, CycleKind.period) != null;
          final hasIntimacy = _cycle.myEntryOn(day, CycleKind.intimacy) != null;

          return SheetScaffold(
            title: _dayLabel(day),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: SettingsGroup([
                SettingsRow(
                  icon: Icons.water_drop_rounded,
                  title: _s.cycleMarkPeriod,
                  subtitle: _s.cycleMarkPeriodHint,
                  iconBg: _periodColor.withValues(alpha: 0.16),
                  iconFg: _periodColor,
                  trailing: Switch(
                    value: hasPeriod,
                    onChanged: (_) async {
                      await _cycle.toggle(day, CycleKind.period);
                      setSheet(() {});
                    },
                  ),
                  onTap: () async {
                    await _cycle.toggle(day, CycleKind.period);
                    setSheet(() {});
                  },
                ),
                const SettingsDivider(),
                SettingsRow(
                  icon: Icons.favorite_rounded,
                  title: _s.cycleMarkIntimacy,
                  subtitle: _s.cycleMarkIntimacyHint,
                  iconBg: _cs.tertiaryContainer,
                  iconFg: _cs.onTertiaryContainer,
                  trailing: Switch(
                    value: hasIntimacy,
                    onChanged: (_) async {
                      await _cycle.toggle(day, CycleKind.intimacy);
                      setSheet(() {});
                    },
                  ),
                  onTap: () async {
                    await _cycle.toggle(day, CycleKind.intimacy);
                    setSheet(() {});
                  },
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ── Аналитика ──────────────────────────────────────────────────────────

  Widget _forecastSection() {
    final cycleLen = _cycle.averageCycleLength;
    final periodLen = _cycle.averagePeriodLength;
    final forecast = _cycle.forecast;

    if (cycleLen == null && periodLen == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSection(_s.cycleAnalyticsTitle),
        SettingsGroup([
          if (cycleLen != null)
            SettingsRow(
              icon: Icons.autorenew_rounded,
              title: _s.cycleAverageLength,
              subtitle: _s.cycleDaysValue(cycleLen),
            ),
          if (cycleLen != null && periodLen != null) const SettingsDivider(),
          if (periodLen != null)
            SettingsRow(
              icon: Icons.water_drop_outlined,
              title: _s.cycleAveragePeriod,
              subtitle: _s.cycleDaysValue(periodLen),
            ),
          if (forecast != null) ...[
            const SettingsDivider(),
            SettingsRow(
              icon: Icons.event_rounded,
              title: _s.cycleNextPeriod,
              subtitle: _fullDate(forecast.nextPeriod),
            ),
            const SettingsDivider(),
            SettingsRow(
              icon: Icons.eco_rounded,
              title: _s.cycleFertileWindow,
              subtitle:
                  '${_shortDate(forecast.fertileFrom)} — ${_shortDate(forecast.fertileTo)}',
            ),
          ],
        ]),
      ],
    );
  }

  Widget _legend() {
    Widget item(Color color, String label, {bool ring = false}) => Row(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: ring ? Colors.transparent : color,
                shape: BoxShape.circle,
                border: ring ? Border.all(color: color, width: 2) : null,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Onest',
                fontSize: 12,
                color: _cs.onSurfaceVariant,
              ),
            ),
          ],
        );

    return Wrap(
      spacing: 18,
      runSpacing: 10,
      children: [
        item(_periodColor.withValues(alpha: 0.9), _s.cycleLegendPeriod),
        item(_periodColor.withValues(alpha: 0.6), _s.cycleLegendPredicted,
            ring: true),
        item(_fertileColor.withValues(alpha: 0.85), _s.cycleLegendOvulation),
        item(_fertileColor.withValues(alpha: 0.22), _s.cycleLegendFertile),
        item(_cs.tertiary, _s.cycleLegendIntimacy),
      ],
    );
  }

  // ── Даты ───────────────────────────────────────────────────────────────

  DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  String _monthLabel(DateTime d) =>
      '${_s.cycleMonthNames[d.month - 1]} ${d.year}';

  String _dayLabel(DateTime d) =>
      '${d.day} ${_s.cycleMonthsGenitive[d.month - 1]}';

  String _shortDate(DateTime d) =>
      '${d.day} ${_s.cycleMonthsGenitive[d.month - 1]}';

  String _fullDate(DateTime d) =>
      '${d.day} ${_s.cycleMonthsGenitive[d.month - 1]} ${d.year}';
}
