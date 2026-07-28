import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../theme/profile_theme.dart';
import '../avatar_widget.dart';

/// Подсказка на главной: партнёр давно не заходил.
///
/// Пары гаснут вдвоём, поэтому момент, когда один затих, а второй ещё
/// открывает приложение, — единственный, где можно вмешаться. Одна кнопка,
/// отказ — просто пролистнуть.
///
/// Условия показа считает `QuietPartner`; здесь только вид.
class QuietPartnerCard extends StatelessWidget {
  const QuietPartnerCard({
    super.key,
    required this.scheme,
    required this.partnerUid,
    required this.partnerName,
    required this.partnerAvatarUrl,
    required this.quietDays,
    required this.busy,
    required this.onSend,
  });

  final ColorScheme scheme;
  final String partnerUid;
  final String partnerName;
  final String partnerAvatarUrl;
  final int quietDays;

  /// Отправка идёт — кнопка занята.
  final bool busy;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _avatar(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.quietPartnerTitle(partnerName, quietDays),
                      style: TextStyle(
                        fontFamily: ProfileTheme.displayFont,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        fontVariations: const [FontVariation('wght', 700)],
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      s.quietPartnerBody,
                      style: TextStyle(
                        fontFamily: ProfileTheme.bodyFont,
                        fontSize: 13,
                        height: 1.35,
                        color: scheme.onSurfaceVariant,
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
            child: FilledButton.icon(
              onPressed: busy ? null : onSend,
              icon: busy
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: scheme.onPrimary,
                      ),
                    )
                  : const Icon(Icons.favorite_rounded, size: 18),
              label: Text(
                s.quietPartnerAction,
                style: const TextStyle(
                  fontFamily: ProfileTheme.bodyFont,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: const StadiumBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Тот же аватар, что в остальных местах: сам подставляет живой урл по uid и
  /// рисует букву, когда фото нет.
  Widget _avatar() => AvatarWidget(
        uid: partnerUid,
        fallbackUrl: partnerAvatarUrl,
        name: partnerName,
        size: 44,
        primary: scheme.primary,
      );
}
