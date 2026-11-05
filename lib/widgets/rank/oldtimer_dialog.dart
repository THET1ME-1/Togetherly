import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../dict_strings.dart';
import '../../models/user_data.dart';
import '../../theme/profile_theme.dart';
import '../common/badge_image.dart';

/// Ключ наградного значка «Старожил» (каталог `badge_old_timer`). Его выдаёт
/// сервер всем аккаунтам, созданным до выхода званий за часы.
const String kOldTimerBadge = 'Old-timer';

const String _shownKey = 'oldtimer_welcome_shown';
bool _open = false;

/// «Вы с нами с самого начала»: один раз, когда у человека появился значок
/// «Старожил». Часы для званий у всех с нуля, а этот значок — знак, что
/// человек был здесь раньше.
Future<void> maybeShowOldTimer(BuildContext context, UserData user) async {
  if (_open || !user.grantedBadges.contains(kOldTimerBadge)) return;
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_shownKey) == true || !context.mounted) return;
  _open = true;
  try {
    await prefs.setBool(_shownKey, true);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => const OldTimerDialog(),
    );
  } finally {
    _open = false;
  }
}

class OldTimerDialog extends StatelessWidget {
  const OldTimerDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BadgeImage(kOldTimerBadge, side: 168),
            const SizedBox(height: 8),
            Text(
              trKey('oldTimerTitle'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: ProfileTheme.displayFont,
                fontSize: 22,
                height: 1.15,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              trKey('oldTimerText'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: ProfileTheme.bodyFont,
                fontSize: 15,
                height: 1.35,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                minimumSize: const Size(140, 52),
                shape: const StadiumBorder(),
                textStyle: const TextStyle(
                  fontFamily: ProfileTheme.bodyFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Text(trKey('hrankNewOk')),
            ),
          ],
        ),
      ),
    );
  }
}
