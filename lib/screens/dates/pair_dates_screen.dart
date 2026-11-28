import 'package:flutter/material.dart';

import '../../l10n/dates_text.dart';
import '../../models/pair_data.dart';
import '../../models/pair_date.dart';
import '../../models/symbol_catalog.dart';
import '../../models/user_data.dart';
import '../../services/locale_service.dart';
import '../../services/pair_dates_service.dart';
import '../../services/widget_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/fonts.dart';
import '../../theme/profile_theme.dart';
import '../../utils/calendar_day.dart';
import 'date_form_screen.dart';

/// «Наши даты» списком: что скоро и что уже было в этом году. Сюда ведёт чип
/// «Все даты» под карточкой ближайшей даты.
class PairDatesScreen extends StatefulWidget {
  const PairDatesScreen({
    super.key,
    required this.theme,
    required this.pair,
    required this.userData,
    required this.widgetService,
  });

  final AppTheme theme;
  final PairData pair;
  final UserData? userData;
  final WidgetService widgetService;

  @override
  State<PairDatesScreen> createState() => _PairDatesScreenState();
}

class _PairDatesScreenState extends State<PairDatesScreen> {
  final PairDatesService _dates = PairDatesService.instance;

  @override
  void initState() {
    super.initState();
    _dates.addListener(_changed);
    widget.pair.addListener(_changed);
  }

  @override
  void dispose() {
    _dates.removeListener(_changed);
    widget.pair.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  String get _myUid => widget.userData?.uid ?? '';

  Future<void> _open(DateOccurrence o) async {
    if (o.date.isAuto) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(dt('dt.autoHint'))));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<bool>(
      builder: (_) => DateFormScreen(
        theme: widget.theme,
        groupId: widget.pair.pairId,
        existing: o.date,
        occurrenceDay: o.day,
      ),
      settings: const RouteSettings(name: '/date_form'),
    ));
  }

  Future<void> _add() async {
    await Navigator.of(context).push(MaterialPageRoute<bool>(
      builder: (_) => DateFormScreen(theme: widget.theme, groupId: widget.pair.pairId),
      settings: const RouteSettings(name: '/date_form'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.schemeFor(widget.theme);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final all = _dates.allFor(widget.pair, myUid: _myUid);
    final soon = upcomingOccurrences(all, now);
    // Уже были в этом году: у каждой даты — последний прошедший повтор.
    final past = <DateOccurrence>[
      for (final d in all)
        ...() {
          final list = d.occurrencesBetween(DateTime(today.year, 1, 1), calendarDay(today, -1));
          return list.isEmpty ? const <DateOccurrence>[] : [list.last];
        }(),
    ]..sort((a, b) => b.day.compareTo(a.day));
    final partner = widget.pair.partnerDisplayName;
    final gender = widget.widgetService.firstPartnerData?.gender ?? '';

    return Theme(
      data: ProfileTheme.data(cs),
      child: Scaffold(
        backgroundColor: widget.theme.surfaceMuted,
        appBar: AppBar(
          backgroundColor: widget.theme.cardSurface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(dt('dt.legend'), style: AppFonts.onest(size: 20, weight: 800, color: widget.theme.textPrimary)),
        ),
        floatingActionButton: FloatingActionButton.extended(
          key: const ValueKey('dates-add-fab'),
          onPressed: _add,
          backgroundColor: cs.primaryContainer,
          foregroundColor: AppThemes.onColor(cs.primaryContainer),
          elevation: 0,
          icon: const Icon(Icons.add_rounded),
          label: Text(dt('dt.add'), style: AppFonts.onest(size: 15, weight: 700)),
        ),
        body: all.isEmpty
            ? _empty(cs)
            : ListView(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 110 + MediaQuery.of(context).padding.bottom),
                children: [
                  if (soon.isNotEmpty) ...[
                    _sectionTitle(cs, dt('dt.soon')),
                    _group(cs, [
                      for (final o in soon)
                        _row(cs, o, trailing: untilText(daysBetween(today, o.day)), partner: partner, gender: gender),
                    ]),
                  ],
                  if (past.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    _sectionTitle(cs, dt('dt.pastYear')),
                    _group(cs, [for (final o in past) _row(cs, o, partner: partner, gender: gender)]),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _empty(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: cs.tertiaryContainer, shape: BoxShape.circle),
              child: Icon(Icons.event_rounded, size: 36, color: cs.onTertiaryContainer),
            ),
            const SizedBox(height: 18),
            Text(
              dt('dt.emptyTitle'),
              textAlign: TextAlign.center,
              style: AppFonts.unbounded(size: 18, weight: 700, color: cs.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              dt('dt.emptyHint'),
              textAlign: TextAlign.center,
              style: AppFonts.onest(size: 14, height: 1.4, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(ColorScheme cs, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(text, style: AppFonts.unbounded(size: 14, weight: 700, color: cs.onSurfaceVariant)),
      );

  Widget _group(ColorScheme cs, List<Widget> rows) => Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(28)),
        child: Column(children: rows),
      );

  Widget _row(
    ColorScheme cs,
    DateOccurrence o, {
    String? trailing,
    required String partner,
    required String gender,
  }) {
    final d = o.date;
    final auto = d.isAuto;
    final tile = auto ? cs.primaryContainer : cs.tertiaryContainer;
    final tileFg = auto ? AppThemes.onColor(cs.primaryContainer) : cs.onTertiaryContainer;
    final sub = [
      if (!auto && d.repeats) repeatLine(d.rrule, d.day!),
      if (auto) autoSourceText(d),
      occurrenceLine(o, myUid: _myUid, partnerName: partner, partnerGender: gender, withDate: false),
    ].where((t) => t.isNotEmpty).join(' · ');
    return InkWell(
      key: ValueKey('dates-row-${d.id}'),
      onTap: () => _open(o),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: tile, borderRadius: BorderRadius.circular(18)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('${o.day.day}', style: AppFonts.unbounded(size: 18, weight: 800, height: 1.1, color: tileFg)),
                  Text(
                    LocaleService.current.shortMonths[o.day.month - 1],
                    style: AppFonts.onest(size: 11, weight: 700, color: tileFg),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SymbolIcon(d.symbol, size: 18, color: cs.tertiary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          dateTitle(d, o.day),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppFonts.onest(size: 16, weight: 700, color: cs.onSurface),
                        ),
                      ),
                    ],
                  ),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(sub, style: AppFonts.onest(size: 13, color: cs.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 84),
                child: Text(
                  trailing,
                  textAlign: TextAlign.right,
                  style: AppFonts.onest(size: 12, weight: 700, color: cs.primary),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
