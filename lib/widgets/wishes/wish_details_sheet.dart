import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/wish.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/fonts.dart';
import '../../theme/profile_theme.dart';
import '../../utils/safe_launch.dart';
import '../app_sheet.dart';

/// Открыть чужое желание целиком.
///
/// В списке описание сжато в одну строку, а править чужое нельзя, поэтому
/// нажатие на желание партнёра раньше не делало ничего: длинное желание было
/// не прочитать (отзыв из Play 02.09.2026).
Future<void> showWishDetailsSheet(
  BuildContext context, {
  required AppTheme theme,
  required Wish wish,
  required String authorName,
}) {
  // Схему снимаем до открытия: лист живёт в навигаторе и переживает экран.
  final scheme = ProfileTheme.themeFor(theme).colorScheme;
  return showAppSheet<void>(
    context,
    background: scheme.surfaceContainer,
    builder: (_) => Theme(
      data: ProfileTheme.data(scheme),
      child: WishDetailsSheet(wish: wish, authorName: authorName),
    ),
  );
}

class WishDetailsSheet extends StatelessWidget {
  const WishDetailsSheet({
    super.key,
    required this.wish,
    required this.authorName,
  });

  final Wish wish;
  final String authorName;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ru = LocaleService.instance.isRussian;
    final hasShopLine = wish.hasPrice || wish.shop.isNotEmpty;

    return SheetScaffold(
      title: wish.title,
      bottom: wish.url.isEmpty
          ? null
          : FilledButton.icon(
              key: const Key('wish-open-link'),
              onPressed: () async {
                final uri = Uri.tryParse(wish.url);
                if (uri == null) return;
                await safeLaunchUrl(uri, mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 20),
              label: Text(ru ? 'Открыть ссылку' : 'Open link'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
            ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (authorName.isNotEmpty)
              Text(
                authorName,
                style: AppFonts.onest(
                    size: 13.5, weight: 600, color: cs.onSurfaceVariant),
              ),
            if (hasShopLine) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (wish.hasPrice)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: cs.secondaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        wish.priceLabel,
                        style: AppFonts.onest(
                            size: 13.5,
                            weight: 700,
                            color: cs.onSecondaryContainer),
                      ),
                    ),
                  if (wish.shop.isNotEmpty)
                    Text(
                      wish.shop,
                      style: AppFonts.onest(
                          size: 13.5, color: cs.onSurfaceVariant),
                    ),
                ],
              ),
            ],
            if (wish.note.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                wish.note,
                style: AppFonts.onest(
                    size: 16, height: 1.45, color: cs.onSurface),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
