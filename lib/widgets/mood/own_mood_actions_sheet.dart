import 'package:flutter/material.dart';

import '../../dict_strings.dart';
import '../../models/custom_mood.dart';
import '../../services/locale_service.dart';
import '../../theme/profile_theme.dart';
import '../../theme/theme_scope.dart';
import '../app_sheet.dart';
import 'mood_form_parts.dart';

/// Что выбрали в листе удержания своего настроения.
enum OwnMoodAction { edit, remove }

/// Удержание своего настроения в сетке выбора.
///
/// Своё можно изменить или убрать. Чужое — только объяснить, кто может: правила
/// коллекции пускают править и удалять одного автора, и раньше удаление чужого
/// молча отбивалось сервером, а настроение оставалось на месте.
Future<OwnMoodAction?> showOwnMoodActions(
  BuildContext context, {
  required CustomMood mood,
  required bool mine,
  String partnerName = '',
}) {
  return showAppSheet<OwnMoodAction>(
    context,
    builder: (_) => _OwnMoodActionsSheet(mood: mood, mine: mine, partnerName: partnerName),
  );
}

class _OwnMoodActionsSheet extends StatelessWidget {
  final CustomMood mood;
  final bool mine;
  final String partnerName;

  const _OwnMoodActionsSheet({required this.mood, required this.mine, required this.partnerName});

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final cs = ProfileTheme.schemeFor(context.appTheme);
    final name = partnerName.trim();
    return SheetScaffold(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                OwnMoodPicture(mood: mood, size: 88),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mood.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Unbounded',
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          height: 1.25,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(color: CustomMood.colorOfScore(mood.score), shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              moodScoreLabel(mood.score),
                              style: TextStyle(fontFamily: 'Onest', fontSize: 13.5, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (mine) ...[
              _ActionButton(
                icon: Icons.edit_rounded,
                label: trKey('customMoodEdit'),
                background: cs.surfaceContainerHighest,
                foreground: cs.onSurface,
                onTap: () => Navigator.of(context).pop(OwnMoodAction.edit),
              ),
              const SizedBox(height: 10),
              _ActionButton(
                icon: Icons.delete_outline_rounded,
                label: s.customMoodDelete,
                background: cs.errorContainer,
                foreground: cs.onErrorContainer,
                onTap: () => Navigator.of(context).pop(OwnMoodAction.remove),
              ),
              const SizedBox(height: 10),
              Text(
                s.customMoodDeleteHint,
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Onest', fontSize: 12.5, color: cs.onSurfaceVariant),
              ),
            ] else ...[
              Text(
                name.isEmpty
                    ? trKey('customMoodOnlyAuthorAnon')
                    : trKey('customMoodOnlyAuthor').replaceAll('{name}', name),
                style: TextStyle(fontFamily: 'Onest', fontSize: 14.5, height: 1.45, color: cs.onSurface),
              ),
              const SizedBox(height: 16),
              _ActionButton(
                label: s.gotIt,
                background: cs.surfaceContainerHighest,
                foreground: cs.onSurface,
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData? icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  const _ActionButton({
    this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontFamily: 'Onest', fontSize: 15, fontWeight: FontWeight.w600),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 22), const SizedBox(width: 8)],
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}
