import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/pair_data.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/profile_theme.dart';
import 'waiting_setup_sheet.dart';

/// Карточка пары, где второе место пока пустует.
///
/// Показывает, кого ждут, сколько осталось, и код второго места — он всегда на
/// виду, чтобы не потерялся за год ожидания. Пришла заявка — та же карточка
/// спрашивает «это он?»: подтверждение обязательно, иначе код из чужих рук
/// пустил бы постороннего в чужую переписку.
class WaitingCard extends StatelessWidget {
  final PairData pair;
  final AppTheme theme;

  const WaitingCard({super.key, required this.pair, required this.theme});

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.themeFor(theme).colorScheme;
    final s = LocaleService.current;
    final days = pair.daysUntilReturn;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  pair.placeholderName.isEmpty
                      ? '?'
                      : pair.placeholderName.characters.first.toUpperCase(),
                  style: TextStyle(
                    fontFamily: ProfileTheme.displayFont,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: cs.onSecondaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            pair.placeholderName,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: ProfileTheme.displayFont,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: cs.tertiaryContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            s.waitingBadge,
                            style: TextStyle(
                              fontFamily: ProfileTheme.bodyFont,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: cs.onTertiaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      days == null
                          ? s.waitingSetupTitle
                          : days <= 0
                              ? s.waitingHomeToday
                              : '${s.waitingUntilReturn} · ${s.waitingDaysLeft(days)}',
                      style: TextStyle(
                        fontFamily: ProfileTheme.bodyFont,
                        fontSize: 13.5,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: s.waitingEditTitle,
                onPressed: () => WaitingSetupSheet.show(
                  context,
                  pair: pair,
                  theme: theme,
                  editing: true,
                ),
                icon: Icon(Icons.edit_rounded, size: 20, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          if (days != null && days > 0) ...[
            const SizedBox(height: 14),
            _ReturnProgress(days: days, color: cs.primary, track: cs.surfaceContainerHighest),
          ],
          if (pair.hasClaimRequest) ...[
            const SizedBox(height: 16),
            _ClaimRequest(pair: pair, cs: cs),
          ] else ...[
            const SizedBox(height: 16),
            _CodeRow(pair: pair, cs: cs),
          ],
        ],
      ),
    );
  }
}

/// Полоса ожидания: сколько уже прошло от объявленного срока.
class _ReturnProgress extends StatelessWidget {
  final int days;
  final Color color;
  final Color track;

  const _ReturnProgress({
    required this.days,
    required this.color,
    required this.track,
  });

  @override
  Widget build(BuildContext context) {
    // Полный срок службы неизвестен, поэтому берём год как привычную мерку:
    // полоса показывает не долю от срока, а «сколько осталось» в понятном виде.
    final left = (days / 365).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: 1 - left,
        minHeight: 8,
        backgroundColor: track,
        color: color,
      ),
    );
  }
}

class _CodeRow extends StatelessWidget {
  final PairData pair;
  final ColorScheme cs;

  const _CodeRow({required this.pair, required this.cs});

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.waitingCodeTitle,
          style: TextStyle(
            fontFamily: ProfileTheme.bodyFont,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: pair.claimToken));
                  HapticFeedback.selectionClick();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(s.waitingCodeCopied)),
                    );
                  }
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          pair.claimToken.isEmpty ? '••••••••' : pair.claimToken,
                          style: TextStyle(
                            fontFamily: ProfileTheme.displayFont,
                            fontSize: 19,
                            letterSpacing: 3,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      Icon(Icons.copy_rounded, size: 18, color: cs.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: s.waitingResetCode,
              onPressed: () async {
                final code = await pair.resetClaimToken();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(code.isEmpty
                        ? s.waitingCreateFailed
                        : '${s.waitingResetCode}: $code'),
                  ),
                );
              },
              icon: Icon(Icons.refresh_rounded, color: cs.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          s.waitingCodeHint,
          style: TextStyle(
            fontFamily: ProfileTheme.bodyFont,
            fontSize: 12,
            height: 1.3,
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// «Кто-то ввёл ваш код» — подтверждение привязки.
class _ClaimRequest extends StatelessWidget {
  final PairData pair;
  final ColorScheme cs;

  const _ClaimRequest({required this.pair, required this.cs});

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
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
            pair.claimName.isEmpty
                ? s.waitingClaimAsk
                : '${pair.claimName} — ${s.waitingClaimAsk}',
            style: TextStyle(
              fontFamily: ProfileTheme.displayFont,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: cs.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => pair.answerClaim(approve: true),
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
                onPressed: () => pair.answerClaim(approve: false),
                style: TextButton.styleFrom(
                  foregroundColor: cs.onPrimaryContainer,
                  shape: const StadiumBorder(),
                ),
                child: Text(s.waitingClaimNo),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
