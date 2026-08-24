import 'package:flutter/material.dart';

import '../../models/plus_gift.dart';
import '../../services/locale_service.dart';
import '../../theme/profile_theme.dart';
import '../app_sheet.dart';
import '../avatar_widget.dart';

/// Лист «кому подарить Togetherly+».
///
/// Между кнопкой и оплатой стоит намеренно: доступ уходит НЕ тому, кто платит,
/// и человек должен увидеть имя получателя раньше, чем откроется браузер.
/// Связей у части людей несколько, и выбирать за них нельзя.
///
/// Возвращает выбранного получателя или null, если лист закрыли.
Future<GiftRecipient?> showGiftRecipientSheet(
  BuildContext context, {
  required ColorScheme scheme,
  required PlusGiftOffer offer,
  String priceLabel = '',
}) {
  return showAppSheet<GiftRecipient>(
    context,
    background: scheme.surfaceContainerHigh,
    builder: (ctx) => Theme(
      // Лист живёт выше экрана в дереве навигатора и цвета берёт у
      // MaterialApp, а не у того, кто его открыл. Без этого он выезжает в
      // чужой теме — на этом уже ловили витрину Плюса.
      data: ProfileTheme.data(scheme),
      child: _GiftRecipientSheet(
        scheme: scheme,
        offer: offer,
        priceLabel: priceLabel,
      ),
    ),
  );
}

class _GiftRecipientSheet extends StatefulWidget {
  const _GiftRecipientSheet({
    required this.scheme,
    required this.offer,
    required this.priceLabel,
  });

  final ColorScheme scheme;
  final PlusGiftOffer offer;

  /// Цена на кнопке. В Play и App Store её называет магазин, поэтому она
  /// приходит готовой строкой, а не считается из ответа сервера.
  final String priceLabel;

  @override
  State<_GiftRecipientSheet> createState() => _GiftRecipientSheetState();
}

class _GiftRecipientSheetState extends State<_GiftRecipientSheet> {
  late String _chosenUid = widget.offer.suggested?.uid ?? '';

  ColorScheme get _cs => widget.scheme;
  AppStrings get _s => LocaleService.current;

  GiftRecipient? get _chosen {
    for (final r in widget.offer.recipients) {
      if (r.uid == _chosenUid) return r;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final chosen = _chosen;
    final price = widget.priceLabel;
    final canGift = chosen != null && !chosen.alreadyHasPlus;

    return SheetScaffold(
      title: _s.plusGiftSheetTitle,
      bottom: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: canGift ? () => Navigator.pop(context, chosen) : null,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: Text(
            price.isEmpty ? _s.plusGiftAction : _s.plusGiftActionFor(price),
            style: const TextStyle(
              fontFamily: 'Onest',
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _s.plusGiftSheetBody,
              style: TextStyle(
                fontFamily: 'Onest',
                fontSize: 13,
                height: 1.4,
                color: _cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            for (final r in widget.offer.recipients) ...[
              _recipientTile(r),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 6),
            Text(
              _s.plusGiftSheetNote,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Onest',
                fontSize: 11.5,
                height: 1.4,
                color: _cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  /// Строка получателя. У кого Плюс уже есть — приглушена и не нажимается, но
  /// остаётся на месте: пропавшее из списка знакомое имя читается как поломка.
  Widget _recipientTile(GiftRecipient r) {
    final taken = r.alreadyHasPlus;
    final selected = r.uid == _chosenUid && !taken;
    final bg = selected ? _cs.secondaryContainer : _cs.surfaceContainerHighest;
    final ink = selected ? _cs.onSecondaryContainer : _cs.onSurface;

    return Opacity(
      opacity: taken ? 0.55 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: taken ? null : () => setState(() => _chosenUid = r.uid),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                AvatarWidget(
                  uid: r.uid,
                  liveUrl: r.avatarUrl,
                  name: r.name,
                  size: 40,
                  primary: _cs.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Onest',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        taken ? _s.plusGiftHasPlus : _s.plusGiftPairRole,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Onest',
                          fontSize: 12,
                          color: selected
                              ? ink.withValues(alpha: 0.75)
                              : _cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  taken
                      ? Icons.check_circle_rounded
                      : selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                  size: 22,
                  color: selected ? ink : _cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
