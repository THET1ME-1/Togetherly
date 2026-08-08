import 'package:flutter/material.dart';

import '../../models/pair_data.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/profile_theme.dart';
import '../app_sheet.dart';
import '../common/m3_loading.dart';

/// Лист «жду человека»: имя, дата возвращения — и пара заводится на одного.
///
/// Тем же листом заглушку правят потом: срок службы сдвигается, имя уточняется.
class WaitingSetupSheet extends StatefulWidget {
  final PairData pair;
  final AppTheme theme;

  /// Правим существующую пару, а не заводим новую.
  final bool editing;

  const WaitingSetupSheet({
    super.key,
    required this.pair,
    required this.theme,
    this.editing = false,
  });

  static Future<bool?> show(
    BuildContext context, {
    required PairData pair,
    required AppTheme theme,
    bool editing = false,
  }) =>
      showAppSheet<bool>(
        context,
        builder: (_) => WaitingSetupSheet(
          pair: pair,
          theme: theme,
          editing: editing,
        ),
      );

  @override
  State<WaitingSetupSheet> createState() => _WaitingSetupSheetState();
}

class _WaitingSetupSheetState extends State<WaitingSetupSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.editing ? widget.pair.placeholderName : '',
  );
  DateTime? _returnDate;
  bool _saving = false;

  /// Отказ показываем ВНУТРИ листа. Снекбар живёт в Scaffold, а лист — маршрутом
  /// поверх него: сообщение уезжало под лист, и отказ сервера выглядел как
  /// «нажимаю „Завести пару“ — абсолютно ничего не происходит».
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.editing) _returnDate = widget.pair.returnDate;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _returnDate ?? DateTime(now.year + 1, now.month, now.day),
      firstDate: now,
      // Служба, вахта, экспедиция — дальше пяти лет планов не строят.
      lastDate: DateTime(now.year + 5, now.month, now.day),
      helpText: LocaleService.current.waitingReturnDate,
    );
    if (picked != null && mounted) setState(() => _returnDate = picked);
  }

  Future<void> _save() async {
    final s = LocaleService.current;
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final ok = widget.editing
        ? await widget.pair.updateWaitingPlaceholder(
            name: name,
            returnDate: _returnDate,
            clearReturnDate: _returnDate == null,
          )
        : (await widget.pair.createWaitingPair(
            name: name,
            returnDate: _returnDate,
          ))
            .isNotEmpty;
    if (!mounted) return;
    if (ok) {
      setState(() => _saving = false);
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _saving = false;
        _error = widget.pair.lastWaitingCreateError ?? s.waitingCreateFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.themeFor(widget.theme).colorScheme;
    final s = LocaleService.current;
    final days = _returnDate == null
        ? null
        : DateTime(_returnDate!.year, _returnDate!.month, _returnDate!.day)
            .difference(DateTime(
                DateTime.now().year, DateTime.now().month, DateTime.now().day))
            .inDays;

    return SheetScaffold(
      title: widget.editing ? s.waitingEditTitle : s.waitingSetupTitle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.waitingSetupHint,
              style: TextStyle(
                fontFamily: ProfileTheme.bodyFont,
                fontSize: 14.5,
                height: 1.35,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: s.waitingNameLabel,
                filled: true,
                fillColor: cs.surfaceContainerHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Icon(Icons.event_rounded, size: 20, color: cs.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _returnDate == null
                            ? s.waitingReturnDate
                            : '${_returnDate!.day.toString().padLeft(2, '0')}.'
                                '${_returnDate!.month.toString().padLeft(2, '0')}.'
                                '${_returnDate!.year}',
                        style: TextStyle(
                          fontFamily: ProfileTheme.bodyFont,
                          fontSize: 15,
                          color: _returnDate == null
                              ? cs.onSurfaceVariant
                              : cs.onSurface,
                        ),
                      ),
                    ),
                    if (days != null)
                      Text(
                        s.waitingDaysLeft(days),
                        style: TextStyle(
                          fontFamily: ProfileTheme.bodyFont,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                    if (_returnDate != null)
                      IconButton(
                        onPressed: () => setState(() => _returnDate = null),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 20, color: cs.onErrorContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          fontFamily: ProfileTheme.bodyFont,
                          fontSize: 14,
                          height: 1.3,
                          color: cs.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _name.text.trim().isEmpty || _saving ? null : _save,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: const StadiumBorder(),
              ),
              child: _saving
                  ? M3Loading(size: 22, color: cs.onPrimary)
                  : Text(widget.editing ? s.save : s.waitingCreateAction),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
