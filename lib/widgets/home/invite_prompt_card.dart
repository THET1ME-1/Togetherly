import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../theme/profile_theme.dart';

/// Приглашение партнёра в слоте подсказки на главной.
///
/// Единственное, что имеет смысл предлагать одиночке: настроение без группы не
/// сохраняется, половина каталога виджетов закрыта, чат и лента ждут второго.
/// Поэтому вместо списка первых действий тут одна карточка с одной кнопкой,
/// а список появляется, когда пара уже собралась.
class InvitePromptCard extends StatelessWidget {
  const InvitePromptCard({
    super.key,
    required this.scheme,
    required this.onInvite,
  });

  final ColorScheme scheme;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.onPrimaryContainer.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.favorite_rounded,
                  size: 22,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.invitePromptTitle,
                      style: TextStyle(
                        fontFamily: ProfileTheme.displayFont,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        fontVariations: const [FontVariation('wght', 700)],
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      s.invitePromptBody,
                      style: TextStyle(
                        fontFamily: ProfileTheme.bodyFont,
                        fontSize: 13,
                        height: 1.35,
                        color: scheme.onPrimaryContainer.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onInvite,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: const StadiumBorder(),
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
              ),
              child: Text(
                s.invitePromptAction,
                style: const TextStyle(
                  fontFamily: ProfileTheme.bodyFont,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
