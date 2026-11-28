import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/dates_text.dart';
import '../../services/pair_dates_service.dart';
import '../../services/phone_calendar_sync.dart';
import '../../theme/app_theme.dart';
import '../../theme/fonts.dart';
import '../../theme/profile_theme.dart';
import '../app_sheet.dart';
import 'date_controls.dart';

/// Лист «Календарь телефона»: включить копию наших дат и выбрать календарь.
/// Каждый из пары включает у себя.
Future<void> showPhoneCalendarSheet(BuildContext context, {required AppTheme theme}) {
  final cs = ProfileTheme.schemeFor(theme);
  return showAppSheet<void>(
    context,
    background: cs.surfaceContainerLow,
    builder: (_) => Theme(data: ProfileTheme.data(cs), child: PhoneCalendarSheet(scheme: cs)),
  );
}

class PhoneCalendarSheet extends StatefulWidget {
  const PhoneCalendarSheet({super.key, required this.scheme});

  final ColorScheme scheme;

  @override
  State<PhoneCalendarSheet> createState() => _PhoneCalendarSheetState();
}

class _PhoneCalendarSheetState extends State<PhoneCalendarSheet> {
  final PhoneCalendarSync _sync = PhoneCalendarSync.instance;
  List<Calendar> _calendars = const [];
  bool _denied = false;
  bool _busy = false;

  ColorScheme get _cs => widget.scheme;

  @override
  void initState() {
    super.initState();
    _sync.addListener(_changed);
    _start();
  }

  @override
  void dispose() {
    _sync.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    await _sync.load();
    if (_sync.enabled && await _sync.hasAccess()) {
      final list = await _sync.writableCalendars();
      if (mounted) setState(() => _calendars = list);
    }
  }

  static String labelOf(Calendar c) {
    final account = c.accountName ?? '';
    return account.isEmpty || account == c.name ? c.name : '${c.name} · $account';
  }

  Future<void> _turnOn() async {
    setState(() => _busy = true);
    final granted = await _sync.hasAccess() || await _sync.askAccess();
    if (!granted) {
      if (mounted) {
        setState(() {
          _denied = true;
          _busy = false;
        });
      }
      return;
    }
    final list = await _sync.writableCalendars();
    if (!mounted) return;
    setState(() {
      _denied = false;
      _calendars = list;
    });
    if (list.isNotEmpty) {
      await _sync.enable(list.first, labelOf(list.first));
      _sync.mirror(PairDatesService.instance.own);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _turnOff() async {
    var remove = false;
    if (_sync.count > 0) {
      final answer = await showAppSheet<bool>(
        context,
        background: _cs.surfaceContainerLow,
        builder: (ctx) => Theme(
          data: ProfileTheme.data(_cs),
          child: SheetScaffold(
            title: dt('dt.phOffAsk'),
            bottom: Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    child: Text(dt('dt.phKeep')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('phone-remove-added'),
                    onPressed: () => Navigator.pop(ctx, true),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    child: Text(dt('dt.phRemove')),
                  ),
                ),
              ],
            ),
            child: const SizedBox.shrink(),
          ),
        ),
      );
      if (answer == null) return;
      remove = answer;
    }
    setState(() => _busy = true);
    await _sync.disable(removeAdded: remove);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _choose(Calendar c) async {
    if (c.id == _sync.calendarId) return;
    setState(() => _busy = true);
    await _sync.enable(c, labelOf(c));
    _sync.mirror(PairDatesService.instance.own);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = _cs;
    final enabled = _sync.enabled;
    return SheetScaffold(
      title: dt('dt.phTitle'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(dt('dt.phHint'), style: AppFonts.onest(size: 13, height: 1.4, color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            Material(
              color: cs.tertiaryContainer,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const ValueKey('phone-toggle'),
                onTap: _busy ? null : (enabled ? _turnOff : _turnOn),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: cs.onTertiaryContainer.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.event_available_rounded, color: cs.onTertiaryContainer),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dt('dt.phToggle'),
                              style: AppFonts.onest(size: 16, weight: 700, color: cs.onTertiaryContainer),
                            ),
                            if (enabled && _sync.count > 0) ...[
                              const SizedBox(height: 2),
                              Text(
                                dtCount('dt.phCount', _sync.count),
                                style: AppFonts.onest(size: 13, color: cs.onTertiaryContainer.withValues(alpha: 0.8)),
                              ),
                            ],
                          ],
                        ),
                      ),
                      _busy
                          ? const SizedBox(width: 52, height: 32, child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)))
                          : Switch(value: enabled, onChanged: (_) => enabled ? _turnOff() : _turnOn()),
                    ],
                  ),
                ),
              ),
            ),
            if (_denied) ...[
              const SizedBox(height: 12),
              Text(dt('dt.phDenied'), style: AppFonts.onest(size: 14, weight: 600, color: cs.error)),
              const SizedBox(height: 8),
              FilledButton.tonal(
                key: const ValueKey('phone-settings'),
                onPressed: _sync.openSettings,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: Text(dt('dt.phSettings')),
              ),
            ],
            if (enabled && !_denied) ...[
              DateSectionLabel(dt('dt.phWhere'), scheme: cs),
              if (_calendars.isEmpty)
                Text(dt('dt.phEmpty'), style: AppFonts.onest(size: 14, color: cs.onSurfaceVariant))
              else
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(24)),
                  child: Column(
                    children: [
                      for (final c in _calendars) _calendarRow(cs, c),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.sync_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(dt('dt.phSync'), style: AppFonts.onest(size: 13, height: 1.4, color: cs.onSurfaceVariant)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _calendarRow(ColorScheme cs, Calendar c) {
    final selected = c.id == _sync.calendarId;
    final account = c.accountName ?? '';
    final local = (c.accountType ?? '').toUpperCase() == 'LOCAL';
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: InkWell(
        onTap: _busy
            ? null
            : () {
                HapticFeedback.selectionClick();
                _choose(c);
              },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(color: _colorOf(c.colorHex) ?? cs.primary, shape: BoxShape.circle),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name, style: AppFonts.onest(size: 16, weight: 700, color: cs.onSurface)),
                      if (local || (account.isNotEmpty && account != c.name)) ...[
                        const SizedBox(height: 2),
                        Text(
                          local ? dt('dt.phLocal') : account,
                          style: AppFonts.onest(size: 13, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Color? _colorOf(String? hex) {
    final h = (hex ?? '').replaceAll('#', '');
    final v = int.tryParse(h, radix: 16);
    if (v == null) return null;
    return Color(h.length <= 6 ? 0xFF000000 | v : v);
  }
}
