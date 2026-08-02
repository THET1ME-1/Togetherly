import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../theme/profile_theme.dart';

/// Главная у той, кто ждёт: сколько осталось до возвращения.
///
/// Заодно единственное место, где заявка на второе место видна сразу при
/// запуске: экран пары человек открывает не каждый день, а «кто-то ввёл ваш
/// код» ждать в очереди не должно.
class WaitingHomeCard extends StatelessWidget {
  final ColorScheme scheme;
  final String name;

  /// Дней до возвращения. null — дата не задана, отрицательное — уже пора.
  final int? daysLeft;

  /// Имя того, кто ввёл код. null — заявки нет.
  final String? claimName;

  final VoidCallback onApprove;
  final VoidCallback onDecline;

  const WaitingHomeCard({
    super.key,
    required this.scheme,
    required this.name,
    required this.daysLeft,
    required this.claimName,
    required this.onApprove,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final cs = scheme;
    final pending = claimName != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: pending ? cs.primaryContainer : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
      ),
      child: pending ? _claim(cs, s) : _countdown(cs, s),
    );
  }

  Widget _countdown(ColorScheme cs, AppStrings s) {
    final days = daysLeft;
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration:
              BoxDecoration(color: cs.secondaryContainer, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Icon(Icons.hourglass_bottom_rounded,
              size: 22, color: cs.onSecondaryContainer),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                days == null
                    ? name
                    : days <= 0
                        ? s.waitingHomeToday
                        : s.waitingDaysLeft(days),
                style: TextStyle(
                  fontFamily: ProfileTheme.displayFont,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                days == null || days <= 0
                    ? s.waitingBadge
                    : '${s.waitingUntilReturn.toLowerCase()} · $name',
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
    );
  }

  Widget _claim(ColorScheme cs, AppStrings s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.waitingClaimTitle,
          style: TextStyle(
            fontFamily: ProfileTheme.bodyFont,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: cs.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          claimName!.isEmpty
              ? s.waitingClaimAsk
              : '${claimName!} — ${s.waitingClaimAsk}',
          style: TextStyle(
            fontFamily: ProfileTheme.displayFont,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: cs.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: onApprove,
                style: FilledButton.styleFrom(
                  shape: const StadiumBorder(),
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                ),
                child: Text(s.waitingClaimYes),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onDecline,
              style: TextButton.styleFrom(
                foregroundColor: cs.onPrimaryContainer,
                shape: const StadiumBorder(),
              ),
              child: Text(s.waitingClaimNo),
            ),
          ],
        ),
      ],
    );
  }
}
