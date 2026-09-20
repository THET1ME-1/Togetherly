import 'package:flutter/material.dart';

import '../../models/memory_reaction.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/fonts.dart';
import '../../dict_strings.dart';
import '../app_sheet.dart';
import '../avatar_widget.dart';

/// Кто отметил запись — аватарка и значок.
///
/// Счётчика нет намеренно: в паре двое, и «12 лайков» тут взяться неоткуда.
/// Вместо числа стоит лицо того, кто отметил.
class ReactionChip extends StatelessWidget {
  const ReactionChip({
    super.key,
    required this.uid,
    required this.name,
    required this.avatarUrl,
    required this.reactionKey,
    required this.theme,
    required this.isMine,
    this.onTap,
    this.height = 40,
  });

  final String uid;
  final String name;
  final String avatarUrl;
  final String reactionKey;
  final AppTheme theme;

  /// Своя реакция подсвечена: её снимают тем же нажатием.
  final bool isMine;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final r = reactionByKey(reactionKey);
    // Своя отметка подсвечена тональным контейнером: её снимают тем же
    // нажатием, и человеку надо видеть, что отметка именно его.
    final bg = isMine ? theme.primaryLight : theme.bgGradient[0];
    final avatar = height - 12;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(height / 2),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(4, 0, height * 0.3, 0),
          child: SizedBox(
            height: height,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AvatarWidget(
                  uid: uid,
                  liveUrl: avatarUrl,
                  name: name,
                  size: avatar,
                  primary: theme.primary,
                ),
                const SizedBox(width: 6),
                Icon(r.icon, size: height * 0.45, color: theme.fillColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Кнопка «поставить реакцию»: круглая, открывает выбор значка.
class AddReactionButton extends StatelessWidget {
  const AddReactionButton({
    super.key,
    required this.theme,
    required this.onPick,
    this.height = 40,
  });

  final AppTheme theme;
  final ValueChanged<String> onPick;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.bgGradient[0],
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          final picked = await showReactionPicker(context, theme);
          if (picked != null) onPick(picked);
        },
        child: SizedBox(
          width: height,
          height: height,
          child: Icon(Icons.add_reaction_outlined,
              size: height * 0.5, color: theme.textSecondary),
        ),
      ),
    );
  }
}

/// Лист выбора значка: шесть штук в ряд, подпись под каждым.
Future<String?> showReactionPicker(BuildContext context, AppTheme theme) {
  return showAppSheet<String>(
    context,
    builder: (ctx) => SheetScaffold(
      title: LocaleService.current.reactionPickTitle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final r in kMemoryReactions)
              SizedBox(
                width: 96,
                child: Material(
                  color: theme.cardSurface,
                  borderRadius: BorderRadius.circular(20),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.pop(ctx, r.key),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Column(
                        children: [
                          Icon(r.icon, size: 30, color: theme.fillColor),
                          const SizedBox(height: 6),
                          Text(
                            trKey(r.dictKey),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppFonts.onest(
                                size: 12.5,
                                weight: 600,
                                color: theme.textPrimary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
