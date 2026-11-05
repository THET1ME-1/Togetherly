import 'package:flutter/material.dart';

import '../../dict_strings.dart';
import '../../theme/profile_theme.dart';
import '../../theme/theme_scope.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/auth/ink.dart';

/// Каким путём вернуть доступ.
enum ForgotWay { partner, email }

/// Лист «Забыли пароль?» (макет «Вход без писем», 1-А): через партнёра или
/// письмом. Партнёр стоит первым: у большинства пара есть, и код приходит за
/// минуту, а письма упираются в квоту почтового сервиса.
///
/// Имя партнёра здесь не показываем: почту может ввести и чужой человек.
Future<ForgotWay?> showForgotPasswordSheet(
  BuildContext context, {
  required String email,
}) {
  final cs = ProfileTheme.schemeFor(context.appTheme);
  return showModalSheet<ForgotWay>(
    context: context,
    isScrollControlled: true,
    backgroundColor: cs.surfaceContainerLow,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => Theme(
      data: ProfileTheme.data(cs),
      child: ForgotPasswordSheet(email: email),
    ),
  );
}

class ForgotPasswordSheet extends StatelessWidget {
  const ForgotPasswordSheet({super.key, required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              trKey('prSheetTitle'),
              style: TextStyle(
                fontFamily: ProfileTheme.displayFont,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              trKey('prSheetFor').replaceAll('{0}', email),
              style: TextStyle(
                fontFamily: ProfileTheme.bodyFont,
                fontSize: 14,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            _WayTile(
              main: true,
              icon: Icons.favorite_rounded,
              title: trKey('prViaPartner'),
              badge: trKey('prFaster'),
              hint: trKey('prViaPartnerHint'),
              onTap: () => Navigator.of(context).pop(ForgotWay.partner),
            ),
            const SizedBox(height: 8),
            _WayTile(
              main: false,
              icon: Icons.mail_rounded,
              title: trKey('prViaEmail'),
              hint: trKey('prViaEmailHint').replaceAll('{0}', email),
              onTap: () => Navigator.of(context).pop(ForgotWay.email),
            ),
          ],
        ),
      ),
    );
  }
}

class _WayTile extends StatelessWidget {
  const _WayTile({
    required this.main,
    required this.icon,
    required this.title,
    required this.hint,
    required this.onTap,
    this.badge,
  });

  final bool main;
  final IconData icon;
  final String title;
  final String hint;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = main
        ? inkOn(cs.primaryContainer, cs.onPrimaryContainer, cs.onSurface)
        : cs.onSurface;
    return Material(
      color: main ? cs.primaryContainer : cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: main ? cs.primary : cs.surface,
                  shape: main ? BoxShape.circle : BoxShape.rectangle,
                  borderRadius: main ? null : BorderRadius.circular(16),
                ),
                child: Icon(
                  icon,
                  color: main ? cs.onPrimary : cs.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontFamily: ProfileTheme.bodyFont,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: fg,
                          ),
                        ),
                        if (badge != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: cs.primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              badge!,
                              style: TextStyle(
                                fontFamily: ProfileTheme.bodyFont,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: cs.onPrimary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hint,
                      style: TextStyle(
                        fontFamily: ProfileTheme.bodyFont,
                        fontSize: 13,
                        height: 1.3,
                        color: fg.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.outline),
            ],
          ),
        ),
      ),
    );
  }
}
