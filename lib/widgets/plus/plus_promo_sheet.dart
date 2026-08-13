import 'package:flutter/material.dart';

import '../../screens/plus_screen.dart';
import '../../services/locale_service.dart';
import '../../theme/profile_theme.dart';
import '../../theme/theme_scope.dart';
import '../app_sheet.dart';

/// Плашка Togetherly+ на главной — раз в семь часов тем, кто не купил.
///
/// Нижний лист, а не экран: экран целиком выглядит как «купи, иначе не пущу», а
/// человек открывал приложение ради своей пары. Отказаться можно и кнопкой, и
/// свайпом вниз — в обоих случаях следующее напоминание будет через семь часов.
Future<void> showPlusPromoSheet(BuildContext context) async {
  final s = LocaleService.current;
  final t = context.appTheme;
  final cs = ProfileTheme.schemeFor(t);

  final open = await showAppSheet<bool>(
    context,
    builder: (ctx) => SheetScaffold(
      title: s.plusPromoTitle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.plusPromoBody,
              style: TextStyle(
                fontSize: 15,
                height: 1.4,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(s.plusPromoOpen),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(s.plusPromoLater),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  if (open != true || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => PlusScreen(scheme: cs)),
  );
}
