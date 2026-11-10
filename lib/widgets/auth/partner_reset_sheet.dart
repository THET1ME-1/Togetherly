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

/// Время запроса на свой аккаунт, который человек уже видел и закрыл.
int _ownSeenAt = 0;

/// Код для партнёра, который забыл пароль (макет «Вход без писем», 2-А).
///
/// Главная зовёт это при открытии, при возврате в приложение и по пушу
/// `pair_reset`. Лист встаёт поверх любого экрана: код живёт десять минут, и
/// ждать, пока человек вернётся на главную, нельзя.
///
/// Сперва спрашивается запрос на СВОЙ аккаунт (10.11.2026): попросить код на
/// чужую почту может и сам партнёр, и хозяин обязан успеть нажать «Это не я».
Future<void> maybeShowPartnerReset(BuildContext context) async {
  if (_open || !PbAuthService().isLoggedIn) return;
  _open = true;
  try {
    OwnReset? own;
    try {
      own = await PbAuthService().ownPartnerReset();
    } catch (_) {
      // Нет связи или сервер старше этого листа — идём дальше, к коду.
      own = null;
    }
    // «Это я» уже нажато по этому же запросу — второй раз не спрашиваем.
    if (own != null && own.at.millisecondsSinceEpoch != _ownSeenAt) {
      if (!context.mounted) return;
      final asked = own;
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
          child: OwnResetSheet(own: asked),
        ),
      );
      _ownSeenAt = asked.at.millisecondsSinceEpoch;
      return;
    }
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

/// Лист хозяину аккаунта: «Ваш пароль меняют» с кнопкой «Это не я».
///
/// Строится по листу партнёра ниже: те же отступы, шрифты и кнопки. Кода
/// здесь нет: он только у партнёра.
class OwnResetSheet extends StatefulWidget {
  const OwnResetSheet({super.key, required this.own, this.clock, this.onCancel});

  final OwnReset own;

  /// Часы для теста; в приложении — системные.
  final DateTime Function()? clock;

  /// Отмена для теста; в приложении — запрос на сервер.
  final Future<void> Function()? onCancel;

  @override
  State<OwnResetSheet> createState() => _OwnResetSheetState();
}

class _OwnResetSheetState extends State<OwnResetSheet> {
  Timer? _tick;
  bool _busy = false;

  DateTime _now() => (widget.clock ?? DateTime.now)().toUtc();

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      // Срок вышел — отменять уже нечего.
      if (widget.own.left(_now()) == Duration.zero) {
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

  Future<void> _cancel() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await (widget.onCancel ?? PbAuthService().cancelPartnerReset)();
    } catch (_) {
      // Не дошло: лист остаётся, чтобы человек нажал ещё раз.
      if (!mounted) return;
      setState(() => _busy = false);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(trKey('proCancelFailed')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).maybePop();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(trKey('proCancelled')),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final own = widget.own;
    final name = own.partnerName.trim().isEmpty ? '…' : own.partnerName.trim();
    final at = own.at.toLocal();
    final time =
        '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final left = own.left(_now());
    final leftText =
        '${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}';

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
                    color: cs.errorContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.lock_reset_rounded,
                    size: 26,
                    color: inkOn(
                      cs.errorContainer,
                      cs.onErrorContainer,
                      cs.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trKey('proTitle'),
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
                        trKey(own.codeEntered ? 'proWhoEntered' : 'proWho')
                            .replaceAll('{0}', name)
                            .replaceAll('{1}', time),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trKey('proHint'),
                          style: TextStyle(
                            fontFamily: ProfileTheme.bodyFont,
                            fontSize: 13.5,
                            height: 1.35,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          trKey('proLeft').replaceAll('{0}', leftText),
                          style: TextStyle(
                            fontFamily: ProfileTheme.bodyFont,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                // Подписи целиком в одну строку, как у листа партнёра.
                Expanded(
                  flex: 2,
                  child: FilledButton.tonal(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).maybePop(),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: const StadiumBorder(),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(trKey('proMine')),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: FilledButton(
                    onPressed: _busy ? null : _cancel,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: const StadiumBorder(),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(trKey('proNotMe')),
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
