import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../dict_strings.dart';
import '../../models/partner_reset.dart';
import '../../services/pb_auth_service.dart';
import '../../theme/profile_theme.dart';
import '../../theme/theme_scope.dart';
import '../app_sheet.dart';
import 'ink.dart';

bool _open = false;

/// Код для партнёра, который забыл пароль (макет «Вход без писем», 2-А).
///
/// Главная зовёт это при открытии, при возврате в приложение и по пушу
/// `pair_reset`. Лист встаёт поверх любого экрана: код живёт десять минут, и
/// ждать, пока человек вернётся на главную, нельзя.
Future<void> maybeShowPartnerReset(BuildContext context) async {
  if (_open || !PbAuthService().isLoggedIn) return;
  _open = true;
  try {
    final PendingReset? pending;
    try {
      pending = await PbAuthService().pendingPartnerReset();
    } catch (_) {
      // Нет связи — спросим на следующем возврате или пуше.
      return;
    }
    if (pending == null || !context.mounted) return;
    final cs = ProfileTheme.schemeFor(context.appTheme);
    await showModalSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: cs.surfaceContainerLow,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => Theme(
        data: ProfileTheme.data(cs),
        child: PartnerResetSheet(pending: pending!),
      ),
    );
  } finally {
    _open = false;
  }
}

class PartnerResetSheet extends StatefulWidget {
  const PartnerResetSheet({super.key, required this.pending, this.clock});

  final PendingReset pending;

  /// Часы для теста; в приложении — системные.
  final DateTime Function()? clock;

  @override
  State<PartnerResetSheet> createState() => _PartnerResetSheetState();
}

class _PartnerResetSheetState extends State<PartnerResetSheet> {
  Timer? _tick;
  bool _busy = false;

  DateTime _now() => (widget.clock ?? DateTime.now)().toUtc();

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      // Код истёк — показывать больше нечего.
      if (widget.pending.left(_now()) == Duration.zero) {
        Navigator.of(context).maybePop();
        return;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _deny() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await PbAuthService().denyPartnerReset();
    } catch (_) {
      // Не дошло — код и так погаснет через несколько минут.
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.of(context).pop();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(trKey('prDenied')),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.pending.code));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(trKey('prCopied')),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = widget.pending;
    final name = p.name.trim().isEmpty ? '…' : p.name.trim();
    final at = p.at.toLocal();
    final time =
        '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final left = p.left(_now());
    final leftText =
        '${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}';
    final codeInk = inkOn(
      cs.primaryContainer,
      cs.onPrimaryContainer,
      cs.onSurface,
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.tertiaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    name.characters.first.toUpperCase(),
                    style: TextStyle(
                      fontFamily: ProfileTheme.displayFont,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: inkOn(
                        cs.tertiaryContainer,
                        cs.onTertiaryContainer,
                        cs.onSurface,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trKey(p.female ? 'prAskF' : 'prAskM')
                            .replaceAll('{0}', name),
                        style: TextStyle(
                          fontFamily: ProfileTheme.displayFont,
                          fontSize: 19,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        trKey('prAskedAt').replaceAll('{0}', time),
                        style: TextStyle(
                          fontFamily: ProfileTheme.bodyFont,
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      formatResetCode(p.code),
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: ProfileTheme.displayFont,
                        fontSize: 44,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        fontVariations: const [FontVariation('wght', 800)],
                        color: codeInk,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    trKey('prCodeLeft').replaceAll('{0}', leftText),
                    style: TextStyle(
                      fontFamily: ProfileTheme.bodyFont,
                      fontSize: 13.5,
                      color: codeInk.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shield_rounded, size: 20, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      trKey(p.female ? 'prWarnF' : 'prWarnM')
                          .replaceAll('{0}', name),
                      style: TextStyle(
                        fontFamily: ProfileTheme.bodyFont,
                        fontSize: 13.5,
                        height: 1.35,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                // Подписи целиком в одну строку: на узком экране и крупном
                // шрифте они сжимаются, а не обрезаются («Это не она» в 1.41
                // превращалось в «Это»).
                Expanded(
                  flex: 2,
                  child: FilledButton.tonal(
                    onPressed: _busy ? null : _deny,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: const StadiumBorder(),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(trKey(p.female ? 'prDenyF' : 'prDenyM')),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: FilledButton(
                    onPressed: _copy,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: const StadiumBorder(),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.content_copy_rounded, size: 18),
                          const SizedBox(width: 8),
                          Text(trKey('prCopy')),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
